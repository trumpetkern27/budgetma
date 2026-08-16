import Foundation
import SwiftData

/* --- Actuals ingestion ---
 * the seam for getting real transactions in from somewhere that isn't a keyboard
 *
 * nothing implements ActualsImporter yet -- entry is manual today. this exists
 * now so that adding csv import or a bank connection later is:
 *   1. a type conforming to ActualsImporter
 *   2. a TransactionSource case
 * and nothing else. the dedup, the persistence, and the matching-to-expected
 * work below are provider-agnostic and already done.
 */

/// a transaction as some external system describes it, before we've decided
/// what it means
struct ImportedTransaction: Sendable, Hashable {
	/// stable id from the provider -- the dedup key. a csv row hash, a bank's
	/// transaction id, whatever that source can promise won't change.
	let externalID: String
	let date: Date
	/// signed: negative is money leaving, positive is money arriving
	let signedAmount: Decimal
	let descriptionText: String
	/// whatever the provider called it; we map it to our own Category if we can
	let rawCategory: String?

	var magnitude: Decimal { abs(signedAmount) }
	var sign: FlowSign { signedAmount < 0 ? .outflow : .inflow }
}

/// anything that can hand us actuals
protocol ActualsImporter {
	var source: TransactionSource { get }
	/// `since` lets incremental syncs avoid refetching everything
	func loadCandidates(since: Date?) async throws -> [ImportedTransaction]
}

/* --- Import pipeline ---
 * turns ImportedTransactions into persisted actuals, exactly once
 */
@available(iOS 26, *)
enum ImportPipeline {

	struct Outcome: Sendable {
		var inserted: Int = 0
		/// already present under the same (source, externalID)
		var duplicates: Int = 0
		/// inserted *and* automatically linked to an expected occurrence
		var matched: Int = 0
	}

	/// persist a batch, skipping anything already ingested from this source
	@discardableResult
	static func ingest(
		_ items: [ImportedTransaction],
		from source: TransactionSource,
		into context: ModelContext,
		categoriseWith categories: [Category] = [],
		autoMatch: Bool = true,
		calendar: Calendar = .current
	) -> Outcome {
		var outcome = Outcome()
		guard !items.isEmpty else { return outcome }

		let existing = existingExternalIDs(for: source, in: context)

		// one matcher for the whole batch so the schedule is projected once
		let matcher = autoMatch
			? ActualMatcher(
				service: BudgetService(context: context),
				range: enclosingRange(of: items, calendar: calendar),
				calendar: calendar
			)
			: nil

		for item in items {
			guard !existing.contains(item.externalID) else {
				outcome.duplicates += 1
				continue
			}

			let category = categories.first {
				$0.name.caseInsensitiveCompare(item.rawCategory ?? "") == .orderedSame
			}

			let match = matcher?.bestMatch(for: item)
			if match != nil { outcome.matched += 1 }

			let expected = match.flatMap { context.model(for: $0.sourceID) as? ExpectedTransaction }

			let transaction: Transaction = item.sign == .inflow
				? Income(
					name: item.descriptionText,
					date: item.date,
					amount: item.magnitude,
					category: category,
					note: nil,
					expected: expected,
					occurrenceDate: match?.occurrenceDate,
					source: source,
					externalID: item.externalID
				)
				: Expense(
					name: item.descriptionText,
					date: item.date,
					amount: item.magnitude,
					category: category,
					note: nil,
					expected: expected,
					occurrenceDate: match?.occurrenceDate,
					source: source,
					externalID: item.externalID
				)

			context.insert(transaction)
			outcome.inserted += 1
		}

		try? context.save()
		return outcome
	}

	private static func existingExternalIDs(
		for source: TransactionSource,
		in context: ModelContext
	) -> Set<String> {
		let raw = source.rawValue
		let descriptor = FetchDescriptor<Transaction>(
			predicate: #Predicate { $0.sourceRaw == raw && $0.externalID != nil }
		)
		let found = (try? context.fetch(descriptor)) ?? []
		return Set(found.compactMap(\.externalID))
	}

	/// the window the batch covers, padded so matching can reach nearby occurrences
	private static func enclosingRange(
		of items: [ImportedTransaction],
		calendar: Calendar
	) -> Range<Date> {
		let dates = items.map(\.date)
		let lower = (dates.min() ?? .now).addingTimeInterval(-30 * 86_400)
		let upper = (dates.max() ?? .now).addingTimeInterval(30 * 86_400)
		return lower..<upper
	}
}

/* --- Actual matcher ---
 * decides which scheduled occurrence, if any, an incoming actual settles
 *
 * used by the import pipeline, and equally usable from the manual-entry screen
 * to pre-select "this looks like your rent payment"
 */
@available(iOS 26, *)
struct ActualMatcher {
	struct Match {
		let sourceID: PersistentIdentifier
		let occurrenceDate: Date
		let expectedAmount: Decimal
		let name: String
	}

	/// how far from an occurrence an actual can land and still be considered it
	var dateTolerance: TimeInterval = 5 * 86_400
	/// how far off the expected amount can be, proportionally
	var amountTolerance: Decimal = 0.25

	private let events: [ScheduledEvent]
	private let calendar: Calendar

	init(service: BudgetService, range: Range<Date>, calendar: Calendar = .current) {
		self.events = service.events(in: range, calendar: calendar)
		self.calendar = calendar
	}

	init(events: [ScheduledEvent], calendar: Calendar = .current) {
		self.events = events
		self.calendar = calendar
	}

	/// best candidate slot for an incoming actual, or nil to leave it unplanned
	func bestMatch(for item: ImportedTransaction) -> Match? {
		bestMatch(amount: item.magnitude, sign: item.sign, date: item.date)
	}

	func bestMatch(amount: Decimal, sign: FlowSign, date: Date) -> Match? {
		let viable = events.filter { event in
			guard event.sourceID != nil else { return false }
			guard event.sign == sign else { return false }
			guard abs(event.date.timeIntervalSince(date)) <= dateTolerance else { return false }
			guard event.amount > 0 else { return true }
			let drift = abs(event.amount - amount) / event.amount
			return drift <= amountTolerance
		}

		// closest in time wins; amount breaks ties
		let best = viable.min { lhs, rhs in
			let lhsGap = abs(lhs.date.timeIntervalSince(date))
			let rhsGap = abs(rhs.date.timeIntervalSince(date))
			if lhsGap != rhsGap { return lhsGap < rhsGap }
			return abs(lhs.amount - amount) < abs(rhs.amount - amount)
		}

		guard let best, let sourceID = best.sourceID else { return nil }
		return Match(
			sourceID: sourceID,
			occurrenceDate: best.occurrenceDate,
			expectedAmount: best.amount,
			name: best.name
		)
	}
}
