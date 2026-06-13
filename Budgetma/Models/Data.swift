import SwiftUI
import SwiftData

@Model
final class Transaction {
	var date: Date
	var amount: Decimal
	var category: Category?
	var note: String

	init(
		date: Date,
		amount: Decimal,
		category: Category?,
		note: String
	) {
		self.date = date
		self.amount = amount
		self.category = category
		self.note = note
	}
}

@Model
final class Category {
	@Attribute(.unique)
	var id: UUID
	@Attribute(.unique)
	var name: String
	var emoji: String
	var isActive: Bool

	init(
		name: String,
		emoji: String,
		isActive: Bool = true
	) {
		self.id = UUID()
		self.name = name
		self.emoji = emoji
		self.isActive = isActive
	}
}

@Model
final class ExpectedTransaction {
	var amount: Decimal
	var name: String
	var regularity: RecurrenceRule?
	var category: Category?

	init(
		name: String,
		amount: Decimal,
		regularity: RecurrenceRule?,
		category: Category?
	) {
		self.name = name
		self.amount = amount
		self.regularity = regularity
		self.category = category
	}
}

@Model
final class Envelope {
	var amount: Decimal
	var name: String
	var regularity: RecurrenceRule?
	var category: Category?
	var carryOver: Bool

	init(
		name: String,
		amount: Decimal,
		regularity: RecurrenceRule?,
		category: Category?,
		carryOver: Bool = false
	) {
		self.name = name
		self.amount = amount
		self.regularity = regularity
		self.category = category
		self.carryOver = carryOver
	}
}

@Model
final class Income {
	var name: String
	var amount: Decimal
	var regularity: RecurrenceRule?
	var category: Category?

	init(
		name: String,
		amount: Decimal,
		regularity: RecurrenceRule?,
		category: Category?
	) {
		self.name = name
		self.amount = amount
		self.regularity = regularity
		self.category = category
	}
}

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

let defaultCategory = Category(name: "Misc", emoji: "🗿")
