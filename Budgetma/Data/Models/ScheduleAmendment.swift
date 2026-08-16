import Foundation
import SwiftData

/* --- Schedule Amendment ---
 * "from this date on, it's a different number"
 *
 * the other sparse half of the schedule, and the counterpart to
 * OccurrenceOverride. an override says *this one occurrence* deviated. an
 * amendment says everything from here forward is different, permanently.
 *
 * you get a raise. editing the amount on the expected income would be wrong: it
 * would rewrite every paycheck you've already reconciled, retroactively making
 * six months of correct budgets look like you were underpaid. history is a fact,
 * not a projection, and it must not move when the future does.
 *
 * so the base amount stays as the item's *original* value and amendments layer
 * on top, each one taking effect from its own date. resolution is "the latest
 * amendment on or before this occurrence wins", falling back to the base amount
 * for occurrences before the first amendment.
 *
 * keyed against the base ExpectedTransaction, so one model covers income,
 * expenses and envelopes -- same payoff as OccurrenceOverride gets.
 */
@available(iOS 26, *)
@Model
final class ScheduleAmendment {
	/// the first occurrence date this amount applies to
	var effectiveFrom: Date
	/// what the item is worth from `effectiveFrom` onwards
	var amount: Decimal
	/// why -- "annual raise", "rent review". shown in the history list.
	var note: String?
	/// when the amendment was recorded, purely for display ordering of ties
	var createdAt: Date

	var expected: ExpectedTransaction?

	init(
		expected: ExpectedTransaction?,
		effectiveFrom: Date,
		amount: Decimal,
		note: String? = nil,
		createdAt: Date = .now
	) {
		self.expected = expected
		self.effectiveFrom = effectiveFrom
		self.amount = amount
		self.note = note
		self.createdAt = createdAt
	}
}

/* --- Amendment point ---
 * an amendment stripped of its model reference, so the projector can carry it
 * across an actor boundary inside a ScheduleSnapshot
 */
nonisolated struct AmendmentPoint: Sendable, Hashable {
	let effectiveFrom: Date
	let amount: Decimal
}

/* --- Amendment index ---
 * amendments per expected item, flattened and pre-sorted once
 *
 * same reasoning as OverrideIndex: the projector touches these per occurrence,
 * so sorting or scanning models in that loop would turn a long projection
 * quadratic and drag SwiftData objects off the main actor besides.
 */
@available(iOS 26, *)
nonisolated struct AmendmentIndex: Sendable {
	private let map: [PersistentIdentifier: [AmendmentPoint]]

	@MainActor
	init(_ amendments: [ScheduleAmendment], calendar: Calendar = .current) {
		var map: [PersistentIdentifier: [AmendmentPoint]] = [:]
		for amendment in amendments {
			guard let sourceID = amendment.expected?.persistentModelID else { continue }
			map[sourceID, default: []].append(
				AmendmentPoint(
					// normalised to the day: an amendment effective "today" must
					// catch an occurrence generated at midnight today
					effectiveFrom: calendar.startOfDay(for: amendment.effectiveFrom),
					amount: amendment.amount
				)
			)
		}
		// sorted once here so resolution is a walk, never a sort
		self.map = map.mapValues { $0.sorted { $0.effectiveFrom < $1.effectiveFrom } }
	}

	private init(map: [PersistentIdentifier: [AmendmentPoint]]) {
		self.map = map
	}

	nonisolated static var empty: AmendmentIndex { AmendmentIndex(map: [:]) }

	var isEmpty: Bool { map.isEmpty }

	func points(for sourceID: PersistentIdentifier) -> [AmendmentPoint] {
		map[sourceID] ?? []
	}
}
