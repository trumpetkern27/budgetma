import Foundation
import SwiftData

/* --- Sample data ---
 * DEBUG-only development scaffolding, off unless you ask for it
 *
 * launch with  -seed-sample-data  to fill an empty store with a realistic
 * misaligned budget: biweekly pay against monthly rent, a 6-week barber
 * envelope, a savings goal. useful for seeing the charts with something in them.
 * launch with  -start-tab plan    to open straight onto a given tab.
 *
 * it refuses to run if there's already data, so it can't tread on real records.
 * delete this file whenever it stops being useful -- nothing depends on it.
 */
#if DEBUG
@available(iOS 26, *)
enum SampleData {

	static var isRequested: Bool {
		ProcessInfo.processInfo.arguments.contains("-seed-sample-data")
	}

	/// tab to open on, when specified
	static var requestedTab: String? {
		let arguments = ProcessInfo.processInfo.arguments
		guard let index = arguments.firstIndex(of: "-start-tab"),
			  index + 1 < arguments.count else { return nil }
		return arguments[index + 1]
	}

	static func seedIfRequested(into context: ModelContext) {
		guard isRequested else { return }

		// never overwrite real data
		let existing = (try? context.fetch(FetchDescriptor<ExpectedTransaction>())) ?? []
		guard existing.isEmpty else { return }

		let calendar = Calendar.current
		let today = calendar.startOfDay(for: .now)
		func day(_ offset: Int) -> Date {
			calendar.date(byAdding: .day, value: offset, to: today) ?? today
		}

		// categories
		let housing = Category(name: "Housing", emoji: "🏠")
		let food = Category(name: "Food", emoji: "🍜")
		let fun = Category(name: "Fun", emoji: "🎸")
		let work = Category(name: "Work", emoji: "🧑‍💻")
		let grooming = Category(name: "Grooming", emoji: "💈")
		[housing, food, fun, work, grooming].forEach(context.insert)

		func rule(
			_ frequency: Calendar.RecurrenceRule.Frequency,
			every interval: Int = 1
		) -> RecurrenceRule {
			let created = RecurrenceRule(frequency: frequency, interval: interval)
			context.insert(created)
			return created
		}

		// biweekly pay against monthly bills -- the misalignment the app exists for
		let paycheck = ExpectedIncome(
			name: "Paycheck", amount: 2100, startDate: day(-3),
			regularity: rule(.weekly, every: 2), category: work
		)
		context.insert(paycheck)

		let rent = ExpectedExpense(
			name: "Rent", amount: 1750, startDate: day(-8),
			regularity: rule(.monthly), category: housing
		)
		context.insert(rent)
		context.insert(ExpectedExpense(
			name: "Electric", amount: 95, startDate: day(4),
			regularity: rule(.monthly), category: housing
		))
		context.insert(ExpectedExpense(
			name: "Phone", amount: 45, startDate: day(9),
			regularity: rule(.monthly), category: housing
		))
		context.insert(ExpectedExpense(
			name: "Streaming", amount: 18, startDate: day(1),
			regularity: rule(.monthly), category: fun
		))
		// a one-off, to prove non-recurring items flow through the same path
		context.insert(ExpectedExpense(
			name: "Car registration", amount: 320, startDate: day(52),
			regularity: nil, category: housing
		))

		// envelopes, including the every-6-weeks barber from the model comments
		let groceries = Envelope(
			name: "Groceries", amount: 260, startDate: day(-3),
			regularity: rule(.weekly, every: 2), category: food, carryOver: false
		)
		context.insert(groceries)
		context.insert(Envelope(
			name: "Barber", amount: 40, startDate: day(-12),
			regularity: rule(.weekly, every: 6), category: grooming, carryOver: true
		))

		// a goal with a real contribution schedule, so it shows up as outflow
		context.insert(Goal(
			name: "New couch", emoji: "🛋️", targetAmount: 1200,
			targetDate: day(300),
			contributionAmount: 120, contributionStart: day(-3),
			contributionRule: rule(.weekly, every: 2)
		))

		/* actuals, so expected-vs-actual has something to compare.
		 * the linked ones carry `expected` + `occurrenceDate` -- the slot they
		 * settle -- exactly as the log screen and a csv import would set them.
		 */
		context.insert(Expense(
			name: "Rent", date: day(-8), amount: 1750,
			category: housing, note: nil,
			expected: rent, occurrenceDate: day(-8)
		))
		// came in over -- shows as an "Over" line rather than settled
		context.insert(Income(
			name: "Paycheck", date: day(-3), amount: 2180,
			category: work, note: "included overtime",
			expected: paycheck, occurrenceDate: day(-3)
		))
		// envelope spending: drawn against Groceries, not settling an occurrence
		context.insert(Expense(
			name: "Trader Joe's", date: day(-2), amount: 82.40,
			category: food, note: nil, envelope: groceries
		))
		context.insert(Expense(
			name: "Corner store", date: day(-1), amount: 23.15,
			category: food, note: nil, envelope: groceries
		))
		// genuinely unplanned -- settles nothing, draws on nothing
		context.insert(Expense(
			name: "Concert tickets", date: day(-4), amount: 140,
			category: fun, note: nil
		))

		try? context.save()
	}
}
#endif
