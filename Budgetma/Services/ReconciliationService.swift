import Foundation
import SwiftData

/* --- Reconciliation ---
 * expected vs actual for a window
 *
 * projected occurrences are computed, actuals are logged, and this is where the
 * two meet. an actual settles a slot when it points at the same expected item
 * and the same occurrence date. actuals that point at nothing are unplanned
 * spending, which is a first-class thing to see rather than an error.
 *
 * matching lives here, on its own, precisely so that a csv importer or a bank
 * feed can reuse it: ingestion's job ends at "here is an actual", and this
 * decides what it settles.
 */
@available(iOS 26, *)
enum ReconciliationService {

	enum LineStatus: String, Sendable {
		/// hasn't happened yet
		case upcoming
		/// due, nothing logged against it
		case outstanding
		/// logged, close enough to expected
		case settled
		/// logged, came in higher than expected
		case over
		/// logged, came in lower than expected
		case under
	}

	/// one expected occurrence, paired with whatever actually happened
	struct Line: Identifiable {
		/// the occurrence this line came from -- kept whole so the UI can
		/// prefill a log entry or an override straight from it
		let event: ScheduledEvent
		let actualAmount: Decimal
		let actuals: [Transaction]

		var id: String { event.id }
		var name: String { event.name }
		var emoji: String { event.emoji }
		var kind: EventKind { event.kind }
		var occurrenceDate: Date { event.occurrenceDate }
		var date: Date { event.date }
		var expectedAmount: Decimal { event.amount }
		var sourceID: PersistentIdentifier? { event.sourceID }

		var isInflow: Bool { kind.sign == .inflow }
		var hasActuals: Bool { !actuals.isEmpty }
		/// positive == more money moved than planned
		var variance: Decimal { actualAmount - expectedAmount }

		func status(asOf now: Date = .now) -> LineStatus {
			guard hasActuals else {
				return date > now ? .upcoming : .outstanding
			}
			// within 1% (or a cent) counts as settled -- rounding shouldn't
			// light the whole screen up
			let tolerance = Swift.max(expectedAmount * Decimal(0.01), Decimal(0.01))
			if abs(variance) <= tolerance { return .settled }
			return variance > 0 ? .over : .under
		}
	}

	/// the whole window, rolled up
	struct Summary {
		let range: Range<Date>
		let lines: [Line]
		/// actuals in the window that settle nothing
		let unplanned: [Transaction]

		var expectedInflow: Decimal { lines.filter(\.isInflow).reduce(0) { $0 + $1.expectedAmount } }
		var expectedOutflow: Decimal { lines.filter { !$0.isInflow }.reduce(0) { $0 + $1.expectedAmount } }

		var actualInflow: Decimal {
			lines.filter(\.isInflow).reduce(0) { $0 + $1.actualAmount }
				+ unplanned.compactMap { $0 as? Income }.reduce(0) { $0 + $1.amount }
		}
		var actualOutflow: Decimal {
			lines.filter { !$0.isInflow }.reduce(0) { $0 + $1.actualAmount }
				+ unplanned.filter { !($0 is Income) }.reduce(0) { $0 + $1.amount }
		}

		var expectedNet: Decimal { expectedInflow - expectedOutflow }
		var actualNet: Decimal { actualInflow - actualOutflow }

		/// what the plan said should have happened *by now*
		///
		/// comparing a whole window's plan against the actuals logged so far
		/// always reads as a disaster on day one of the window. drift is only
		/// meaningful against the elapsed portion.
		func expectedNet(through date: Date) -> Decimal {
			lines
				.filter { $0.date <= date }
				.reduce(Decimal(0)) { $0 + ($1.isInflow ? $1.expectedAmount : -$1.expectedAmount) }
		}

		var unplannedTotal: Decimal { unplanned.reduce(0) { $0 + $1.amount } }
	}

	// MARK: - Building

	/// pair every projected occurrence in `range` with the actuals that settle it
	static func summary(
		events: [ScheduledEvent],
		actuals: [Transaction],
		in range: Range<Date>,
		calendar: Calendar = .current
	) -> Summary {
		// bucket actuals by the slot they claim to settle
		var bySlot: [OccurrenceSlot: [Transaction]] = [:]
		var unmatched: [Transaction] = []

		for actual in actuals {
			/* a scheduled goal contribution is sourced from a *Goal*, not an
			 * ExpectedTransaction, so it can't be named by `expected` -- that
			 * relationship is typed to the expected-transaction family. a Savings
			 * names its goal instead, and that's what it settles against.
			 *
			 * without this, goal contributions were the one scheduled thing in the
			 * app that could never be settled by anything.
			 */
			if let savings = actual as? Savings,
			   let goalID = savings.goal?.persistentModelID {
				let slotDate = savings.occurrenceDate ?? savings.date
				let slot = OccurrenceSlot(sourceID: goalID, occurrenceDate: slotDate, calendar: calendar)
				bySlot[slot, default: []].append(actual)
				continue
			}

			guard let expectedID = actual.expected?.persistentModelID else {
				unmatched.append(actual)
				continue
			}
			// an actual can name its expected item without naming a specific
			// occurrence -- fall back to its own date, and let the nearest-slot
			// pass below sort it out
			let slotDate = actual.occurrenceDate ?? actual.date
			let slot = OccurrenceSlot(sourceID: expectedID, occurrenceDate: slotDate, calendar: calendar)
			bySlot[slot, default: []].append(actual)
		}

		/* envelope funding is reconciled differently from everything else.
		 * you don't "settle" a grocery envelope with one matching payment --
		 * you fund it once and spend against it many times. so for an envelope
		 * line, actual == everything drawn from that envelope during this
		 * funding cycle. that's what makes "did i stay inside the envelope"
		 * answerable on this screen.
		 */
		// normalised to the day for the same reason EnvelopeLedger does it: a
		// funding occurrence at 15:47 would otherwise push everything you spent
		// that morning into the *previous* cycle
		let fundingDates = Dictionary(
			grouping: events.filter { $0.kind == .envelopeFunding },
			by: { $0.sourceID }
		).compactMapValues { $0.map { calendar.startOfDay(for: $0.date) }.sorted() }

		let expenses = actuals.compactMap { $0 as? Expense }

		var lines: [Line] = []
		var claimed: Set<ObjectIdentifier> = []

		for event in events {
			var matched: [Transaction] = []

			if let sourceID = event.sourceID {
				if event.kind == .envelopeFunding {
					// this cycle runs until the next funding, or the window ends
					let cycleStart = calendar.startOfDay(for: event.date)
					let next = fundingDates[sourceID]?.first { $0 > cycleStart }
					let end = next ?? range.upperBound
					matched = expenses.filter {
						$0.envelope?.persistentModelID == sourceID
							&& $0.date >= cycleStart
							&& $0.date < end
					}
				} else {
					let slot = OccurrenceSlot(
						sourceID: sourceID,
						occurrenceDate: event.occurrenceDate,
						calendar: calendar
					)
					if let exact = bySlot[slot] {
						matched = exact
					} else {
						// no exact slot hit: adopt any actual for this expected item
						// whose own date falls inside this occurrence's day
						let day = calendar.startOfDay(for: event.date)
						let slotByDate = OccurrenceSlot(sourceID: sourceID, occurrenceDate: day, calendar: calendar)
						matched = bySlot[slotByDate] ?? []
					}
				}
			}

			matched.forEach { claimed.insert(ObjectIdentifier($0)) }

			lines.append(
				Line(
					event: event,
					actualAmount: matched.reduce(0) { $0 + $1.amount },
					actuals: matched
				)
			)
		}

		// anything that named an expected item but never got adopted by a line
		// (e.g. it settles an occurrence outside this window) still counts as
		// unplanned *for this window*
		for (_, transactions) in bySlot {
			for transaction in transactions where !claimed.contains(ObjectIdentifier(transaction)) {
				unmatched.append(transaction)
			}
		}

		// envelope spending has no `expected` link, so it landed in `unmatched`
		// above -- but a line has since adopted it, and it isn't unplanned
		let windowed = unmatched.filter {
			range.contains($0.date) && !claimed.contains(ObjectIdentifier($0))
		}

		return Summary(
			range: range,
			lines: lines.sorted { $0.date < $1.date },
			unplanned: windowed.sorted { $0.date < $1.date }
		)
	}
}
