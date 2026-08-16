import Foundation

/* --- BudgetPeriod ---
 * the app's one notion of "the window you're standing in"
 *
 * Home and Budget used to derive their period two different ways, and both were
 * wrong in their own direction:
 *
 *   Home generated recurrences *forward* from the anchor date, so it could never
 *   page earlier than the anchor -- if your anchor was "today" you were nailed to
 *   the present with no history.
 *
 *   Budget snapped to a calendar week/month boundary, so a fortnightly window sat
 *   off your actual pay cycle: aligned to Monday rather than to the fortnight you
 *   are actually being paid on.
 *
 * both now come from here, off the same rule, so the two screens always agree on
 * what "this period" means.
 *
 * boundaries are pure arithmetic -- anchor + n×interval units, for any integer n,
 * negative as happily as positive. no occurrence generation and no bounded search
 * range, so paging back ten years costs exactly what paging back one does.
 */
nonisolated struct BudgetPeriod: Equatable, Sendable, Identifiable {
	let start: Date
	let end: Date
	/// signed distance, in whole periods, from the period containing "now"
	let offset: Int

	var id: Date { start }
	var range: Range<Date> { start ..< end }

	func contains(_ date: Date) -> Bool { date >= start && date < end }

	/// "Aug 15 – Aug 28" -- end is exclusive, so the label walks it back a day
	func label(style: Date.FormatStyle = .dateTime.month(.abbreviated).day()) -> String {
		start.formatted(style) + " – " + end.addingTimeInterval(-1).formatted(style)
	}
}

/* --- PeriodRule ---
 * how time gets chopped up: an anchor, a frequency and an interval
 *
 * this is the same shape as the calendar settings on the Settings screen, and
 * deliberately *not* a Calendar.RecurrenceRule -- we only need boundary maths,
 * and doing it arithmetically is what makes negative offsets free.
 */
nonisolated struct PeriodRule: Equatable, Sendable {
	var anchor: Date
	var frequency: Calendar.RecurrenceRule.Frequency
	var interval: Int

	init(
		anchor: Date,
		frequency: Calendar.RecurrenceRule.Frequency = .monthly,
		interval: Int = 1
	) {
		self.anchor = anchor
		self.frequency = frequency
		self.interval = Swift.max(interval, 1)
	}

	var component: Calendar.Component {
		switch frequency {
		case .minutely: return .minute
		case .hourly: return .hour
		case .daily: return .day
		case .weekly: return .weekOfYear
		case .monthly: return .month
		case .yearly: return .year
		@unknown default: return .month
		}
	}

	/// rough seconds per period -- only ever used to *seed* the search for the
	/// right boundary, never to define one. month lengths and DST make it
	/// approximate by design; the walk below corrects it.
	private var approximateLength: TimeInterval {
		let unit: TimeInterval
		switch frequency {
		case .minutely: unit = 60
		case .hourly: unit = 3_600
		case .daily: unit = 86_400
		case .weekly: unit = 604_800
		case .monthly: unit = 2_629_746
		case .yearly: unit = 31_556_952
		@unknown default: unit = 2_629_746
		}
		return unit * TimeInterval(interval)
	}

	/// the nth boundary: always measured from the anchor itself, never by
	/// stepping one period at a time, so a monthly rule anchored on the 31st
	/// doesn't ratchet itself down to the 28th and stay there
	func boundary(_ n: Int, calendar: Calendar = .current) -> Date {
		let base = calendar.startOfDay(for: anchor)
		guard n != 0 else { return base }
		return calendar.date(byAdding: component, value: n * interval, to: base) ?? base
	}

	/// which period index `date` falls in
	func index(containing date: Date, calendar: Calendar = .current) -> Int {
		let base = calendar.startOfDay(for: anchor)
		var n = Int((date.timeIntervalSince(base) / approximateLength).rounded(.down))

		// the estimate lands within a step or two; walk it home. the bound is a
		// backstop against a pathological calendar, not an expected path.
		var steps = 0
		while boundary(n, calendar: calendar) > date, steps < 1_000 {
			n -= 1
			steps += 1
		}
		while boundary(n + 1, calendar: calendar) <= date, steps < 1_000 {
			n += 1
			steps += 1
		}
		return n
	}

	/// the period containing `reference`, shifted by `offset` whole periods
	///
	/// negative offsets are ordinary: this is what lets Home page into the past.
	func period(
		offset: Int = 0,
		containing reference: Date = .now,
		calendar: Calendar = .current
	) -> BudgetPeriod {
		let index = self.index(containing: reference, calendar: calendar) + offset
		let start = boundary(index, calendar: calendar)
		var end = boundary(index + 1, calendar: calendar)
		// a degenerate period would break bucketing and day-listing downstream
		if end <= start {
			end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
		}
		return BudgetPeriod(start: start, end: end, offset: offset)
	}

	/// every day in a period, for the calendar grid
	func days(in period: BudgetPeriod, calendar: Calendar = .current) -> [Date] {
		var days: [Date] = []
		var day = calendar.startOfDay(for: period.start)
		// guard against an absurd interval producing a million cells
		while day < period.end && days.count < 400 {
			days.append(day)
			guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
			day = next
		}
		return days
	}
}

/* --- the app-wide period settings ---
 * Home's calendar frequency is the single source of truth for "a period", and
 * Budget follows it. both read the same three AppStorage keys, so changing the
 * frequency in Settings moves both screens together.
 */
@available(iOS 26, *)
nonisolated enum PeriodSettings {
	static let frequencyKey = "calendarViewFrequency"
	static let intervalKey = "calendarViewInterval"
	static let startDateKey = "calendarViewStartDate"

	/// read straight from defaults, for the places that aren't observing them
	static var current: PeriodRule {
		let defaults = UserDefaults.standard

		let frequency = (defaults.object(forKey: frequencyKey) as? Int)
			.flatMap { Calendar.RecurrenceRule.Frequency(rawValue: $0) } ?? .monthly
		let interval = defaults.object(forKey: intervalKey) as? Int ?? 1
		let anchor = defaults.object(forKey: startDateKey) as? Date ?? .now

		return PeriodRule(anchor: anchor, frequency: frequency, interval: interval)
	}
}
