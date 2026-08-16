import Foundation
import SwiftData

/* --- Occurrence Override ---
 * the sparse exception half of the schedule
 *
 * recurrence rules are the source of truth and occurrences are computed, never
 * stored -- that's what lets a projection run to any horizon without the db
 * exploding. but real life deviates: rent got paid late, you skipped a month of
 * the gym, the subscription went up $2. those deviations get stored *here*, one
 * row per deviation, and nowhere else.
 *
 * keyed against the base ExpectedTransaction, so this single model covers
 * income, expenses and envelopes without three parallel types -- the payoff for
 * the class hierarchy already being in place
 */
@available(iOS 26, *)
@Model
final class OccurrenceOverride {
	/// the slot being overridden -- the date the *rule* originally produced
	var occurrenceDate: Date
	/// this occurrence just doesn't happen
	var isSkipped: Bool
	/// this occurrence happens, but on a different date
	var movedTo: Date?
	/// this occurrence happens, but for a different amount
	var amountOverride: Decimal?

	var expected: ExpectedTransaction?

	init(
		expected: ExpectedTransaction?,
		occurrenceDate: Date,
		isSkipped: Bool = false,
		movedTo: Date? = nil,
		amountOverride: Decimal? = nil
	) {
		self.expected = expected
		self.occurrenceDate = occurrenceDate
		self.isSkipped = isSkipped
		self.movedTo = movedTo
		self.amountOverride = amountOverride
	}

	/// an override that no longer deviates from the rule is just noise --
	/// the caller should delete it rather than persist a no-op
	var isNoOp: Bool {
		!isSkipped && movedTo == nil && amountOverride == nil
	}
}

/* --- Override index ---
 * overrides are sparse, but the projector hits them once per occurrence, so a
 * linear scan would turn a long projection quadratic. this flattens them into a
 * dictionary once, up front, and detaches them from SwiftData so the lookup is
 * safe to use off the main actor.
 */
@available(iOS 26, *)
nonisolated struct OverrideIndex: Sendable {
	/// the deviation, stripped of its model reference
	struct Resolution: Sendable {
		let isSkipped: Bool
		let movedTo: Date?
		let amountOverride: Decimal?
	}

	private let map: [OccurrenceSlot: Resolution]

	@MainActor
	init(_ overrides: [OccurrenceOverride], calendar: Calendar = .current) {
		var map: [OccurrenceSlot: Resolution] = [:]
		for override in overrides {
			guard let sourceID = override.expected?.persistentModelID else { continue }
			let slot = OccurrenceSlot(
				sourceID: sourceID,
				occurrenceDate: override.occurrenceDate,
				calendar: calendar
			)
			map[slot] = Resolution(
				isSkipped: override.isSkipped,
				movedTo: override.movedTo,
				amountOverride: override.amountOverride
			)
		}
		self.map = map
	}

	/// nonisolated, so `empty` can be too
	private init(map: [OccurrenceSlot: Resolution]) {
		self.map = map
	}

	/// an empty index -- for candidates and previews, which never have overrides
	///
	/// deliberately built without touching the @Model initialiser: that one is
	/// main-actor-isolated, which would make `empty` unusable as a default
	/// argument on the concurrent projection path.
	nonisolated static var empty: OverrideIndex { OverrideIndex(map: [:]) }

	/// the overwhelmingly common case, and worth checking: with no exceptions
	/// the projector can skip per-occurrence slot construction entirely, which
	/// is the difference between a long horizon being usable or not
	var isEmpty: Bool { map.isEmpty }

	func resolution(for slot: OccurrenceSlot) -> Resolution? { map[slot] }
}
