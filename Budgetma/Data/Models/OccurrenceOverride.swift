import Foundation
import SwiftData

/* --- Occurrence Override ---
 *
 * recurrence rules are the source of truth and are computed, not stored,
 * allowing a projection run to any horizon without the db exploding
 * 
 * but, life. things don't go as planned. perhaps you failed to pay rent,
 * or perhaps microsoft started asking for more money to steal your data.
 * these deviations are stored with this
 *
 * keyed against the base ExpectedTransaction, so this single model covers
 * income, expenses and envelopes without three parallel types -- the payoff for
 * the class hierarchy already being in place
 */
@available(iOS 26, *)
@Model
final class OccurrenceOverride {
	// occurence date being overridden
	var occurrenceDate: Date
	// if expected transaction skipped
	var isSkipped: Bool
	// expected transaction occurs on a different date
	var movedTo: Date?

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

	// an override that doesn't deviate from the rule is a no-op, caller should delete
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
	// the deviation, stripped of its model reference
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

	// nonisolated, so `empty` can be too
	private init(map: [OccurrenceSlot: Resolution]) {
		self.map = map
	}

	// an empty index -- for candidates and previews, which never have overrides
	//
	// deliberately built without touching the @Model initialiser: that one is
	// main-actor-isolated, which would make `empty` unusable as a default
	// argument on the concurrent projection path.
	nonisolated static var empty: OverrideIndex { OverrideIndex(map: [:]) }

	// the overwhelmingly common case, and worth checking: with no exceptions
	// the projector can skip per-occurrence slot construction entirely, which
	// is the difference between a long horizon being usable or not
	var isEmpty: Bool { map.isEmpty }

	func resolution(for slot: OccurrenceSlot) -> Resolution? { map[slot] }
}
