import Foundation

/* --- Affordability Engine ---
 * "can i afford this?" answered against a projection rather than a monthly budget
 *
 * the whole point of the app: monthly expenses and a biweekly paycheck never
 * line up, so a "monthly surplus" number lies to you. what actually matters is
 * whether the *curve* dips below what you can absorb at any point, and whether
 * it still trends upward over the long run. those are two genuinely different
 * failure modes and we report them separately.
 *
 * the maths trick worth knowing: a candidate's effect on the curve is linear in
 * its amount. so we project it once at unit amount and every other question --
 * the combined curve, the largest amount that still fits -- is arithmetic on
 * that one result. no re-projection, no binary search.
 */
@available(iOS 26, *)
nonisolated enum AffordabilityEngine {

	enum Verdict: String, Sendable {
		/// fits with room to spare
		case comfortable
		/// fits, but the margin is thin enough that you should know
		case tight
		/// doesn't fit -- see `failureReason`
		case unaffordable

		var label: String {
			switch self {
			case .comfortable: return "Affordable"
			case .tight: return "Tight"
			case .unaffordable: return "Not affordable"
			}
		}
	}

	enum FailureReason: String, Sendable {
		/// the curve ends lower than it started -- structurally spending more
		/// than you bring in. no cash cushion fixes this.
		case structural
		/// the long run is fine, but the curve dips deeper than your buffer at
		/// some point along the way -- a timing problem, not an income problem
		case liquidity
	}

	struct Result: Sendable {
		let candidateName: String
		let candidateAmount: Decimal
		let baseline: Projection
		let projected: Projection
		let verdict: Verdict
		let failureReason: FailureReason?

		/// deepest point of the curve, before and after taking this on
		let troughBefore: Decimal
		let troughAfter: Decimal
		let troughDate: Date?

		/// where the curve ends up, before and after
		let endBefore: Decimal
		let endAfter: Decimal

		/// what this costs in total across the horizon
		let totalCost: Decimal
		/// the cushion the verdict was judged against
		let buffer: Decimal
		/// largest amount that would still clear the bar; nil == unconstrained
		/// (the candidate never actually occurs inside the horizon)
		let maxAffordable: Decimal?

		/// how much deeper the worst point gets
		var troughImpact: Decimal { troughBefore - troughAfter }
		/// slack remaining at the worst point
		var headroom: Decimal { troughAfter + buffer }
	}

	// MARK: - Evaluation

	/// affordability is judged on finer buckets than a chart needs
	///
	/// the verdict turns entirely on the trough, and a dip that happens *inside*
	/// a bucket is invisible to it. at chart resolution a 5-year horizon buckets
	/// by month, which hides exactly the paycheck-vs-rent gap this app exists to
	/// expose -- and hiding it produces a falsely optimistic "yes". asking for
	/// more buckets pushes the same horizon down to weekly.
	static let verdictTargetBuckets = 500

	static func evaluate(
		candidate: ScheduleSnapshot,
		against schedules: [ScheduleSnapshot],
		overrides: OverrideIndex = .empty,
		in range: Range<Date>,
		openingBalance: Decimal? = nil,
		buffer: Decimal = 0,
		calendar: Calendar = .current
	) -> Result {
		let baseline = CashflowProjector.project(
			for: schedules,
			overrides: overrides,
			in: range,
			openingBalance: openingBalance,
			targetBuckets: verdictTargetBuckets,
			calendar: calendar
		)

		// the candidate alone, at unit amount -- our linear basis.
		// same range and bucket target, so the two share boundaries and can be
		// combined index by index.
		let unit = CashflowProjector.project(
			for: [candidate.repriced(to: 1)],
			overrides: .empty,
			in: range,
			openingBalance: 0,
			targetBuckets: verdictTargetBuckets,
			calendar: calendar
		)

		let projected = combine(baseline: baseline, unit: unit, amount: candidate.amount)

		let troughBefore = baseline.trough?.cumulative ?? (openingBalance ?? 0)
		let troughAfter = projected.trough?.cumulative ?? (openingBalance ?? 0)
		let endBefore = baseline.endingValue
		let endAfter = projected.endingValue

		// unit cumulative is negative for an outflow candidate; magnitude at the
		// end is how many times it occurs, so total cost falls straight out
		let unitEnd = unit.buckets.last?.cumulative ?? 0
		let totalCost = abs(unitEnd) * candidate.amount

		let (verdict, reason) = judge(
			troughAfter: troughAfter,
			endAfter: endAfter,
			endBefore: endBefore,
			buffer: buffer,
			openingBalance: openingBalance
		)

		return Result(
			candidateName: candidate.name,
			candidateAmount: candidate.amount,
			baseline: baseline,
			projected: projected,
			verdict: verdict,
			failureReason: reason,
			troughBefore: troughBefore,
			troughAfter: troughAfter,
			troughDate: projected.trough?.start,
			endBefore: endBefore,
			endAfter: endAfter,
			totalCost: totalCost,
			buffer: buffer,
			maxAffordable: solveMaxAffordable(
				baseline: baseline,
				unit: unit,
				buffer: buffer,
				openingBalance: openingBalance
			)
		)
	}

	// MARK: - Verdict

	private static func judge(
		troughAfter: Decimal,
		endAfter: Decimal,
		endBefore: Decimal,
		buffer: Decimal,
		openingBalance: Decimal?
	) -> (Verdict, FailureReason?) {
		let floor = (openingBalance ?? 0) - buffer

		// structural: the curve ends below where it began. taking this on means
		// steadily losing ground, which no amount of cash cushion survives.
		if endAfter < (openingBalance ?? 0) {
			return (.unaffordable, .structural)
		}
		// liquidity: long run is fine but you'd dip past your cushion en route
		if troughAfter < floor {
			return (.unaffordable, .liquidity)
		}

		// it fits -- but flag it if the margin is slim on either axis.
		// "tight" if the surplus shrinks by more than 3/4, or the worst point
		// sits within 10% of the floor.
		let surplusBefore = endBefore - (openingBalance ?? 0)
		let surplusAfter = endAfter - (openingBalance ?? 0)
		if surplusBefore > 0 && surplusAfter * 4 < surplusBefore {
			return (.tight, nil)
		}
		let slack = troughAfter - floor
		if buffer > 0 && slack * 10 < buffer {
			return (.tight, nil)
		}
		if surplusAfter <= 0 {
			return (.tight, nil)
		}
		return (.comfortable, nil)
	}

	// MARK: - Linear combination

	/// baseline + amount x unit, bucket by bucket
	///
	/// valid because both projections share a range, and therefore share
	/// granularity and bucket boundaries
	static func combine(baseline: Projection, unit: Projection, amount: Decimal) -> Projection {
		guard baseline.buckets.count == unit.buckets.count else { return baseline }

		var buckets: [ProjectionBucket] = []
		buckets.reserveCapacity(baseline.buckets.count)

		for index in baseline.buckets.indices {
			let base = baseline.buckets[index]
			let scaled = unit.buckets[index]
			buckets.append(
				ProjectionBucket(
					start: base.start,
					end: base.end,
					inflow: base.inflow + scaled.inflow * amount,
					outflow: base.outflow + scaled.outflow * amount,
					cumulative: base.cumulative + scaled.cumulative * amount
				)
			)
		}

		return Projection(
			range: baseline.range,
			granularity: baseline.granularity,
			buckets: buckets,
			openingBalance: baseline.openingBalance
		)
	}

	// MARK: - Max affordable

	/// largest candidate amount that still clears both bars, solved exactly
	///
	/// for every bucket i we need   B[i] + a * C[i] >= floor
	/// with C[i] <= 0 for an outflow, that rearranges to
	///                              a <= (B[i] - floor) / -C[i]
	/// so the answer is the tightest of those constraints. the end-of-horizon
	/// sustainability bar is the same inequality with floor = opening balance.
	static func solveMaxAffordable(
		baseline: Projection,
		unit: Projection,
		buffer: Decimal,
		openingBalance: Decimal?
	) -> Decimal? {
		guard baseline.buckets.count == unit.buckets.count else { return nil }

		let opening = openingBalance ?? 0
		let floor = opening - buffer
		var limit: Decimal?

		func tighten(to value: Decimal) {
			limit = limit.map { Swift.min($0, value) } ?? value
		}

		for index in baseline.buckets.indices {
			let draw = -unit.buckets[index].cumulative	// positive for an outflow
			guard draw > 0 else { continue }			// no constraint yet

			// liquidity bar, at every point along the way
			tighten(to: (baseline.buckets[index].cumulative - floor) / draw)
		}

		// sustainability bar, at the end of the horizon
		if let lastBase = baseline.buckets.last, let lastUnit = unit.buckets.last {
			let draw = -lastUnit.cumulative
			if draw > 0 {
				tighten(to: (lastBase.cumulative - opening) / draw)
			}
		}

		guard let limit else { return nil }		// candidate never occurs in range
		return Swift.max(limit, 0)
	}
}
