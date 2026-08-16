import SwiftUI
import SwiftData

/* --- Home ---
 * the glance: a calendar of what's coming, and the way in to everything else
 *
 * the calendar period is itself defined by a recurrence rule (see the settings
 * at the top), so "my pay period" can be biweekly, or every 10 days, or monthly
 * -- the grid doesn't assume months any more than the rest of the app does.
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

	@State private var periodOffset: Int = 0

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	private var snapshots: [ScheduleSnapshot] {
		BudgetService.snapshots(
			incomes: expectedIncomes,
			expenses: expectedExpenses,
			envelopes: envelopes,
			goals: goals
		)
	}

	private var bounds: (start: Date, end: Date) { currentPeriodBounds() }

	private var events: [ScheduledEvent] {
		CashflowProjector.events(
			for: snapshots,
			overrides: OverrideIndex(overrides),
			in: bounds.start..<bounds.end
		)
	}

	private var groupedByDay: [(day: Date, items: [ScheduledEvent])] {
		let dict = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.date) }
		return dict.keys.sorted().map { ($0, dict[$0]!.sorted { $0.date < $1.date }) }
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
				setupLinks
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.chartPalette(for: theme.bgColour)
		.navigationTitle("Budgetma")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				NavigationLink {
					LogTransactionView()
				} label: {
					Image(systemName: "plus.circle.fill")
				}
			}
		}
	}

	// MARK: - Period

	private var periodHeader: some View {
		HStack {
			Button { periodOffset -= 1 } label: { Image(systemName: "chevron.left") }

			Spacer()

			VStack(spacing: 2) {
				Text(bounds.start.formatted(.dateTime.month(.wide).year()))
					.font(.headline)
				Text(bounds.start.formatted(.dateTime.month(.abbreviated).day()) + " – "
					 + bounds.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))
					.font(.caption2)
					.foregroundStyle(theme.fgColour.opacity(0.55))
			}

			Spacer()

			Button { periodOffset += 1 } label: { Image(systemName: "chevron.right") }
		}
		.tint(theme.fgColour)
	}

	// MARK: - Calendar

	var calendarGrid: some View {
		VStack(spacing: 8) {
			HStack {
				// keyed by position, not value -- S/M/T/W/T/F/S repeats letters
				// and \.self makes SwiftUI collapse the duplicates
				ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
					Text(symbol)
						.font(.caption)
						.foregroundStyle(theme.fgColour.opacity(0.6))
						.frame(maxWidth: .infinity)
				}
			}

			LazyVGrid(columns: columns, spacing: 0) {
				ForEach(calendarCells) { cell in
					if let date = cell.date {
						dayCell(for: date)
					} else {
						Color.clear.frame(height: 52)
							.overlay { Rectangle().stroke(theme.fgColour.opacity(0.15), lineWidth: 1) }
					}
				}
			}
		}
	}

	private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

	private struct CalendarCell: Identifiable {
		let id: Int
		let date: Date?
	}

	private var calendarCells: [CalendarCell] {
		let (start, end) = bounds
		let days = daysInPeriod(start: start, end: end)
		let leadingBlanks = (Calendar.current.component(.weekday, from: start) - Calendar.current.firstWeekday + 7) % 7
		let blanks = (0..<leadingBlanks).map { CalendarCell(id: $0, date: nil) }
		let realDays = days.enumerated().map { CalendarCell(id: leadingBlanks + $0.offset, date: $0.element) }
		return blanks + realDays
	}

	private var weekdaySymbols: [String] {
		let calendar = Calendar.current
		let symbols = calendar.veryShortWeekdaySymbols
		let offset = calendar.firstWeekday - 1
		return Array(symbols[offset...] + symbols[..<offset])
	}

	func currentPeriodBounds(reference: Date = .now) -> (start: Date, end: Date) {
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: reference)
		let rule = Calendar.RecurrenceRule(calendar: calendar, frequency: frequency, interval: interval, end: .never)

		let searchStart = calendar.date(byAdding: .day, value: -400, to: today)!
		let searchEnd = calendar.date(byAdding: .day, value: 400, to: today)!

		let occurrences = Array(rule.recurrences(of: periodStart, in: searchStart..<searchEnd))

		guard let base = occurrences.lastIndex(where: { $0 <= today }) else {
			return (periodStart, periodStart)
		}

		let index = min(max(base + periodOffset, 0), max(occurrences.count - 1, 0))
		let start = occurrences[index]
		let end = index + 1 < occurrences.count
			? occurrences[index + 1]
			: calendar.date(byAdding: .day, value: 1, to: start)!
		return (start, end)
	}

	func daysInPeriod(start: Date, end: Date) -> [Date] {
		var days: [Date] = []
		var day = start
		let calendar = Calendar.current
		while day < end {
			days.append(day)
			day = calendar.date(byAdding: .day, value: 1, to: day)!
		}
		return days
	}

	private func dayCell(for date: Date) -> some View {
		let calendar = Calendar.current
		let isToday = calendar.isDateInToday(date)
		let dayItems = groupedByDay.first { calendar.isDate($0.day, inSameDayAs: date) }?.items ?? []
		let net = dayItems.reduce(Decimal(0)) { $0 + $1.signedAmount }

		return VStack(spacing: 2) {
			Text("\(calendar.component(.day, from: date))")
				.frame(width: 32, height: 20)
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
				.frame(width: 32, height: 32)
		}
		.frame(maxWidth: .infinity, alignment: .top)
		.overlay { Rectangle().stroke(theme.fgColour.opacity(0.15), lineWidth: 1) }
	}

	// MARK: - Cards

	private var summaryCard: some View {
		let net = totalIncome - totalExpense

		return Card(title: "This period") {
			HStack(alignment: .top, spacing: 12) {
				StatTile(label: "In", value: totalIncome.moneyCompact, accent: palette.inflow)
				StatTile(label: "Out", value: totalExpense.moneyCompact, accent: palette.outflow)
				StatTile(
					label: "Net",
					value: net.moneySigned,
					accent: net >= 0 ? palette.good : palette.critical,
					systemImage: net >= 0 ? "arrow.up.right" : "arrow.down.right"
				)
			}
		}
	}

	@ViewBuilder
	private var upcomingCard: some View {
		Card(title: "Coming up") {
			if events.isEmpty {
				Text("Nothing expected in this period.")
					.font(.callout)
					.foregroundStyle(theme.fgColour.opacity(0.6))
			} else {
				VStack(spacing: 0) {
					ForEach(groupedByDay, id: \.day) { group in
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

	private var setupLinks: some View {
		HStack(spacing: 12) {
			NavigationLink {
				IncomeView()
			} label: {
				setupTile(emoji: "💰", label: "Income")
			}
			.buttonStyle(.plain)

			NavigationLink {
				ExpenseView()
			} label: {
				setupTile(emoji: "💸", label: "Expenses")
			}
			.buttonStyle(.plain)
		}
	}

	private func setupTile(emoji: String, label: String) -> some View {
		VStack(spacing: 6) {
			Text(emoji).font(.title3)
			Text(label).font(.caption)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 14)
		.overlay {
			RoundedRectangle(cornerRadius: 14)
				.stroke(theme.fgColour.opacity(0.25), lineWidth: 1)
		}
	}
}
