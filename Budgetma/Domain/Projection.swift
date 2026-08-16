import Foundation

/* --- Projection granularity ---
 * a projection can span a day or a millennium, and the chart has to stay
 * readable (and the memory bounded) either way. so we never plot raw events --
 * we bucket them, and the bucket size is *derived from the horizon* rather than
 * hardcoded. 30 days buckets by day; 1000 years buckets by decade. both draw
 * roughly the same number of points.
 */
nonisolated enum ProjectionGranularity: String, CaseIterable, Sendable {
	case day, week, month, quarter, year, decade

	var component: Calendar.Component {
		switch self {
		case .day: return .day
		case .week: return .weekOfYear
		case .month: return .month
		case .quarter: return .quarter
		case .year, .decade: return .year
		}
	}

	/// how many of `component` make up one bucket
	var step: Int {
		switch self {
		case .decade: return 10
		case .quarter: return 3
		default: return 1
		}
	}

	/// rough length in days, used only to pick a granularity
	var approximateDays: Double {
		switch self {
		case .day: return 1
		case .week: return 7
		case .month: return 30.44
		case .quarter: return 91.31
		case .year: return 365.25
		case .decade: return 3652.5
		}
	}

	/// adjectival -- "Weekly totals"
	var label: String {
		switch self {
		case .day: return "Daily"
		case .week: return "Weekly"
		case .month: return "Monthly"
		case .quarter: return "Quarterly"
		case .year: return "Yearly"
		case .decade: return "Per decade"
		}
	}

	/// the bare noun -- "101 decades", where `label` would read "101 per decade"
	var periodNoun: String {
		switch self {
		case .day: return "day"
		case .week: return "week"
		case .month: return "month"
		case .quarter: return "quarter"
		case .year: return "year"
		case .decade: return "decade"
		}
	}

	/// pick the coarsest granularity that still gives us a decent number of points
	static func fitting(_ range: Range<Date>, targetBuckets: Int = 120) -> ProjectionGranularity {
		let days = range.upperBound.timeIntervalSince(range.lowerBound) / 86_400
		for granularity in ProjectionGranularity.allCases {
			if days / granularity.approximateDays <= Double(targetBuckets) {
				return granularity
			}
		}
		return .decade
	}
}

/* --- Projection bucket ---
 * one point on the chart: what came in, what went out, and the running total
 */
nonisolated struct ProjectionBucket: Identifiable, Sendable {
	let start: Date
	let end: Date
	var inflow: Decimal
	var outflow: Decimal
	/// running cumulative net across the whole projection, including any
	/// opening balance offset. this is the line the chart draws.
	var cumulative: Decimal

	var id: Date { start }
	var net: Decimal { inflow - outflow }
}

/* --- Projection ---
 * the result of running the engine over a horizon
 *
 * note there's no `events` array here on purpose: a millennium-long projection
 * would be millions of events. the engine streams them into buckets and throws
 * the individual events away. when you need the actual line items -- the budget
 * window list -- you ask CashflowProjector for events over a short range
 * instead.
 */
nonisolated struct Projection: Sendable {
	let range: Range<Date>
	let granularity: ProjectionGranularity
	let buckets: [ProjectionBucket]
	/// nil means pure net-flow mode: the curve starts at zero and shows drift
	/// rather than an absolute balance
	let openingBalance: Decimal?

	var totalInflow: Decimal { buckets.reduce(0) { $0 + $1.inflow } }
	var totalOutflow: Decimal { buckets.reduce(0) { $0 + $1.outflow } }
	var net: Decimal { totalInflow - totalOutflow }

	var startingValue: Decimal { openingBalance ?? 0 }
	var endingValue: Decimal { buckets.last?.cumulative ?? startingValue }

	/// the deepest point of the curve -- the moment you'd be most stretched.
	/// this is the number affordability actually turns on.
	var trough: ProjectionBucket? {
		buckets.min { $0.cumulative < $1.cumulative }
	}

	var peak: ProjectionBucket? {
		buckets.max { $0.cumulative < $1.cumulative }
	}

	static func empty(range: Range<Date>) -> Projection {
		Projection(
			range: range,
			granularity: .fitting(range),
			buckets: [],
			openingBalance: nil
		)
	}
}
