import Foundation
import SwiftData

/* --- ScheduledEvent ---
 * one projected occurrence, flattened into a plain value type
 *
 * this is what the projector emits. it deliberately carries no model
 * references -- just an optional id to navigate back with -- so projections can
 * be computed off the main actor without dragging SwiftData objects across
 * threads
 */
nonisolated struct ScheduledEvent: Identifiable, Hashable, Sendable {
	/// the canonical slot this event belongs to (the date the *rule* produced,
	/// before any override moved it). this is the join key for actuals.
	let occurrenceDate: Date
	/// where the event actually lands after overrides are applied
	let date: Date
	/// always a positive magnitude; direction lives in `sign`
	let amount: Decimal
	let kind: EventKind
	let name: String
	let emoji: String
	let sourceID: PersistentIdentifier?

	var sign: FlowSign { kind.sign }
	var signedAmount: Decimal { amount * sign.multiplier }
	var isInflow: Bool { sign == .inflow }

	var id: String {
		let source = sourceID.map { String(describing: $0.hashValue) } ?? "candidate"
		return "\(kind.rawValue)-\(source)-\(occurrenceDate.timeIntervalSince1970)"
	}
}

/* --- OccurrenceSlot ---
 * a stable, hashable identity for "this expected item, on this date"
 * used to key overrides and to match actuals back to what they settle
 */
nonisolated struct OccurrenceSlot: Hashable, Sendable {
	let sourceID: PersistentIdentifier
	let occurrenceDate: Date

	init(sourceID: PersistentIdentifier, occurrenceDate: Date, calendar: Calendar = .current) {
		self.sourceID = sourceID
		// normalise to the day so time-of-day drift never breaks a match
		self.occurrenceDate = calendar.startOfDay(for: occurrenceDate)
	}
}
