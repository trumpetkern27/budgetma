import Foundation
import SwiftData

/* --- Cashflow Projector ---
 * the engine
 *
 * takes schedule snapshots + the sparse override index, and answers two
 * different shaped questions:
 *
 *   events(in:)  -> every line item, materialised. for the budget window list.
 *                   only ever asked over short ranges.
 *   project(in:) -> a bucketed curve. for charts and affordability. streams
 *                   events into buckets and discards them, so memory is O(buckets)
 *                   no matter how long the horizon is.
 *
 * nothing in here knows what a month is, or that a paycheck is different from
 * rent. arbitrary intervals work because they were never special-cased.
 */
@available(iOS 26, *)
nonisolated enum CashflowProjector {

	/// how far outside the range to look for occurrences that an override might
	/// have *moved into* it. without this, "rent moved from Jan 31 to Feb 2"
	/// would vanish from a February window.
	private static let overrideLookaround: TimeInterval = 90 * 86_400

	/// hard stop so a pathological rule (daily, over a millennium) can't spin
	/// forever. hit only in absurd cases; the bucketed path is the intended one.
	private static let occurrenceCap = 200_000

	// MARK: - Events

	/// every occurrence in `range`, with overrides applied, sorted by date.
	/// use over short windows only -- this materialises.
	static func events(
		for schedules: [ScheduleSnapshot],
		overrides: OverrideIndex = .empty,
		in range: Range<Date>,
		calendar: Calendar = .current
	) -> [ScheduledEvent] {
		var out: [ScheduledEvent] = []
		for schedule in schedules {
			forEachEvent(of: schedule, overrides: overrides, in: range, calendar: calendar) {
				out.append($0)
			}
		}
		return out.sorted { $0.date < $1.date }
	}

	/// streams the events of one schedule through `body`, never building an array
	static func forEachEvent(
		of schedule: ScheduleSnapshot,
		overrides: OverrideIndex,
		in range: Range<Date>,
		calendar: Calendar = .current,
		_ body: (ScheduledEvent) -> Void
	) {
		/* with no exceptions in play there's nothing to move an occurrence in
		 * from outside the range, and nothing to look up per occurrence. that
		 * lets us skip both the widened search and building an OccurrenceSlot
		 * (a startOfDay call) for every single date -- which over a very long
		 * horizon is the bulk of the work.
		 */
		let hasOverrides = !overrides.isEmpty
		let searchRange = hasOverrides
			? range.lowerBound.addingTimeInterval(-overrideLookaround)
				..< range.upperBound.addingTimeInterval(overrideLookaround)
			: range

		var emitted = 0
		for occurrence in rawOccurrences(of: schedule, in: searchRange) {
			emitted += 1
			if emitted > occurrenceCap { break }

			var date = occurrence
			/* amendments first, then the per-occurrence override.
			 *
			 * the order is the precedence: an amendment says "from here on it's
			 * £X", an override says "this one time it was £Y". the specific
			 * exception has to win over the standing change, or you could never
			 * record a one-off deviation from a post-raise salary.
			 */
			var amount = schedule.amount(effectiveOn: occurrence)

			// apply the sparse override for this slot, if there is one
			if hasOverrides, let sourceID = schedule.sourceID {
				let slot = OccurrenceSlot(
					sourceID: sourceID,
					occurrenceDate: occurrence,
					calendar: calendar
				)
				if let resolution = overrides.resolution(for: slot) {
					if resolution.isSkipped { continue }
					if let moved = resolution.movedTo { date = moved }
					if let override = resolution.amountOverride { amount = override }
				}
			}

			// the *final* date decides membership, so a moved event lands in the
			// window it was moved into. without overrides the generator already
			// bounded us, so the check is only needed when one could have moved.
			if hasOverrides, !range.contains(date) { continue }

			body(
				ScheduledEvent(
					occurrenceDate: occurrence,
					date: date,
					amount: amount,
					kind: schedule.kind,
					name: schedule.name,
					emoji: schedule.emoji,
					sourceID: schedule.sourceID
				)
			)
		}
	}

	/// the dates a schedule produces, before any override is considered
	private static func rawOccurrences(
		of schedule: ScheduleSnapshot,
		in range: Range<Date>
	) -> AnySequence<Date> {
		guard let rule = schedule.rule else {
			// one-time item: happens once, on its start date
			return AnySequence(range.contains(schedule.start) ? [schedule.start] : [])
		}
		return AnySequence(rule.recurrences(of: schedule.start, in: range))
	}

	// MARK: - Projection

	/// bucketed cumulative curve over `range`
	///
	/// `openingBalance` is a pure offset: nil (the default) means net-flow mode,
	/// where the curve starts at zero and shows drift. passing a balance shifts
	/// the same curve into absolute terms without changing any of the maths.
	static func project(
		for schedules: [ScheduleSnapshot],
		overrides: OverrideIndex = .empty,
		in range: Range<Date>,
		openingBalance: Decimal? = nil,
		targetBuckets: Int = 120,
		calendar: Calendar = .current
	) -> Projection {
		let granularity = ProjectionGranularity.fitting(range, targetBuckets: targetBuckets)
		let boundaries = bucketBoundaries(range: range, granularity: granularity, calendar: calendar)

		guard boundaries.count > 1 else {
			return Projection(
				range: range,
				granularity: granularity,
				buckets: [],
				openingBalance: openingBalance
			)
		}

		// accumulate into flat arrays keyed by bucket index -- cheap, and keeps
		// memory tied to bucket count rather than event count
		var inflows = [Decimal](repeating: 0, count: boundaries.count - 1)
		var outflows = [Decimal](repeating: 0, count: boundaries.count - 1)

		for schedule in schedules {
			let (scheduleIn, scheduleOut) = accumulate(
				schedule: schedule,
				overrides: overrides,
				in: range,
				boundaries: boundaries,
				calendar: calendar
			)
			for index in inflows.indices {
				inflows[index] += scheduleIn[index]
				outflows[index] += scheduleOut[index]
			}
		}

		var running = openingBalance ?? 0
		var buckets: [ProjectionBucket] = []
		buckets.reserveCapacity(inflows.count)

		for index in inflows.indices {
			running += inflows[index] - outflows[index]
			buckets.append(
				ProjectionBucket(
					start: boundaries[index],
					end: boundaries[index + 1],
					inflow: inflows[index],
					outflow: outflows[index],
					cumulative: running
				)
			)
		}

		return Projection(
			range: range,
			granularity: granularity,
			buckets: buckets,
			openingBalance: openingBalance
		)
	}

	/// bucket one schedule's events into inflow/outflow totals
	private static func accumulate(
		schedule: ScheduleSnapshot,
		overrides: OverrideIndex,
		in range: Range<Date>,
		boundaries: [Date],
		calendar: Calendar
	) -> (inflows: [Decimal], outflows: [Decimal]) {
		var inflows = [Decimal](repeating: 0, count: boundaries.count - 1)
		var outflows = [Decimal](repeating: 0, count: boundaries.count - 1)

		forEachEvent(of: schedule, overrides: overrides, in: range, calendar: calendar) { event in
			guard let index = bucketIndex(for: event.date, in: boundaries) else { return }
			switch event.sign {
			case .inflow: inflows[index] += event.amount
			case .outflow: outflows[index] += event.amount
			}
		}
		return (inflows, outflows)
	}

	/// the same projection, with schedules fanned out across cores
	///
	/// Foundation's recurrence generator runs at roughly 9k occurrences/sec, so
	/// a very long horizon is bound by raw occurrence count and nothing else.
	/// schedules are independent, so projecting them concurrently divides that
	/// wall-clock cost by however many cores are going spare. identical output
	/// to `project` -- addition doesn't care what order it happens in.
	static func projectConcurrently(
		for schedules: [ScheduleSnapshot],
		overrides: OverrideIndex = .empty,
		in range: Range<Date>,
		openingBalance: Decimal? = nil,
		targetBuckets: Int = 120,
		calendar: Calendar = .current
	) async -> Projection {
		let granularity = ProjectionGranularity.fitting(range, targetBuckets: targetBuckets)
		let boundaries = bucketBoundaries(range: range, granularity: granularity, calendar: calendar)

		guard boundaries.count > 1, !schedules.isEmpty else {
			return Projection(
				range: range,
				granularity: granularity,
				buckets: [],
				openingBalance: openingBalance
			)
		}

		let bucketCount = boundaries.count - 1
		var inflows = [Decimal](repeating: 0, count: bucketCount)
		var outflows = [Decimal](repeating: 0, count: bucketCount)

		await withTaskGroup(of: (inflows: [Decimal], outflows: [Decimal]).self) { group in
			for schedule in schedules {
				group.addTask {
					accumulate(
						schedule: schedule,
						overrides: overrides,
						in: range,
						boundaries: boundaries,
						calendar: calendar
					)
				}
			}

			for await partial in group {
				for index in 0..<bucketCount {
					inflows[index] += partial.inflows[index]
					outflows[index] += partial.outflows[index]
				}
			}
		}

		var running = openingBalance ?? 0
		var buckets: [ProjectionBucket] = []
		buckets.reserveCapacity(bucketCount)

		for index in 0..<bucketCount {
			running += inflows[index] - outflows[index]
			buckets.append(
				ProjectionBucket(
					start: boundaries[index],
					end: boundaries[index + 1],
					inflow: inflows[index],
					outflow: outflows[index],
					cumulative: running
				)
			)
		}

		return Projection(
			range: range,
			granularity: granularity,
			buckets: buckets,
			openingBalance: openingBalance
		)
	}

	// MARK: - Bucketing

	/// bucket edges covering `range`, aligned to natural calendar boundaries
	static func bucketBoundaries(
		range: Range<Date>,
		granularity: ProjectionGranularity,
		calendar: Calendar = .current
	) -> [Date] {
		/* the first boundary is always the range start, never the aligned one.
		 * snapping a 1000-year projection to a decade boundary would otherwise
		 * open the chart in 2020 for a horizon that begins in 2026 -- and then
		 * report the trough as happening six years before the projection does.
		 * so we align the *interior* boundaries and let the first and last
		 * buckets be partial.
		 */
		var boundaries: [Date] = [range.lowerBound]
		var cursor = alignedStart(for: range.lowerBound, granularity: granularity, calendar: calendar)

		func advance() -> Bool {
			guard let next = calendar.date(
				byAdding: granularity.component,
				value: granularity.step,
				to: cursor
			), next > cursor else { return false }
			cursor = next
			return true
		}

		// walk forward to the first aligned boundary strictly inside the range
		while cursor <= range.lowerBound {
			guard advance() else { return [range.lowerBound, range.upperBound] }
		}

		// generous ceiling; `fitting` targets ~120 so this is only a backstop
		let cap = 10_000
		while cursor < range.upperBound && boundaries.count < cap {
			boundaries.append(cursor)
			guard advance() else { break }
		}

		// close off the final bucket
		boundaries.append(range.upperBound)
		return boundaries
	}

	/// snap a date down to the start of its bucket
	private static func alignedStart(
		for date: Date,
		granularity: ProjectionGranularity,
		calendar: Calendar
	) -> Date {
		switch granularity {
		case .day:
			return calendar.startOfDay(for: date)
		case .week:
			return calendar.dateInterval(of: .weekOfYear, for: date)?.start
				?? calendar.startOfDay(for: date)
		case .month:
			return calendar.dateInterval(of: .month, for: date)?.start
				?? calendar.startOfDay(for: date)
		case .quarter:
			// dateInterval(of: .quarter,) is unreliable; derive it from the month
			let month = calendar.component(.month, from: date)
			let quarterStartMonth = ((month - 1) / 3) * 3 + 1
			var components = calendar.dateComponents([.year], from: date)
			components.month = quarterStartMonth
			components.day = 1
			return calendar.date(from: components) ?? calendar.startOfDay(for: date)
		case .year:
			return calendar.dateInterval(of: .year, for: date)?.start
				?? calendar.startOfDay(for: date)
		case .decade:
			let year = calendar.component(.year, from: date)
			var components = DateComponents()
			components.year = (year / 10) * 10
			components.month = 1
			components.day = 1
			return calendar.date(from: components) ?? calendar.startOfDay(for: date)
		}
	}

	/// which bucket a date falls into, by binary search over the edges
	private static func bucketIndex(for date: Date, in boundaries: [Date]) -> Int? {
		guard let first = boundaries.first, let last = boundaries.last,
			  date >= first, date < last else { return nil }

		var low = 0
		var high = boundaries.count - 1
		while low < high - 1 {
			let mid = (low + high) / 2
			if boundaries[mid] <= date { low = mid } else { high = mid }
		}
		return low
	}
}
