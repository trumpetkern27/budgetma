import Foundation
import SwiftData

/* --- Envelope Ledger ---
 * what's actually left in an envelope right now
 *
 * an envelope is funded on a schedule and spent against ad hoc, so its periods
 * are the gaps between funding occurrences -- which, like everything else here,
 * can be any interval at all. every 6 weeks for the barber is not a special
 * case of monthly, it's just a different rule.
 *
 * carryOver decides what happens to what's left at the end of a period:
 * true rolls it into the next one, false is use-it-or-lose-it.
 */
@available(iOS 26, *)
enum EnvelopeLedger {

	/// one funding cycle
	struct Period: Identifiable {
		let start: Date
		let end: Date
		/// what the schedule put in at the start of this period
		let funded: Decimal
		/// what rolled in from the previous period (always 0 when carryOver is off)
		let carriedIn: Decimal
		let spent: Decimal
		let expenses: [Expense]

		var id: Date { start }
		var budget: Decimal { funded + carriedIn }
		var available: Decimal { budget - spent }
		var isOverspent: Bool { available < 0 }

		/// 0...1 of the budget consumed, for a gauge
		var utilisation: Double {
			guard budget > 0 else { return spent > 0 ? 1 : 0 }
			let ratio = spent / budget
			return min(max(NSDecimalNumber(decimal: ratio).doubleValue, 0), 1)
		}

		func contains(_ date: Date) -> Bool { date >= start && date < end }
	}

	/// every funding cycle of an envelope across `range`, with spending applied
	static func periods(
		for envelope: Envelope,
		expenses: [Expense],
		in range: Range<Date>,
		amendments: [AmendmentPoint] = [],
		calendar: Calendar = .current
	) -> [Period] {
		let snapshot = envelope.snapshot(amendments: amendments)

		/* funding dates bound the periods, and they are *days*, not instants.
		 *
		 * an envelope's start date carries whatever time of day it was created
		 * at, and the projector faithfully preserves it. left alone, a fortnightly
		 * envelope created at 15:47 produces cycles like
		 * [Aug 1 15:47, Aug 15 15:47) while the budget window is
		 * [Aug 15 00:00, Aug 29 00:00) — so the *previous* cycle ends after the
		 * window begins and leaks into it as a phantom second envelope, and the
		 * current cycle's exclusive end lands a day later than it should in every
		 * label. snapping to the day makes cycles line up with pay periods
		 * exactly, which is the entire point of matching their intervals.
		 */
		var fundingDates: [Date] = []
		CashflowProjector.forEachEvent(
			of: snapshot,
			overrides: .empty,
			in: range,
			calendar: calendar
		) { fundingDates.append(calendar.startOfDay(for: $0.date)) }
		fundingDates.sort()

		guard !fundingDates.isEmpty else { return [] }

		// only spending tagged to this envelope counts against it
		let envelopeID = envelope.persistentModelID
		let mine = expenses
			.filter { $0.envelope?.persistentModelID == envelopeID }
			.sorted { $0.date < $1.date }

		var periods: [Period] = []
		var carriedIn: Decimal = 0

		for (index, start) in fundingDates.enumerated() {
			let end = index + 1 < fundingDates.count ? fundingDates[index + 1] : range.upperBound
			let inPeriod = mine.filter { $0.date >= start && $0.date < end }
			let spent = inPeriod.reduce(Decimal(0)) { $0 + $1.amount }

			let period = Period(
				start: start,
				end: end,
				// what the envelope was funded with *at the time* -- raising a
				// grocery envelope today must not restate last month's budget
				funded: snapshot.amount(effectiveOn: start),
				carriedIn: carriedIn,
				spent: spent,
				expenses: inPeriod
			)
			periods.append(period)

			// roll forward only if asked to, and never roll a deficit forward --
			// an overspend is a fact about the period it happened in
			carriedIn = envelope.carryOver ? max(period.available, 0) : 0
		}

		return periods
	}

	/// the cycle `date` falls into -- the one the UI usually wants
	static func currentPeriod(
		for envelope: Envelope,
		expenses: [Expense],
		asOf date: Date = .now,
		amendments: [AmendmentPoint] = [],
		calendar: Calendar = .current
	) -> Period? {
		// look back far enough to accumulate a sensible carryover chain without
		// walking the entire history of the envelope
		let lookback = calendar.date(byAdding: .year, value: -2, to: date) ?? date
		let lookahead = calendar.date(byAdding: .year, value: 1, to: date) ?? date

		let all = periods(
			for: envelope,
			expenses: expenses,
			in: lookback..<lookahead,
			amendments: amendments,
			calendar: calendar
		)
		return all.last { $0.start <= date } ?? all.first
	}
}
