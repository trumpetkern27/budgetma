import SwiftUI
import SwiftData

struct HomeView: View {
	@EnvironmentObject var theme: ThemeManager

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
