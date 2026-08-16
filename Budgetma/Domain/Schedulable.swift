import Foundation
import SwiftData

/* --- Schedulable ---
 * the seam the whole projection engine sits on
 *
 * anything that produces dated amounts conforms: expected income, expected
 * expenses, envelope funding, goal contributions -- and, crucially, *candidate*
 * items that aren't saved to the db at all (see CandidateSchedule below), which
 * is what makes the affordability check work without touching persistence
 *
 * the projector takes [any Schedulable] and has no idea what any of them are
 */
protocol Schedulable {
	var scheduleID: PersistentIdentifier? { get }
	var scheduleName: String { get }
	var scheduleEmoji: String { get }
	var scheduleAmount: Decimal { get }
	var scheduleStart: Date { get }
	var scheduleRule: RecurrenceRule? { get }
	var scheduleKind: EventKind { get }
}

extension Schedulable {
	var scheduleSign: FlowSign { scheduleKind.sign }

	/// flatten into a Sendable value type, resolving the recurrence rule once
	///
	/// @Model classes aren't Sendable and RecurrenceRule is one of them, so a
	/// projection can't touch them off the main actor. snapshotting on the main
	/// actor and projecting from snapshots fixes that -- and as a bonus the
	/// rule conversion happens once per item instead of once per occurrence.
	func snapshot() -> ScheduleSnapshot {
		ScheduleSnapshot(
			sourceID: scheduleID,
			name: scheduleName,
			emoji: scheduleEmoji,
			amount: scheduleAmount,
			start: scheduleStart,
			rule: scheduleRule?.toRecurranceRule(),
			kind: scheduleKind
		)
	}
}

/* --- ScheduleSnapshot ---
 * a detached, Sendable copy of a Schedulable
 * this is what the projector actually consumes
 */
nonisolated struct ScheduleSnapshot: Sendable {
	let sourceID: PersistentIdentifier?
	let name: String
	let emoji: String
	let amount: Decimal
	let start: Date
	let rule: Calendar.RecurrenceRule?
	let kind: EventKind

	var sign: FlowSign { kind.sign }

	/// same item, different price -- used by the affordability solver when it
	/// searches for the largest amount that still fits
	func repriced(to newAmount: Decimal) -> ScheduleSnapshot {
		ScheduleSnapshot(
			sourceID: sourceID,
			name: name,
			emoji: emoji,
			amount: newAmount,
			start: start,
			rule: rule,
			kind: kind
		)
	}
}

/* --- conformances for the persisted expected-transaction family ---
 * ExpectedTransaction already gives us name/amount/startDate/regularity,
 * so each subclass only has to declare what kind of event it is
 */

@available(iOS 26, *)
extension ExpectedIncome: Schedulable {
	var scheduleID: PersistentIdentifier? { persistentModelID }
	var scheduleName: String { name }
	var scheduleEmoji: String { category?.emoji ?? EventKind.income.fallbackEmoji }
	var scheduleAmount: Decimal { amount }
	var scheduleStart: Date { startDate }
	var scheduleRule: RecurrenceRule? { regularity }
	var scheduleKind: EventKind { .income }
}

@available(iOS 26, *)
extension ExpectedExpense: Schedulable {
	var scheduleID: PersistentIdentifier? { persistentModelID }
	var scheduleName: String { name }
	var scheduleEmoji: String { category?.emoji ?? EventKind.expense.fallbackEmoji }
	var scheduleAmount: Decimal { amount }
	var scheduleStart: Date { startDate }
	var scheduleRule: RecurrenceRule? { regularity }
	var scheduleKind: EventKind { .expense }
}

@available(iOS 26, *)
extension Envelope: Schedulable {
	var scheduleID: PersistentIdentifier? { persistentModelID }
	var scheduleName: String { name }
	var scheduleEmoji: String { category?.emoji ?? EventKind.envelopeFunding.fallbackEmoji }
	var scheduleAmount: Decimal { amount }
	var scheduleStart: Date { startDate }
	var scheduleRule: RecurrenceRule? { regularity }
	var scheduleKind: EventKind { .envelopeFunding }
}

/* --- CandidateSchedule ---
 * a hypothetical, unsaved thing you're thinking about buying
 *
 * "can i afford netflix at $18/mo" and "can i afford a $3000 couch in march"
 * are the same question to the engine -- one has a rule, one doesn't
 *
 * note the RecurrenceRule here is deliberately never inserted into a context;
 * toRecurranceRule() works fine on a detached instance
 */
struct CandidateSchedule: Schedulable {
	var scheduleID: PersistentIdentifier? { nil }
	var scheduleName: String
	var scheduleEmoji: String
	var scheduleAmount: Decimal
	var scheduleStart: Date
	var scheduleRule: RecurrenceRule?
	var scheduleKind: EventKind

	init(
		name: String,
		emoji: String = "🛒",
		amount: Decimal,
		startDate: Date = .now,
		rule: RecurrenceRule? = nil,
		kind: EventKind = .expense
	) {
		self.scheduleName = name
		self.scheduleEmoji = emoji
		self.scheduleAmount = amount
		self.scheduleStart = startDate
		self.scheduleRule = rule
		self.scheduleKind = kind
	}
}
