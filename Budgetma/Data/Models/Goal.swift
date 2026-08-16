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

	/* --- optional contribution schedule ---
	 * nil contributionAmount == an untargeted "chip away at it" goal that
	 * doesn't participate in projections
	 */
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
		contributionAmount: Decimal? = nil,
		contributionStart: Date = .now,
		contributionRule: RecurrenceRule? = nil
	) {
		self.name = name
		self.emoji = emoji
		self.targetAmount = targetAmount
		self.targetDate = targetDate
		self.isActive = isActive
		self.contributionAmount = contributionAmount
		self.contributionStart = contributionStart
		self.contributionRule = contributionRule
	}

	/// what's actually been put in so far
	var currentAmount: Decimal {
		contributions.reduce(0) { $0 + $1.amount }
	}

	var remaining: Decimal {
		max(targetAmount - currentAmount, 0)
	}

	var isComplete: Bool { currentAmount >= targetAmount && targetAmount > 0 }

	/// 0...1, for progress bars
	var progress: Double {
		guard targetAmount > 0 else { return 0 }
		let ratio = currentAmount / targetAmount
		return min(max(NSDecimalNumber(decimal: ratio).doubleValue, 0), 1)
	}

	/// whether the scheduled contributions actually land the goal by its target
	/// date -- nil when there's no target date or no schedule to judge
	func projectedCompletion(calendar: Calendar = .current) -> Date? {
		guard let contributionAmount, contributionAmount > 0 else { return nil }
		guard remaining > 0 else { return nil }

		// walk occurrences until the remaining balance is covered
		let horizon = calendar.date(byAdding: .year, value: 50, to: contributionStart) ?? contributionStart
		let snapshot = self.snapshot()

		var accumulated: Decimal = 0
		var completion: Date?
		CashflowProjector.forEachEvent(
			of: snapshot,
			overrides: .empty,
			in: contributionStart..<horizon,
			calendar: calendar
		) { event in
			guard completion == nil else { return }
			accumulated += event.amount
			if accumulated >= remaining { completion = event.date }
		}
		return completion
	}
}

/* --- Goal as a Schedulable ---
 * planned contributions are just another outflow in the projection
 */
@available(iOS 26, *)
extension Goal: Schedulable {
	var scheduleID: PersistentIdentifier? { persistentModelID }
	var scheduleName: String { name }
	var scheduleEmoji: String { emoji }
	var scheduleAmount: Decimal { contributionAmount ?? 0 }
	var scheduleStart: Date { contributionStart }
	var scheduleRule: RecurrenceRule? { contributionRule }
	var scheduleKind: EventKind { .goalContribution }

	/// only goals with a real contribution schedule affect cashflow
	var participatesInProjection: Bool {
		isActive && (contributionAmount ?? 0) > 0
	}
}
