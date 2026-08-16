import Foundation
import SwiftData

/* --- Schedule Suspension ---
 * "this stopped happening on this date" — and maybe started again later
 *
 * the third and last sparse deviation, completing the set:
 *
 *   OccurrenceOverride  — this ONE occurrence differed
 *   ScheduleAmendment   — the AMOUNT changed, from a date
 *   ScheduleSuspension  — it stopped EXISTING, between two dates
 *
 * archiving is not deletion, for the same reason a raise isn't a base-amount
 * edit: you really did pay for Hulu for eight months, and those occurrences have
 * been reconciled against real transactions. deleting the expected item would
 * orphan that history and silently restate eight months of budgets. suspending
 * it stops the *future* and leaves the past exactly as it was.
 *
 * `until == nil` means "still cancelled" — that's what archived means. resuming
 * closes the span rather than removing it, so the gap stays a fact: cancel in
 * March, come back in December, and the projector correctly produces nothing at
 * all for those nine months. cancelling again just opens another span, so this
 * survives a subscription you keep flip-flopping on.
 */
@available(iOS 26, *)
@Model
final class ScheduleSuspension {
	/// first date on which the item no longer happens
	var from: Date
	/// first date on which it happens again; nil while still suspended
	var until: Date?
	/// why you cancelled, shown in the archive list
	var note: String?
	var createdAt: Date

	var expected: ExpectedTransaction?

	init(
		expected: ExpectedTransaction?,
		from: Date,
		until: Date? = nil,
		note: String? = nil,
		createdAt: Date = .now
	) {
		self.expected = expected
		self.from = from
		self.until = until
		self.note = note
		self.createdAt = createdAt
	}

	var isOpen: Bool { until == nil }
}

/* --- Suspension span ---
 * a suspension stripped of its model reference, so the projector can carry it
 * across an actor boundary inside a ScheduleSnapshot
 */
nonisolated struct SuspensionSpan: Sendable, Hashable {
	let from: Date
	let until: Date?

	func contains(_ date: Date) -> Bool {
		guard date >= from else { return false }
		guard let until else { return true }
		return date < until
	}
}

/* --- Suspension index ---
 * flattened per expected item, for the same reason as OverrideIndex and
 * AmendmentIndex: the projector consults these once per occurrence
 */
@available(iOS 26, *)
nonisolated struct SuspensionIndex: Sendable {
	private let map: [PersistentIdentifier: [SuspensionSpan]]

	@MainActor
	init(_ suspensions: [ScheduleSuspension], calendar: Calendar = .current) {
		var map: [PersistentIdentifier: [SuspensionSpan]] = [:]
		for suspension in suspensions {
			guard let sourceID = suspension.expected?.persistentModelID else { continue }
			map[sourceID, default: []].append(
				SuspensionSpan(
					// day-normalised: an item cancelled "today" must not still
					// produce an occurrence generated at midnight this morning
					from: calendar.startOfDay(for: suspension.from),
					until: suspension.until.map { calendar.startOfDay(for: $0) }
				)
			)
		}
		self.map = map.mapValues { $0.sorted { $0.from < $1.from } }
	}

	private init(map: [PersistentIdentifier: [SuspensionSpan]]) {
		self.map = map
	}

	nonisolated static var empty: SuspensionIndex { SuspensionIndex(map: [:]) }

	var isEmpty: Bool { map.isEmpty }

	func spans(for sourceID: PersistentIdentifier) -> [SuspensionSpan] {
		map[sourceID] ?? []
	}
}

/* --- what "archived" means to the UI ---
 * an item is archived when it has an open-ended suspension. the flag isn't
 * stored: deriving it from the spans means the two can never disagree.
 */
@available(iOS 26, *)
extension ExpectedTransaction {
	func isArchived(in suspensions: [ScheduleSuspension]) -> Bool {
		suspensions.contains { $0.expected?.persistentModelID == persistentModelID && $0.isOpen }
	}

	func openSuspension(in suspensions: [ScheduleSuspension]) -> ScheduleSuspension? {
		suspensions.first { $0.expected?.persistentModelID == persistentModelID && $0.isOpen }
	}
}
