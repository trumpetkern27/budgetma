import SwiftUI
import SwiftData

/* --- Budget ---
 * the window view: what you planned, against what actually happened
 *
 * by default the window is your pay period -- the same PeriodRule Home's calendar
 * uses, so "this window" means the same thing on both screens. it used to snap to
 * a calendar week/month boundary instead, which put a fortnightly budget
 * permanently off-cycle from the fortnight you're actually being paid on. turn
 * "Follow my pay period" off to drive it with an arbitrary count+unit instead.
 */
@available(iOS 26, *)
struct BudgetView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context

	@Query private var expectedIncomes: [ExpectedIncome]
	@Query private var expectedExpenses: [ExpectedExpense]
	@Query private var envelopes: [Envelope]
	@Query private var goals: [Goal]
	@Query private var overrides: [OccurrenceOverride]
	@Query private var amendments: [ScheduleAmendment]
	@Query private var suspensions: [ScheduleSuspension]
	@Query private var transactions: [Transaction]

	@AppStorage("budgetFollowsPeriod") private var followsPeriod: Bool = true
	@AppStorage("budgetWindowCount") private var windowCount: Int = 2
	@AppStorage("budgetWindowUnit") private var windowUnitRaw: String = DateWindow.Unit.week.rawValue

	// the pay-period definition, shared with Home
	@AppStorage("calendarViewFrequency") private var frequency: Calendar.RecurrenceRule.Frequency = .monthly
	@AppStorage("calendarViewInterval") private var interval: Int = 1
	@AppStorage("calendarViewStartDate") private var periodStart: Date = .now

	@State private var page: Int = 0

	/* everything below is computed once per change and held.
	 *
	 * this screen was slow for one reason: `summary` was a computed property that
	 * re-projected every schedule *and* re-ran reconciliation on every single
	 * access -- and the body touched it about twenty times per render (eleven in
	 * the stat tiles alone). the work was always cheap; doing it twenty times over
	 * was not.
	 */
	@State private var summary: ReconciliationService.Summary?
	@State private var envelopeLines: [EnvelopeLine] = []
	@State private var trackingPoints: [WindowTrackingChart.Point] = []

	/// which drill-down sheet is open, if any
	@State private var detail: Detail?
	@State private var expandedEnvelopes: Set<String> = []
	@State private var showsFullBreakdown = false

	enum Detail: String, Identifiable {
		case planned, actual, drift, unplanned
		var id: String { rawValue }
	}

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	// MARK: - Window

	private var rule: PeriodRule {
		PeriodRule(anchor: periodStart, frequency: frequency, interval: interval)
	}

	private var window: DateWindow {
		DateWindow(
			count: windowCount,
			unit: DateWindow.Unit(rawValue: windowUnitRaw) ?? .week
		)
		.aligned()
		.offset(by: page)
	}

	private var windowBinding: Binding<DateWindow> {
		Binding(
			get: { window },
			set: { windowCount = $0.count; windowUnitRaw = $0.unit.rawValue }
		)
	}

	/// the range on screen: the pay period you're standing in, or the manual window
	private var range: Range<Date> {
		followsPeriod ? rule.period(offset: page).range : window.range()
	}

	private var rangeLabel: String {
		range.lowerBound.formatted(.dateTime.month(.abbreviated).day()) + " – "
			+ range.upperBound.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day())
	}

	// MARK: - Recompute

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

	/// everything the window depends on. actuals are included by id+amount+date so
	/// logging or editing a transaction refreshes the screen, but merely scrolling
	/// it doesn't.

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
		let plan = snapshots
			.map { "\($0.name)|\($0.amount)|\($0.start.timeIntervalSince1970)|\($0.kind.rawValue)|\($0.rule == nil ? 0 : 1)" }
			.joined(separator: ";")
		let actuals = transactions
			.map { "\($0.persistentModelID.hashValue)|\($0.amount)|\($0.date.timeIntervalSince1970)|\($0.expected?.persistentModelID.hashValue ?? 0)" }
			.joined(separator: ";")
		return "\(range.lowerBound.timeIntervalSince1970)-\(range.upperBound.timeIntervalSince1970)"
			+ "|\(overrides.count)|\(amendmentSignature)|\(plan)|\(actuals)"
	}

	private func recompute() {
		let events = CashflowProjector.events(
			for: snapshots,
			overrides: OverrideIndex(overrides),
			in: range
		)

		summary = ReconciliationService.summary(
			events: events,
			actuals: transactions.filter { range.contains($0.date) || $0.occurrenceDate != nil },
			in: range
		)

		envelopeLines = buildEnvelopeLines()
		trackingPoints = buildTrackingPoints(events: events)
	}

	/* the running-total series behind the tracking chart.
	 *
	 * one sweep per curve rather than a filter per day: a 3-month window is ~90
	 * days, and re-filtering every event and every actual per day is the same
	 * quadratic mistake this screen just had beaten out of it.
	 */
	private func buildTrackingPoints(events: [ScheduledEvent]) -> [WindowTrackingChart.Point] {
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: .now)

		var days: [Date] = []
		var cursor = calendar.startOfDay(for: range.lowerBound)
		while cursor < range.upperBound && days.count < 400 {
			days.append(cursor)
			guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
			cursor = next
		}
		guard !days.isEmpty else { return [] }

		let plan = events.sorted { $0.date < $1.date }
		let logged = transactions
			.filter { range.contains($0.date) }
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

			// the future has no actuals; drawing the line flat across it would
			// read as "spent nothing all week" rather than "hasn't happened yet"
			return WindowTrackingChart.Point(
				date: day,
				planned: plannedRunning,
				actual: day <= today ? actualRunning : nil
			)
		}
	}

	/// expected vs actual, rolled up by category name
	private var categoryRows: [ExpectedVsActualChart.Row] {
		guard let summary else { return [] }
		let outflows = summary.lines.filter { !$0.isInflow }
		let grouped = Dictionary(grouping: outflows) { $0.name }
		return grouped
			.map { name, lines in
				ExpectedVsActualChart.Row(
					label: name,
					emoji: lines.first?.emoji ?? "💸",
					expected: lines.reduce(0) { $0 + $1.expectedAmount },
					actual: lines.reduce(0) { $0 + $1.actualAmount }
				)
			}
			.sorted { $0.expected > $1.expected }
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				windowHeader

				if let summary {
					summaryTiles(summary)

					trackingCard

					if !categoryRows.isEmpty {
						breakdownCard
					}

					scheduleCard(summary)

					if !summary.unplanned.isEmpty {
						unplannedCard(summary)
					}
				} else {
					loadingCard
				}

				if !envelopeLines.isEmpty {
					envelopeCard
				}
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.chartPalette(for: theme.bgColour)
		.navigationTitle("Budget")
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
		.sheet(item: $detail) { detail in
			NavigationStack {
				if let summary {
					BudgetDetailView(detail: detail, summary: summary, range: range)
				}
			}
		}
	}

	// MARK: - Cards

	@ViewBuilder
	private var trackingCard: some View {
		Card(
			title: "Tracking",
			subtitle: "Running total across the window · drag to inspect"
		) {
			WindowTrackingChart(points: trackingPoints)
		}
	}

	/* the per-item comparison, which is now the *second* thing on the card rather
	 * than the only thing. it was capped at 8 rows with no way to see the rest.
	 */
	private var breakdownCard: some View {
		Card(title: "By item", subtitle: "Planned against what you logged") {
			VStack(alignment: .leading, spacing: 12) {
				ExpectedVsActualChart(rows: visibleCategoryRows)

				if categoryRows.count > collapsedRowLimit {
					Button {
						withAnimation(.easeInOut(duration: 0.18)) { showsFullBreakdown.toggle() }
					} label: {
						HStack {
							Text(showsFullBreakdown
								 ? "Show top \(collapsedRowLimit)"
								 : "Show all \(categoryRows.count) items")
								.font(.caption)
							Spacer()
							Image(systemName: showsFullBreakdown ? "chevron.up" : "chevron.down")
								.font(.caption2)
						}
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.foregroundStyle(theme.fgColour.opacity(0.7))
				}
			}
		}
	}

	private let collapsedRowLimit = 8

	private var visibleCategoryRows: [ExpectedVsActualChart.Row] {
		showsFullBreakdown ? categoryRows : Array(categoryRows.prefix(collapsedRowLimit))
	}

	// MARK: - Header

	private var windowHeader: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Button { page -= 1 } label: {
					Image(systemName: "chevron.left")
				}

				Spacer()

				VStack(spacing: 2) {
					Text(rangeLabel)
						.font(.headline)
					if page != 0 {
						Button("Back to today") { page = 0 }
							.font(.caption2)
					} else if followsPeriod {
						Text("Current pay period")
							.font(.caption2)
							.foregroundStyle(theme.fgColour.opacity(0.5))
					}
				}

				Spacer()

				Button { page += 1 } label: {
					Image(systemName: "chevron.right")
				}
			}
			.tint(theme.fgColour)

			Toggle(isOn: $followsPeriod) {
				Text("Follow my pay period")
					.font(.caption)
			}
			.tint(theme.fgColour)

			if !followsPeriod {
				WindowPicker(
					window: windowBinding,
					presets: [
						DateWindow(count: 1, unit: .week),
						DateWindow(count: 2, unit: .week),
						DateWindow(count: 1, unit: .month),
						DateWindow(count: 3, unit: .month)
					]
				)
			}
		}
	}

	/// only ever on screen before the first recompute lands -- an empty window
	/// still produces a Summary, it just has no lines in it
	private var loadingCard: some View {
		Card {
			HStack {
				Spacer()
				ProgressView().tint(theme.fgColour)
				Spacer()
			}
			.frame(height: 80)
		}
	}

	@ViewBuilder
	private func summaryTiles(_ summary: ReconciliationService.Summary) -> some View {
		let expectedNet = summary.expectedNet
		let actualNet = summary.actualNet
		// drift is only honest against the part of the window that's happened
		let asOf = min(Date.now, range.upperBound)
		let expectedSoFar = summary.expectedNet(through: asOf)
		let drift = actualNet - expectedSoFar
		let isPast = range.upperBound <= Date.now

		VStack(spacing: 12) {
			HStack(alignment: .top, spacing: 12) {
				tappableTile(.planned) {
					StatTile(
						label: "Planned net",
						value: expectedNet.moneySigned,
						accent: accent(for: expectedNet),
						caption: "\(summary.expectedInflow.moneyCompact) in · \(summary.expectedOutflow.moneyCompact) out",
						showsDisclosure: true
					)
				}
				tappableTile(.actual) {
					StatTile(
						label: "Actual net",
						value: actualNet.moneySigned,
						accent: accent(for: actualNet),
						caption: "\(summary.actualInflow.moneyCompact) in · \(summary.actualOutflow.moneyCompact) out",
						showsDisclosure: true
					)
				}
			}

			HStack(alignment: .top, spacing: 12) {
				tappableTile(.drift) {
					StatTile(
						label: isPast ? "Drift" : "Drift so far",
						value: drift.moneySigned,
						accent: accent(for: drift),
						caption: isPast
							? (drift >= 0 ? "Better than planned" : "Worse than planned")
							: "vs \(expectedSoFar.moneySigned) planned by now",
						systemImage: drift >= 0 ? "arrow.up.right" : "arrow.down.right",
						showsDisclosure: true
					)
				}
				tappableTile(.unplanned) {
					StatTile(
						label: "Unplanned",
						value: summary.unplannedTotal.moneyCompact,
						accent: summary.unplanned.isEmpty ? theme.fgColour : palette.warning,
						caption: "\(summary.unplanned.count) transaction\(summary.unplanned.count == 1 ? "" : "s")",
						showsDisclosure: true
					)
				}
			}
		}
	}

	/// green means "ahead", red means "behind" -- an untouched window is neither
	private func accent(for value: Decimal) -> Color {
		guard value != 0 else { return theme.fgColour }
		return value > 0 ? palette.good : palette.critical
	}

	/// every headline number opens the rows it was added up from
	private func tappableTile<Content: View>(
		_ target: Detail,
		@ViewBuilder content: () -> Content
	) -> some View {
		Button { detail = target } label: {
			content().contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}

	// MARK: - Schedule

	private func scheduleCard(_ summary: ReconciliationService.Summary) -> some View {
		Card(title: "This window", subtitle: "Tap anything to log what really happened") {
			if summary.lines.isEmpty {
				Text("Nothing scheduled in this window.")
					.font(.callout)
					.foregroundStyle(theme.fgColour.opacity(0.6))
			} else {
				VStack(spacing: 0) {
					ForEach(summary.lines) { line in
						NavigationLink {
							if let existing = line.actuals.first {
								LogTransactionView(editing: existing)
							} else {
								LogTransactionView(prefill: line.event)
							}
						} label: {
							lineRow(line)
						}
						.buttonStyle(.plain)
						.contextMenu { overrideMenu(for: line) }

						if line.id != summary.lines.last?.id {
							Divider().background(theme.fgColour.opacity(0.15))
						}
					}
				}
			}
		}
	}

	private func lineRow(_ line: ReconciliationService.Line) -> some View {
		let status = line.status()
		let (color, icon) = style(for: status)

		return HStack(spacing: 10) {
			Text(line.emoji)
				.font(.body)

			VStack(alignment: .leading, spacing: 2) {
				Text(line.name)
					.font(.subheadline)
					.lineLimit(1)
				HStack(spacing: 5) {
					Image(systemName: icon)
						.font(.system(size: 9))
						.foregroundStyle(color)
					Text(statusLabel(status))
						.font(.caption2)
						.foregroundStyle(color)
					Text("· \(line.date.formatted(.dateTime.month(.abbreviated).day()))")
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.5))
				}
			}

			Spacer()

			VStack(alignment: .trailing, spacing: 2) {
				Text(line.expectedAmount.money)
					.font(.subheadline)
					.monospacedDigit()
					.foregroundStyle(line.isInflow ? palette.inflow : theme.fgColour)

				if line.hasActuals {
					Text(line.actualAmount.money)
						.font(.caption2)
						.monospacedDigit()
						.foregroundStyle(color)
				}
			}
		}
		.padding(.vertical, 10)
		.contentShape(Rectangle())
	}

	@ViewBuilder
	private func overrideMenu(for line: ReconciliationService.Line) -> some View {
		if let sourceID = line.sourceID,
		   let expected = context.model(for: sourceID) as? ExpectedTransaction {
			Button {
				BudgetService(context: context).setOverride(
					for: expected,
					on: line.occurrenceDate,
					isSkipped: true
				)
			} label: {
				Label("Skip this occurrence", systemImage: "calendar.badge.minus")
			}

			if overrideExists(for: expected, on: line.occurrenceDate) {
				Button {
					BudgetService(context: context).setOverride(
						for: expected,
						on: line.occurrenceDate
					)
				} label: {
					Label("Clear exception", systemImage: "arrow.uturn.backward")
				}
			}
		}
	}

	private func overrideExists(for expected: ExpectedTransaction, on date: Date) -> Bool {
		BudgetService(context: context).override(for: expected, on: date) != nil
	}

	// MARK: - Unplanned

	private func unplannedCard(_ summary: ReconciliationService.Summary) -> some View {
		Card(
			title: "Unplanned",
			subtitle: "Real spending that didn't settle anything you'd planned"
		) {
			VStack(spacing: 0) {
				ForEach(summary.unplanned) { transaction in
					NavigationLink {
						LogTransactionView(editing: transaction)
					} label: {
						HStack {
							Text(transaction.category?.emoji ?? "❓")
							VStack(alignment: .leading, spacing: 2) {
								Text(transaction.name)
									.font(.subheadline)
									.lineLimit(1)
								Text(transaction.date.formatted(.dateTime.month(.abbreviated).day()))
									.font(.caption2)
									.foregroundStyle(theme.fgColour.opacity(0.5))
							}
							Spacer()
							Text(transaction.amount.money)
								.font(.subheadline)
								.monospacedDigit()
								.foregroundStyle(transaction is Income ? palette.inflow : palette.warning)
						}
						.padding(.vertical, 8)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
			}
		}
	}

	// MARK: - Envelopes

	/* an envelope's funding cycle is its own, and has nothing to do with the
	 * window you happen to be looking at -- a fortnightly window can contain two
	 * grocery cycles, or half of one six-weekly barber cycle. so every cycle that
	 * *overlaps* the window gets its own row, captioned with the dates it actually
	 * covers.
	 */
	struct EnvelopeLine: Identifiable {
		let id: String
		let name: String
		let emoji: String
		let period: EnvelopeLedger.Period
		/// true when this cycle is the one happening right now
		let isCurrent: Bool
	}

	private func buildEnvelopeLines() -> [EnvelopeLine] {
		let calendar = Calendar.current
		let expenses = transactions.compactMap { $0 as? Expense }

		// look back far enough to build an honest carryover chain, and forward far
		// enough that the last overlapping cycle reports its true end rather than
		// being truncated at the window edge
		let lookback = calendar.date(byAdding: .year, value: -2, to: range.lowerBound) ?? range.lowerBound
		let lookahead = calendar.date(byAdding: .year, value: 1, to: range.upperBound) ?? range.upperBound

		let index = AmendmentIndex(amendments)
		let paused = SuspensionIndex(suspensions)

		return envelopes.flatMap { envelope -> [EnvelopeLine] in
			let periods = EnvelopeLedger.periods(
				for: envelope,
				expenses: expenses,
				in: lookback..<lookahead,
				amendments: index.points(for: envelope.persistentModelID),
				suspensions: paused.spans(for: envelope.persistentModelID),
				calendar: calendar
			)

			return periods
				.filter { $0.end > range.lowerBound && $0.start < range.upperBound }
				.map { period in
					EnvelopeLine(
						id: "\(envelope.persistentModelID.hashValue)-\(period.start.timeIntervalSince1970)",
						name: envelope.name,
						emoji: envelope.category?.emoji ?? "✉️",
						period: period,
						isCurrent: period.contains(.now)
					)
				}
		}
		.sorted { $0.period.start < $1.period.start }
	}

	private var envelopeCard: some View {
		Card(title: "Envelopes", subtitle: "Every funding cycle that touches this window") {
			VStack(spacing: 16) {
				ForEach(envelopeLines) { line in
					envelopeRow(line)
				}
			}
		}
	}

	private func envelopeRow(_ line: EnvelopeLine) -> some View {
		let period = line.period
		let isExpanded = expandedEnvelopes.contains(line.id)

		return VStack(alignment: .leading, spacing: 6) {
			Button {
				withAnimation(.easeInOut(duration: 0.18)) {
					if isExpanded {
						expandedEnvelopes.remove(line.id)
					} else {
						expandedEnvelopes.insert(line.id)
					}
				}
			} label: {
				VStack(alignment: .leading, spacing: 6) {
					HStack {
						Text("\(line.emoji) \(line.name)")
							.font(.subheadline)
						if line.isCurrent {
							Text("now")
								.font(.system(size: 9, weight: .semibold))
								.padding(.horizontal, 5)
								.padding(.vertical, 1)
								.overlay { Capsule().stroke(theme.fgColour.opacity(0.35), lineWidth: 1) }
						}
						Spacer()
						Text("\(period.available.money) left")
							.font(.caption)
							.monospacedDigit()
							.foregroundStyle(period.isOverspent ? palette.critical : palette.good)
						Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
							.font(.system(size: 9))
							.foregroundStyle(theme.fgColour.opacity(0.45))
					}

					ProgressView(value: period.utilisation)
						.tint(period.isOverspent ? palette.critical : palette.inflow)

					HStack {
						// which cycle this actually is -- the whole point of splitting them
						Text(period.start.formatted(.dateTime.month(.abbreviated).day())
							 + " – "
							 + period.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))
						Text("· \(period.spent.moneyCompact) of \(period.budget.moneyCompact)")
						if period.carriedIn > 0 {
							Text("· \(period.carriedIn.moneyCompact) carried")
						}
						Spacer()
						Text("\(period.expenses.count) logged")
					}
					.font(.caption2)
					.foregroundStyle(theme.fgColour.opacity(0.5))
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)

			// what was actually drawn from this envelope during this cycle
			if isExpanded {
				if period.expenses.isEmpty {
					Text("Nothing drawn from this envelope yet.")
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.5))
						.padding(.top, 2)
				} else {
					VStack(spacing: 0) {
						ForEach(period.expenses.sorted { $0.date > $1.date }) { expense in
							NavigationLink {
								LogTransactionView(editing: expense)
							} label: {
								TransactionRow(transaction: expense, showsDate: true)
							}
							.buttonStyle(.plain)

							if expense.persistentModelID != period.expenses.sorted(by: { $0.date > $1.date }).last?.persistentModelID {
								Divider().background(theme.fgColour.opacity(0.12))
							}
						}
					}
					.padding(.leading, 6)
				}
			}
		}
	}

	// MARK: - Status presentation

	private func style(for status: ReconciliationService.LineStatus) -> (Color, String) {
		switch status {
		case .upcoming: return (theme.fgColour.opacity(0.5), "clock")
		case .outstanding: return (palette.warning, "exclamationmark.circle")
		case .settled: return (palette.good, "checkmark.circle.fill")
		case .over: return (palette.critical, "arrow.up.circle.fill")
		case .under: return (palette.inflow, "arrow.down.circle.fill")
		}
	}

	private func statusLabel(_ status: ReconciliationService.LineStatus) -> String {
		switch status {
		case .upcoming: return "Upcoming"
		case .outstanding: return "Not logged"
		case .settled: return "Settled"
		case .over: return "Over"
		case .under: return "Under"
		}
	}
}
