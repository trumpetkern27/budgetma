import SwiftUI
import SwiftData

struct HomeView: View {
	@EnvironmentObject var theme: ThemeManager

	@AppStorage("calendarViewFrequency") private var frequency: Calendar.RecurrenceRule.Frequency = .monthly
	@AppStorage("calendarViewInterval") private var interval: Int = 1
	@AppStorage("calendarViewStartDate") private var startDate: Date = .now

	@Query private var expectedIncomes: [ExpectedIncome]
	@Query private var expectedExpenses: [ExpectedExpense]
	@Query private var envelopes: [Envelope]

	@State private var windowDays: Int = 30

	private var windowRange: Range<Date> {
		let start = Calendar.current.startOfDay(for: .now)
		let end = Calendar.current.date(byAdding: .day, value: windowDays, to: start)!
		return start..<end
	}

	private var upcoming: [UpcomingItem] {
		var items: [UpcomingItem] = []

		for income in expectedIncomes {
			items += RecurrenceProjector
				.occurrences(startDate: income.startDate, regularity: income.regularity, in: windowRange)
				.map { UpcomingItem(date: $0, source: .income(income)) }
		}

		for expense in expectedExpenses {
			items += RecurrenceProjector
				.occurrences(startDate: expense.startDate, regularity: expense.regularity, in: windowRange)
				.map { UpcomingItem(date: $0, source: .expense(expense)) }
		}

		for envelope in envelopes {
			items += RecurrenceProjector
				.occurrences(startDate: envelope.startDate, regularity: envelope.regularity, in: windowRange)
				.map { UpcomingItem(date: $0, source: .envelope(envelope)) }
		}

		return items.sorted { $0.date < $1.date }
	}

	private var groupedByDay: [(day: Date, items: [UpcomingItem])] {
		let dict = Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.date) }
		return dict.keys.sorted().map { ($0, dict[$0]!.sorted { $0.date < $1.date }) }
	}

	private var totalIncome: Decimal { upcoming.filter(\.isIncome).reduce(0) { $0 + $1.amount } }
	private var totalExpense: Decimal { upcoming.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount } }

	var body: some View {
		VStack {

			calendarGrid
				.padding()

			Divider()

			ScrollView {
				VStack(spacing: 0) {
					Picker("Window", selection: $windowDays) {
						Text("7 days").tag(7)
						Text("30 days").tag(30)
						Text("90 days").tag(90)
					}
					.pickerStyle(.segmented)
					.padding()

					SummaryCard(totalIncome: totalIncome, totalExpense: totalExpense)
						.padding(.horizontal)
						.padding(.vertical)

					ForEach(groupedByDay, id: \.day) { group in 
						Text(group.day, format: .dateTime.weekday(.wide).month().day())
							.font(.headline)
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.horizontal)
							.padding(.top)

						ForEach(group.items) { item in 
							HStack {
								Text("\(item.emoji) \(item.name)")
								Spacer()
								Text(item.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
									.foregroundStyle(item.isIncome ? .green : theme.fgColour)
							}
							.padding(.horizontal)
							.padding(.vertical, 6)
						}

						Divider()
					}

					if upcoming.isEmpty {
						Text("Nothing expected in this window.")
							.foregroundStyle(.secondary)
							.padding()
					}
				}
			}
			.scrollContentBackground(.hidden)
			.themed()
		}
		.themed()
	}

	var calendarGrid: some View {
		VStack(spacing: 8) {

			HStack {
				ForEach(weekdaySymbols, id: \.self) { symbol in
					Text(symbol)
						.font(.caption)
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity)
				}
			}

			LazyVGrid(columns: columns, spacing: 8) {
				ForEach(calendarCells) { cell in 
					if let date = cell.date {
						dayCell(for: date)
					} else {
						Color.clear.frame(height: 32)
					}
				}
			}
		}
	}

	private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
	private struct CalendarCell: Identifiable {
		let id: Int
		let date: Date?
	}

	private var calendarCells: [CalendarCell] {
		let (start, end) = currentPeriodBounds()
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

		let occurrences = Array(rule.recurrences(of: startDate, in: searchStart..<searchEnd))

		guard let idx = occurrences.lastIndex(where: { $0 <= today }) else {
			return (startDate, startDate)
		}

		let start = occurrences[idx]
		let end = idx + 1 < occurrences.count ? occurrences[idx + 1] : calendar.date(byAdding: .day, value: 1, to: start)!
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
		let hasItems = groupedByDay.contains { calendar.isDate($0.day, inSameDayAs: date) }

		return VStack(spacing: 2) {
			Text("\(calendar.component(.day, from: date))")
				.frame(width: 32, height: 32)
				.background(isToday ? theme.fgColour : .clear)
				.foregroundColor(isToday ? theme.bgColour : theme.fgColour)
				.clipShape(Circle())

				Circle()
					.fill(theme.fgColour)
					.frame(width: 4, height: 4)
					.opacity(hasItems ? 1 : 0)
		}
	}
}

struct SummaryCard: View {
	let totalIncome: Decimal
	let totalExpense: Decimal

	private var net: Decimal { totalIncome - totalExpense }

	var body: some View {
		VStack(spacing: 8) {
			HStack {
				Text("Expected income")
				Spacer()
				Text(totalIncome, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
					.foregroundStyle(.green)
			}
			HStack {
				Text("Expected expenses")
				Spacer()
				Text(totalExpense, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
			}
			Divider()
			HStack {
				Text("Net").bold()
				Spacer()
				Text(net, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
					.bold()
					.foregroundStyle(net >= 0 ? .green : .red)
			}
		}
		.padding()
		.overlay { RoundedRectangle(cornerRadius: 12).stroke(.secondary, lineWidth: 1) }
	}
}

