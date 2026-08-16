import Foundation
import SwiftData

/* --- Goal simulator ---
 * "what if I put in £X instead of £Y, and it earns 4%?"
 *
 * the rest of the app projects *cashflow* — money leaving your account. a goal
 * is the other side of that: money arriving in a pot that then grows on its own.
 * a HYSA at 4% APY contributing biweekly is not a straight line, and the whole
 * reason to ask this question is that compounding makes the answer unobvious.
 *
 * two things had to be right:
 *
 * 1. **interest accrues on time, not per contribution.** growth depends on how
 *    long money has been in there, so the balance is rolled forward day by day
 *    between contributions rather than multiplied once per deposit.
 *
 * 2. **APY is what your bank quotes**, and it already includes compounding. so
 *    the daily rate is the 365th root of (1 + APY), not APY/365 — the naive
 *    version overstates a 4% account by a few pounds a year, which is small,
 *    wrong, and exactly the sort of thing you'd never catch by eye.
 */
@available(iOS 26, *)
nonisolated enum GoalSimulator {

	/// one scenario's worth of answer
	struct Result: Sendable {
		let points: [Point]
        /// when the target is reached, if it is inside the horizon
		let completion: Date?
		let finalBalance: Decimal
		let totalContributed: Decimal
		let totalInterest: Decimal

		var reachesTarget: Bool { completion != nil }
	}

	struct Point: Identifiable, Sendable, Hashable {
		let date: Date
		let balance: Decimal
		/// balance excluding interest, so the two can be drawn apart
		let contributedOnly: Decimal

		var id: Date { date }
		var interest: Decimal { balance - contributedOnly }
	}

	/// what a scenario is: an amount, a rhythm, and a rate
	struct Scenario: Sendable, Hashable {
		var contribution: Decimal
		var rule: Calendar.RecurrenceRule?
		var start: Date
		/// annual percentage yield, as a fraction (0.04 == 4%)
		var annualRate: Decimal
		var openingBalance: Decimal

		init(
			contribution: Decimal,
			rule: Calendar.RecurrenceRule?,
			start: Date = .now,
			annualRate: Decimal = 0,
			openingBalance: Decimal = 0
		) {
			self.contribution = contribution
			self.rule = rule
			self.start = start
			self.annualRate = annualRate
			self.openingBalance = openingBalance
		}
	}

	/// run a scenario forward to `horizon`, stopping early once `target` is met
	static func simulate(
		_ scenario: Scenario,
		target: Decimal,
		from startDate: Date = .now,
		horizon: Date,
		calendar: Calendar = .current
	) -> Result {
		let start = calendar.startOfDay(for: startDate)
		let end = calendar.startOfDay(for: horizon)
		guard end > start else {
			return Result(
				points: [],
				completion: nil,
				finalBalance: scenario.openingBalance,
				totalContributed: 0,
				totalInterest: 0
			)
		}

		// contribution dates up front, so the day loop is a single walk
		var contributionDates: [Date] = []
		if scenario.contribution > 0 {
			if let rule = scenario.rule {
				for date in rule.recurrences(of: scenario.start, in: start..<end) {
					contributionDates.append(calendar.startOfDay(for: date))
					if contributionDates.count > 20_000 { break }
				}
			} else if scenario.start >= start && scenario.start < end {
				contributionDates.append(calendar.startOfDay(for: scenario.start))
			}
		}
		contributionDates.sort()

		let dailyRate = dailyGrowthFactor(annualRate: scenario.annualRate)

		var balance = scenario.openingBalance
		var contributed = scenario.openingBalance
		var completion: Date?
		var points: [Point] = []
		var contributionIndex = 0

		// sample the curve rather than storing every day: a 30-year horizon is
		// ~11k days and no chart needs 11k points
		let totalDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0
		let stride = Swift.max(totalDays / 240, 1)

		var day = start
		var dayNumber = 0

		while day < end {
			// interest first, on yesterday's balance
			if dailyRate != 1, balance > 0 {
				balance *= dailyRate
			}

			while contributionIndex < contributionDates.count,
				  contributionDates[contributionIndex] <= day {
				balance += scenario.contribution
				contributed += scenario.contribution
				contributionIndex += 1
			}

			if completion == nil, target > 0, balance >= target {
				completion = day
			}

			if dayNumber % stride == 0 || day == start {
				points.append(Point(date: day, balance: balance, contributedOnly: contributed))
			}

			guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
			day = next
			dayNumber += 1
		}

		points.append(Point(date: end, balance: balance, contributedOnly: contributed))

		return Result(
			points: points,
			completion: completion,
			finalBalance: balance,
			totalContributed: contributed - scenario.openingBalance,
			totalInterest: balance - contributed
		)
	}

	/// the daily factor that compounds to the quoted APY over a year
	///
	/// APY already includes compounding, so this is the 365th root of (1 + rate),
	/// not rate/365. Decimal has no pow for fractional exponents, so the maths
	/// goes through Double and comes back — the precision loss is far below a
	/// penny and the alternative is a wrong number.
	static func dailyGrowthFactor(annualRate: Decimal) -> Decimal {
		guard annualRate > 0 else { return 1 }
		let annual = NSDecimalNumber(decimal: annualRate).doubleValue
		let daily = pow(1 + annual, 1.0 / 365.0)
		return Decimal(daily)
	}

	/// how long until the target, expressed the way people ask it
	static func timeToTarget(
		from start: Date,
		to completion: Date,
		calendar: Calendar = .current
	) -> String {
		let parts = calendar.dateComponents([.year, .month], from: start, to: completion)
		let years = parts.year ?? 0
		let months = parts.month ?? 0

		switch (years, months) {
		case (0, 0): return "under a month"
		case (0, _): return "\(months) month\(months == 1 ? "" : "s")"
		case (_, 0): return "\(years) year\(years == 1 ? "" : "s")"
		default: return "\(years)y \(months)m"
		}
	}
}
