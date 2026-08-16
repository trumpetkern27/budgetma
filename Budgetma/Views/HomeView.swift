import SwiftUI
import SwiftData

/* --- Home ---
 * the glance: a calendar of what's coming
 *
 * the calendar period is itself defined by a recurrence rule (Settings > Calendar
 * frequency), so "my pay period" can be biweekly, or every 10 days, or monthly --
 * the grid doesn't assume months any more than the rest of the app does. the
 * period maths lives in PeriodRule, shared with the Budget screen so the two
 * always agree on which window you're in.
 */
@available(iOS 26, *)
struct HomeView: View {
	@EnvironmentObject var theme: ThemeManager

	// how the calendar chunks time -- arbitrary, like everything else
	@AppStorage("calendarViewFrequency") private var frequency: Calendar.RecurrenceRule.Frequency = .monthly
	@AppStorage("calendarViewInterval") private var interval: Int = 1
	@AppStorage("calendarViewStartDate") private var periodStart: Date = .now

	@Query private var expectedIncomes: [ExpectedIncome]
	@Query private var expectedExpenses: [ExpectedExpense]
	@Query private var envelopes: [Envelope]
	@Query private var goals: [Goal]
	@Query private var overrides: [OccurrenceOverride]
	@Query private var amendments: [ScheduleAmendment]
	@Query private var suspensions: [ScheduleSuspension]
	@Query private var transactions: [Transaction]

	@State private var periodOffset: Int = 0
	@State private var inspectedDay: InspectedDay?

	/// Date isn't Identifiable and shouldn't be taught to be -- a retroactive
	/// conformance on a stdlib type is somebody else's bug waiting to happen
	private struct InspectedDay: Identifiable {
		let id: Date
	}

	/* the projection is computed once per change and held, rather than being a
	 * computed property. as a computed property it re-ran on every access -- and
	 * `dayCell` accessed it once per cell, so opening the month projected every
	 * schedule in the app thirty-odd times over.
	 */
	@State private var events: [ScheduledEvent] = []
	@State private var eventsByDay: [Date: [ScheduledEvent]] = [:]
	/// the reconciled view of the period: which occurrences have been settled,
	/// and what was actually logged on each day
	@State private var lines: [ReconciliationService.Line] = []
	@State private var actualsByDay: [Date: [Transaction]] = [:]
	/// occurrence ids that something has already been logged against
	@State private var settledIDs: Set<String> = []
	@State private var trackingPoints: [WindowTrackingChart.Point] = []

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	private var rule: PeriodRule {
		PeriodRule(anchor: periodStart, frequency: frequency, interval: interval)
	}

	private var period: BudgetPeriod { rule.period(offset: periodOffset) }

	private var snapshots: [ScheduleSnapshot] {
		BudgetService.snapshots(
			incomes: expectedIncomes,
			expenses: expectedExpenses,
			envelopes: envelopes,
			goals: goals,
			amendments: amendments,
			suspensions: suspensions
		)
	}

	/// everything the grid depends on, flattened -- drives the recompute

	/// amendments change what an occurrence is worth without changing the item's
	/// own fields, so the snapshot signature alone can't see them
	private var amendmentSignature: String {
		let changes = amendments
			.map { "\($0.effectiveFrom.timeIntervalSince1970)|\($0.amount)" }
			.joined(separator: ",")
		let paused = suspensions
			.map { "\($0.from.timeIntervalSince1970)|\($0.until?.timeIntervalSince1970 ?? 0)" }
			.joined(separator: ",")
		return changes + "/" + paused
	}

	private var inputSignature: String {
		let items = snapshots
			.map { "\($0.name)|\($0.amount)|\($0.start.timeIntervalSince1970)|\($0.kind.rawValue)|\($0.rule == nil ? 0 : 1)" }
			.joined(separator: ";")
		let actuals = transactions
			.map { "\($0.persistentModelID.hashValue)|\($0.amount)|\($0.date.timeIntervalSince1970)" }
			.joined(separator: ";")
		return "\(period.start.timeIntervalSince1970)-\(period.end.timeIntervalSince1970)"
			+ "|\(overrides.count)|\(amendmentSignature)|\(items)|\(actuals)"
	}

	private var groupedByDay: [(day: Date, items: [ScheduledEvent])] {
		eventsByDay.keys.sorted().map { ($0, eventsByDay[$0]!) }
	}

	private var totalIncome: Decimal { events.filter(\.isInflow).reduce(0) { $0 + $1.amount } }
	private var totalExpense: Decimal { events.filter { !$0.isInflow }.reduce(0) { $0 + $1.amount } }

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				periodHeader
				calendarGrid
				summaryCard
				upcomingCard
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.chartPalette(for: theme.bgColour)
		.navigationTitle("Budgetma")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarLeading) {
				NavigationLink {
					HistoryView()
				} label: {
					Image(systemName: "clock.arrow.circlepath")
				}
			}
			ToolbarItem(placement: .primaryAction) {
				NavigationLink {
					LogTransactionView()
				} label: {
					Image(systemName: "plus.circle.fill")
				}
			}
		}
		.task(id: inputSignature) { recompute() }
		.sheet(item: $inspectedDay) { inspected in
			NavigationStack {
				DayDetailView(
					day: inspected.id,
					expected: eventsByDay[inspected.id] ?? [],
					actuals: actualsByDay[inspected.id] ?? [],
					settledIDs: settledIDs
				)
			}
		}
	}

	// MARK: - Compute

	private func recompute() {
		let calendar = Calendar.current
		let projected = CashflowProjector.events(
			for: snapshots,
			overrides: OverrideIndex(overrides),
			in: period.range
		)
		events = projected
		eventsByDay = Dictionary(grouping: projected) {
			calendar.startOfDay(for: $0.date)
		}
		.mapValues { $0.sorted { $0.date < $1.date } }

		// same reconciliation the Budget screen runs, so "settled" means the same
		// thing on both -- there is only one definition of it in the app
		let summary = ReconciliationService.summary(
			events: projected,
			actuals: transactions.filter { period.contains($0.date) || $0.occurrenceDate != nil },
			in: period.range
		)
		lines = summary.lines
		settledIDs = Set(summary.lines.filter(\.hasActuals).map(\.id))

		actualsByDay = Dictionary(
			grouping: transactions.filter { period.contains($0.date) }
		) {
			calendar.startOfDay(for: $0.date)
		}
		.mapValues { $0.sorted { $0.date < $1.date } }

		trackingPoints = buildTrackingPoints(events: projected, calendar: calendar)
	}

	/// planned vs actual as a running total across the period -- the same shape
	/// the Budget screen draws, at a glance size
	private func buildTrackingPoints(
		events: [ScheduledEvent],
		calendar: Calendar
	) -> [WindowTrackingChart.Point] {
		let today = calendar.startOfDay(for: .now)
		let days = rule.days(in: period, calendar: calendar)
		guard !days.isEmpty else { return [] }

		let plan = events.sorted { $0.date < $1.date }
		let logged = transactions
			.filter { period.contains($0.date) }
			.sorted { $0.date < $1.date }

		var plannedRunning: Decimal = 0
		var actualRunning: Decimal = 0
		var planIndex = 0
		var loggedIndex = 0

		return days.map { day in
			let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day

			while planIndex < plan.count, plan[planIndex].date < dayEnd {
				plannedRunning += plan[planIndex].signedAmount
				planIndex += 1
			}
			while loggedIndex < logged.count, logged[loggedIndex].date < dayEnd {
				let transaction = logged[loggedIndex]
				actualRunning += transaction is Income ? transaction.amount : -transaction.amount
				loggedIndex += 1
			}

			// the future has no actuals; a flat line across it would read as
			// "spent nothing" rather than "hasn't happened yet"
			return WindowTrackingChart.Point(
				date: day,
				planned: plannedRunning,
				actual: day <= today ? actualRunning : nil
			)
		}
	}

	// MARK: - Period

	private var periodHeader: some View {
		HStack {
			// paging back is unbounded now: the old version generated occurrences
			// forward from the anchor, so with the anchor at "today" there was
			// nothing behind you to page into
			Button { periodOffset -= 1 } label: { Image(systemName: "chevron.left") }

			Spacer()

			VStack(spacing: 2) {
				Text(period.start.formatted(.dateTime.month(.wide).year()))
					.font(.headline)
				Text(period.label())
					.font(.caption2)
					.foregroundStyle(theme.fgColour.opacity(0.55))
				if periodOffset != 0 {
					Button("Back to today") { periodOffset = 0 }
						.font(.caption2)
				}
			}

			Spacer()

			Button { periodOffset += 1 } label: { Image(systemName: "chevron.right") }
		}
		.tint(theme.fgColour)
	}

	// MARK: - Calendar

	/* the grid is drawn eagerly, a row at a time.
	 *
	 * it used to be a LazyVGrid, which is what made the cell borders vanish and
	 * come back as you scrolled: lazy containers discard and rebuild cells as they
	 * leave and re-enter the viewport, and rebuilding one was expensive enough
	 * (see the note on `events` above) to drop frames mid-scroll. a period is at
	 * most six rows of seven -- there was never anything to be lazy about.
	 */
	var calendarGrid: some View {
		VStack(spacing: 0) {
			HStack(spacing: 0) {
				// keyed by position, not value -- S/M/T/W/T/F/S repeats letters
				// and \.self makes SwiftUI collapse the duplicates
				ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
					Text(symbol)
						.font(.caption)
						.foregroundStyle(theme.fgColour.opacity(0.6))
						.frame(maxWidth: .infinity)
				}
			}
			.padding(.bottom, 6)

			VStack(spacing: 0) {
				ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
					HStack(spacing: 0) {
						ForEach(week) { cell in
							cellView(cell)
						}
					}
				}
			}
		}
	}

	private struct CalendarCell: Identifiable {
		let id: Int
		let date: Date?
	}

	@ViewBuilder
	private func cellView(_ cell: CalendarCell) -> some View {
		if let date = cell.date {
			dayCell(for: date)
		} else {
			// a blank still draws its border, so the grid stays a grid
			Color.clear
				.frame(maxWidth: .infinity)
				.frame(height: cellHeight)
				.overlay { Rectangle().stroke(theme.fgColour.opacity(0.15), lineWidth: 1) }
		}
	}

	private let cellHeight: CGFloat = 56

	/// leading blanks + the period's days + trailing blanks, so every row is full
	private var calendarCells: [CalendarCell] {
		let days = rule.days(in: period)
		guard let first = days.first else { return [] }

		let calendar = Calendar.current
		let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7

		var cells = (0..<leading).map { CalendarCell(id: $0, date: nil) }
		cells += days.enumerated().map { CalendarCell(id: leading + $0.offset, date: $0.element) }

		let remainder = cells.count % 7
		if remainder != 0 {
			let trailing = 7 - remainder
			cells += (0..<trailing).map { CalendarCell(id: cells.count + $0, date: nil) }
		}
		return cells
	}

	private var weeks: [[CalendarCell]] {
		stride(from: 0, to: calendarCells.count, by: 7).map {
			Array(calendarCells[$0 ..< min($0 + 7, calendarCells.count)])
		}
	}

	private var weekdaySymbols: [String] {
		let calendar = Calendar.current
		let symbols = calendar.veryShortWeekdaySymbols
		let offset = calendar.firstWeekday - 1
		return Array(symbols[offset...] + symbols[..<offset])
	}

	private func dayCell(for date: Date) -> some View {
		let calendar = Calendar.current
		let day = calendar.startOfDay(for: date)
		let isToday = calendar.isDateInToday(date)
		let dayItems = eventsByDay[day] ?? []
		let dayActuals = actualsByDay[day] ?? []
		let net = dayItems.reduce(Decimal(0)) { $0 + $1.signedAmount }
		let hasAnything = !dayItems.isEmpty || !dayActuals.isEmpty

		return Button {
			guard hasAnything else { return }
			inspectedDay = InspectedDay(id: day)
		} label: {
			VStack(spacing: 2) {
				Text("\(calendar.component(.day, from: date))")
					.font(.caption)
					.frame(width: 26, height: 20)
					.background(isToday ? theme.fgColour : .clear)
					.foregroundColor(isToday ? theme.bgColour : theme.fgColour)
					.clipShape(Circle())

				Text(net.moneyRounded)
					.font(.system(size: 9, weight: .medium))
					.monospacedDigit()
					.lineLimit(1)
					.minimumScaleFactor(0.6)
					.foregroundStyle(net >= 0 ? palette.inflow : palette.outflow)
					.opacity(dayItems.isEmpty ? 0 : 1)
					.padding(.horizontal, 2)

				// a dot per logged actual, so the grid shows what really happened
				// and not only what was meant to
				if !dayActuals.isEmpty {
					HStack(spacing: 2) {
						ForEach(0..<min(dayActuals.count, 4), id: \.self) { _ in
							Circle()
								.fill(theme.fgColour.opacity(0.55))
								.frame(width: 3, height: 3)
						}
					}
				}
			}
			.padding(.top, 5)
			.frame(maxWidth: .infinity, alignment: .top)
			.frame(height: cellHeight)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.overlay { Rectangle().stroke(theme.fgColour.opacity(0.15), lineWidth: 1) }
	}

	// MARK: - Cards

	/* three numbers told you the totals but not the shape: whether the money
	 * arrives before the bills or after it, and where in the period you are
	 * standing right now. the curve says both, and the figures still sit under
	 * it for when you just want the total.
	 */
	private var summaryCard: some View {
		let net = totalIncome - totalExpense

		return Card(title: "This period") {
			VStack(alignment: .leading, spacing: 12) {
				WindowTrackingChart(points: trackingPoints, height: 150)

				Divider().background(theme.fgColour.opacity(0.15))

				HStack(alignment: .top, spacing: 12) {
					StatTile(label: "In", value: totalIncome.moneyCompact, accent: palette.inflow)
					StatTile(label: "Out", value: totalExpense.moneyCompact, accent: palette.outflow)
					StatTile(
						label: "Net",
						value: net.moneySigned,
						accent: net == 0 ? theme.fgColour : (net > 0 ? palette.good : palette.critical),
						systemImage: net >= 0 ? "arrow.up.right" : "arrow.down.right"
					)
				}
			}
		}
	}

	/* --- coming up ---
	 * what's still outstanding. anything you've already logged against drops off:
	 * a list headed "coming up" that keeps showing last week's settled rent is
	 * just a list of things you have to mentally filter yourself.
	 */
	private var outstandingByDay: [(day: Date, items: [ScheduledEvent])] {
		groupedByDay.compactMap { group in
			let remaining = group.items.filter { !settledIDs.contains($0.id) }
			return remaining.isEmpty ? nil : (group.day, remaining)
		}
	}

	private var settledCount: Int {
		events.filter { settledIDs.contains($0.id) }.count
	}

	@ViewBuilder
	private var upcomingCard: some View {
		Card(
			title: "Coming up",
			subtitle: settledCount > 0 ? "\(settledCount) already settled, hidden" : nil
		) {
			if events.isEmpty {
				Text("Nothing expected in this period.")
					.font(.callout)
					.foregroundStyle(theme.fgColour.opacity(0.6))
			} else if outstandingByDay.isEmpty {
				HStack(spacing: 8) {
					Image(systemName: "checkmark.circle.fill")
						.foregroundStyle(palette.good)
					Text("Everything this period is logged.")
						.font(.callout)
						.foregroundStyle(theme.fgColour.opacity(0.7))
				}
			} else {
				VStack(spacing: 0) {
					ForEach(outstandingByDay, id: \.day) { group in
						HStack {
							Text(group.day, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
								.font(.caption.weight(.semibold))
								.foregroundStyle(theme.fgColour.opacity(0.65))
							Spacer()
						}
						.padding(.top, 10)
						.padding(.bottom, 4)

						ForEach(group.items) { item in
							NavigationLink {
								LogTransactionView(prefill: item)
							} label: {
								HStack {
									Text("\(item.emoji)  \(item.name)")
										.font(.subheadline)
										.lineLimit(1)
									Spacer()
									Text(item.amount.money)
										.font(.subheadline)
										.monospacedDigit()
										.foregroundStyle(item.isInflow ? palette.inflow : theme.fgColour)
								}
								.padding(.vertical, 5)
								.contentShape(Rectangle())
							}
							.buttonStyle(.plain)
						}
					}
				}
			}
		}
	}
}
