import Foundation
import SwiftData

/* --- Budget Service ---
 * the bridge between SwiftData and the pure domain
 *
 * everything below the domain line works on Sendable value types and knows
 * nothing about persistence. this is the one place that reaches into a
 * ModelContext, pulls out the expected items, and flattens them into snapshots.
 * views ask for a projection; they never assemble one themselves.
 */
@available(iOS 26, *)
struct BudgetService {
	let context: ModelContext

	init(context: ModelContext) {
		self.context = context
	}

	// MARK: - Snapshot assembly

	/// assemble snapshots from already-fetched models
	///
	/// views hold @Query results and get change tracking for free, so they pass
	/// them straight in rather than making the service re-fetch. same flattening
	/// either way -- the logic lives in one place.
	static func snapshots(
		incomes: [ExpectedIncome] = [],
		expenses: [ExpectedExpense] = [],
		envelopes: [Envelope] = [],
		goals: [Goal] = [],
		amendments: [ScheduleAmendment] = []
	) -> [ScheduleSnapshot] {
		let index = AmendmentIndex(amendments)

		func points(_ id: PersistentIdentifier?) -> [AmendmentPoint] {
			guard let id, !index.isEmpty else { return [] }
			return index.points(for: id)
		}

		return incomes.map { $0.snapshot(amendments: points($0.persistentModelID)) }
			+ expenses.map { $0.snapshot(amendments: points($0.persistentModelID)) }
			+ envelopes.map { $0.snapshot(amendments: points($0.persistentModelID)) }
			// a goal's contribution schedule isn't an ExpectedTransaction, so it
			// has no amendments to resolve -- change the contribution and the
			// simulator is the place that shows you what it does
			+ goals.filter(\.participatesInProjection).map { $0.snapshot() }
	}

	/// every schedule that should participate in a cashflow projection
	func scheduleSnapshots(includeGoals: Bool = true) -> [ScheduleSnapshot] {
		BudgetService.snapshots(
			incomes: fetch(ExpectedIncome.self),
			expenses: fetch(ExpectedExpense.self),
			envelopes: fetch(Envelope.self),
			goals: includeGoals ? fetch(Goal.self) : [],
			amendments: fetch(ScheduleAmendment.self)
		)
	}

	/// the standing amount changes, flattened for O(1) lookup
	func amendmentIndex(calendar: Calendar = .current) -> AmendmentIndex {
		AmendmentIndex(fetch(ScheduleAmendment.self), calendar: calendar)
	}

	/// the sparse schedule exceptions, flattened for O(1) lookup
	func overrideIndex(calendar: Calendar = .current) -> OverrideIndex {
		OverrideIndex(fetch(OccurrenceOverride.self), calendar: calendar)
	}

	// MARK: - Projections

	/// bucketed curve over an arbitrary horizon
	func projection(
		in range: Range<Date>,
		openingBalance: Decimal? = nil,
		includeGoals: Bool = true,
		calendar: Calendar = .current
	) -> Projection {
		CashflowProjector.project(
			for: scheduleSnapshots(includeGoals: includeGoals),
			overrides: overrideIndex(calendar: calendar),
			in: range,
			openingBalance: openingBalance,
			calendar: calendar
		)
	}

	/// individual line items -- only ask this over a budget-window sized range
	func events(
		in range: Range<Date>,
		includeGoals: Bool = true,
		calendar: Calendar = .current
	) -> [ScheduledEvent] {
		CashflowProjector.events(
			for: scheduleSnapshots(includeGoals: includeGoals),
			overrides: overrideIndex(calendar: calendar),
			in: range,
			calendar: calendar
		)
	}

	/// run a candidate purchase against the current picture
	func affordability(
		of candidate: CandidateSchedule,
		in range: Range<Date>,
		openingBalance: Decimal? = nil,
		buffer: Decimal = 0,
		calendar: Calendar = .current
	) -> AffordabilityEngine.Result {
		AffordabilityEngine.evaluate(
			candidate: candidate.snapshot(),
			against: scheduleSnapshots(),
			overrides: overrideIndex(calendar: calendar),
			in: range,
			openingBalance: openingBalance,
			buffer: buffer,
			calendar: calendar
		)
	}

	// MARK: - Overrides

	/// find the existing exception for a slot, if any
	func override(for expected: ExpectedTransaction, on occurrenceDate: Date) -> OccurrenceOverride? {
		let day = Calendar.current.startOfDay(for: occurrenceDate)
		let next = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
		let targetID = expected.persistentModelID

		let descriptor = FetchDescriptor<OccurrenceOverride>(
			predicate: #Predicate { $0.occurrenceDate >= day && $0.occurrenceDate < next }
		)
		return (try? context.fetch(descriptor))?
			.first { $0.expected?.persistentModelID == targetID }
	}

	/// upsert an exception, deleting it instead if it no longer deviates
	@discardableResult
	func setOverride(
		for expected: ExpectedTransaction,
		on occurrenceDate: Date,
		isSkipped: Bool = false,
		movedTo: Date? = nil,
		amountOverride: Decimal? = nil
	) -> OccurrenceOverride? {
		let existing = override(for: expected, on: occurrenceDate)

		// a no-op override is just a wasted row
		if !isSkipped && movedTo == nil && amountOverride == nil {
			if let existing { context.delete(existing) }
			try? context.save()
			return nil
		}

		let target = existing ?? {
			let created = OccurrenceOverride(expected: expected, occurrenceDate: occurrenceDate)
			context.insert(created)
			return created
		}()

		target.isSkipped = isSkipped
		target.movedTo = movedTo
		target.amountOverride = amountOverride
		try? context.save()
		return target
	}

	// MARK: - Helpers

	private func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
		(try? context.fetch(FetchDescriptor<T>())) ?? []
	}
}
