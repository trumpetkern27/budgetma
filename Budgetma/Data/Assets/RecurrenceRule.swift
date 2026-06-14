import SwiftUI
import SwiftData

/* --- Recurrence Rule Model ---
 * imitating the ios recurrence rule
 * bc it would be way too easy if you could just store a Calendar.RecurrenceRule in a @Model
 * i mean why would anyone want to do that
 */
@Model
final class RecurrenceRule {
	var frequencyRaw: Int
	var interval: Int
	var endDate: Date?
	var occuranceCount: Int?

	var daysOfWeekEncoded: [String]
	var daysOfMonth: [Int]
	var daysOfYear: [Int]
	var weeksOfYear: [Int]
	var monthsOfYear: [Int]
	var setPositions: [Int]

	init(
		frequency: Calendar.RecurrenceRule.Frequency,
		interval: Int = 1,
		endDate: Date? = nil,
		occuranceCount: Int? = nil,
		daysOfWeek: [(Locale.Weekday, Int?)] = [], // (weekday, ordinal?)
		daysOfMonth: [Int] = [],
		daysOfYear: [Int] = [],
		weeksOfYear: [Int] = [],
		monthsOfYear: [Int] = [],
		setPositions: [Int] = []
	) {
		self.frequencyRaw = frequency.rawValue
		self.interval = interval
		self.endDate = endDate
		self.occuranceCount = occuranceCount
		self.daysOfWeekEncoded = daysOfWeek.map { weekday, ordinal in
			"\(weekday.rawValue),\(ordinal ?? 0)"
		}
		self.daysOfMonth = daysOfMonth
		self.daysOfYear = daysOfYear
		self.weeksOfYear = weeksOfYear
		self.monthsOfYear = monthsOfYear
		self.setPositions = setPositions
	}

	// convert to the real recurrence rule
	func toRecurranceRule() -> Calendar.RecurrenceRule? {
		guard let freq = Calendar.RecurrenceRule.Frequency(rawValue: frequencyRaw) else {
			return nil
		}

		let weekdays: [Calendar.RecurrenceRule.Weekday] = daysOfWeekEncoded.compactMap { encoded in
			let parts = encoded.split(separator: ",")
			guard parts.count == 2,
				let wdRaw = parts.first.flatMap( {Locale.Weekday(rawValue: String($0))}),
				let ordinal = Int(parts[1])
			else { return nil }

			if ordinal == 0 {
				return .every(wdRaw)
			} else {
				return .nth(ordinal, wdRaw)
			}
		}

		var end: Calendar.RecurrenceRule.End = .never
		if let date = endDate {
			end = .afterDate(date)
		} else if let count = occuranceCount {
			end = .afterOccurrences(count)
		}
		let months = monthsOfYear.map { Calendar.RecurrenceRule.Month($0) }

		return Calendar.RecurrenceRule(
			calendar: .current,
			frequency: freq,
			interval: interval,
			end: end,
			months: months,
			daysOfTheYear: daysOfYear,
			daysOfTheMonth: daysOfMonth,
			weeks: weeksOfYear,
			weekdays: weekdays,
			setPositions: setPositions
		)

	}

	// convert from real recurrence rule
	static func from(_ rule: Calendar.RecurrenceRule) -> RecurrenceRule {
		let weekdays: [(Locale.Weekday, Int?)] = rule.weekdays.map {weekday in
			switch weekday {
			case .every(let day): return (day, nil)
			case .nth(let nth, let day): return (day, nth)
			@unknown default: fatalError("Unhandled weekday case")
			}
		}

		var endDate: Date? = nil
		var count: Int? = nil
		if let date = rule.end.date {
			endDate = date
		} else if let nth = rule.end.occurrences {
			count = nth
		}

		let months = rule.months.map { $0.index }

		return RecurrenceRule(
			frequency: rule.frequency,
			interval: rule.interval,
			endDate: endDate,
			occuranceCount: count,
			daysOfWeek: weekdays,
			daysOfMonth: rule.daysOfTheMonth,
			daysOfYear: rule.daysOfTheYear,
			weeksOfYear: rule.weeks,
			monthsOfYear: months,
			setPositions: rule.setPositions
		)
	}
}
