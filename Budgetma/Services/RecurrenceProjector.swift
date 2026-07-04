import Foundation

enum RecurrenceProjector {
	static func nextOccurence(
		startDate: Date,
		regularity: RecurrenceRule?,
		after date: Date = .now
	) -> Date? {
		guard let rule = regularity?.toRecurranceRule() else {
			return startDate >= date ? startDate : nil
		}
		return rule.recurrences(of: startDate).first { $0 >= date }
	}

	static func occurrences(
		startDate: Date,
		regularity: RecurrenceRule?,
		in range: Range<Date>
	) -> [Date] {
		guard let rule = regularity?.toRecurranceRule() else {
			return range.contains(startDate) ? [startDate] : []
		}
		return Array(rule.recurrences(of: startDate, in: range))
	}
}
