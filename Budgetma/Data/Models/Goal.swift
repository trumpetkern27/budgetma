import Foundation
import SwiftData

/* --- Goal Model ---
 * a savings target you put money into over time
 *
 * a goal optionally carries its own contribution schedule, which is why it
 * conforms to Schedulable further down: if you're putting $200/mo aside for a
 * couch, that $200 is genuinely not available for anything else, and the
 * projection has to know that. planned contributions show up as outflows
 * exactly like any other recurring expense -- no special casing.
 */
@available(iOS 26, *)
@Model
final class Goal {
	var name: String
	var emoji: String
	var targetAmount: Decimal
	var targetDate: Date?
	var isActive: Bool
	var seedAmount: Decimal = 0
	var annualInterestRate: Decimal = 0

	// optional contribution schedule
	var contributionAmount: Decimal?
	var contributionStart: Date
	var contributionRule: RecurrenceRule?

	@Relationship(deleteRule: .cascade, inverse: \Savings.goal)
	var contributions: [Savings] = []

	init(
		name: String,
		emoji: String = "🎯",
		targetAmount: Decimal,
		targetDate: Date? = nil,
		isActive: Bool = true,
		seedAmount: Decimal = 0,
		annualInterestRate: Decimal = 0,
		contributionAmount: Decimal? = nil,
		contributionStart: Date = .now,
		contributionRule: RecurrenceRule? = nil
	) {
		self.name = name
		self.emoji = emoji
		self.targetAmount = targetAmount
		self.targetDate = targetDate
		self.isActive = isActive
		self.seedAmount = seedAmount
		self.annualInterestRate = annualInterestRate
		self.contributionAmount = contributionAmount
		self.contributionStart = contributionStart
		self.contributionRule = contributionRule
	}

	var currentAmount: Decimal {
		contributedAmount + seedAmount
	}

	var contributedAmount: Decimal {
		contributions.reduce(0) { $0 + $1.amount }
	}

	var remaining: Decimal {
		max(targetAmount - currentAmount, 0)
	}

	var isComplete: Bool { currentAmount >= targetAmount && targetAmount > 0 }

	// 0...1, for progress bars
	var progress: Double {
		guard targetAmount > 0 else { return 0 }
		let ratio = currentAmount / targetAmount
		return min(max(NSDecimalNumber(decimal: ratio).doubleValue, 0), 1)
	}

	func projectedCompletion(calendar: Calendar = .current) -> Date? {
		guard let contributionAmount, contributionAmount > 0 else { return nil }
		guard remaining > 0 else { return nil }

		// interest means this can't be a simple running sum any more: money put
		// in early is worth more than money put in late, and for a multi-year
		// goal that difference moves the finish line by months
		let horizon = calendar.date(byAdding: .year, value: 50, to: .now) ?? .now
		let result = GoalSimulator.simulate(
			GoalSimulator.Scenario(
				contribution: contributionAmount,
				rule: contributionRule?.toRecurranceRule(),
				start: contributionStart,
				annualRate: annualInterestRate,
				openingBalance: currentAmount
			),
			target: targetAmount,
			horizon: horizon,
			calendar: calendar
		)
		return result.completion
	}
}

 // make goal schedulable
@available(iOS 26, *)
extension Goal: Schedulable {
	var scheduleID: PersistentIdentifier? { persistentModelID }
	var scheduleName: String { name }
	var scheduleEmoji: String { emoji }
	var scheduleAmount: Decimal { contributionAmount ?? 0 }
	var scheduleStart: Date { contributionStart }
	var scheduleRule: RecurrenceRule? { contributionRule }
	var scheduleKind: EventKind { .goalContribution }

	/// only goals with a scheduled contribution affect projection
	var participatesInProjection: Bool {
		isActive && (contributionAmount ?? 0) > 0
	}
}
