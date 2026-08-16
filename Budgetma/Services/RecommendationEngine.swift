import Foundation
import SwiftData

/* --- Recommendations ---
 * where the plan and reality have quietly diverged
 *
 * everything else in the app compares one window to its plan. this looks across
 * *many* windows and asks a different question: is the plan itself wrong?
 *
 * the whole design turns on one distinction — a **one-off** miss is noise, a
 * **repeated** one is information. budgeting for £10 and paying £10.20 once
 * means nothing. paying £10.20 six months running means the number is £10.20 and
 * you should change it. so nothing is ever flagged from a single occurrence, and
 * a large one-off is deliberately *less* interesting here than a small
 * consistent one.
 */
@available(iOS 26, *)
nonisolated enum RecommendationEngine {

	// MARK: - Thresholds
	//
	// these are the judgement calls. named, in one place, rather than sprinkled
	// as magic numbers through the detectors.

	/// below this, a difference isn't worth anyone's attention whatever it is
	static let absoluteNoiseFloor: Decimal = 1
	/// ...and below this proportion, likewise. £10 -> £10.20 is 2%.
	static let proportionalNoiseFloor: Decimal = 0.05
	/// how many occurrences must agree before it's a pattern rather than a blip
	static let minimumOccurrences = 3
	/// how much of those occurrences must lean the same way
	static let consistencyThreshold = 0.7
	/// unplanned spending needs at least this many hits to suggest planning it
	static let minimumRepeats = 3

	// MARK: - Output

	enum Kind: String, Sendable {
		/// a scheduled item that consistently costs more or less than planned
		case amountDrift
		/// unplanned spending that keeps recurring and probably wants a schedule
		case unplannedPattern
	}

	enum Severity: Int, Sendable, Comparable {
		case low, medium, high
		static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
	}

	struct Recommendation: Identifiable, Sendable {
		let id: String
		let kind: Kind
		let severity: Severity
		let title: String
		/// what was observed, in plain words
		let detail: String
		/// the concrete change being proposed, if there is one
		let suggestion: String?
		/// the expected item this is about, when it has one
		let sourceID: PersistentIdentifier?
		/// the figure worth adopting -- a new amount, or a typical spend
		let suggestedAmount: Decimal?
		/// how many observations back this up
		let sampleSize: Int
		/// annualised impact, for ordering by what actually matters
		let yearlyImpact: Decimal
	}

	// MARK: - Entry point

	/// everything worth saying, most significant first
	@MainActor
	static func recommendations(
		events: [ScheduledEvent],
		transactions: [Transaction],
		calendar: Calendar = .current
	) -> [Recommendation] {
		let drift = amountDrift(events: events, transactions: transactions, calendar: calendar)
		let patterns = unplannedPatterns(transactions: transactions, calendar: calendar)

		return (drift + patterns).sorted {
			if $0.severity != $1.severity { return $0.severity > $1.severity }
			return $0.yearlyImpact > $1.yearlyImpact
		}
	}

	// MARK: - Detector 1: this costs more than you think

	/* pair every settled occurrence with what it actually cost, group by the
	 * expected item, and look for a consistent lean.
	 *
	 * "consistent" is doing the work: we require several occurrences, most of
	 * them off in the *same direction*, and a typical difference above the noise
	 * floor. an item that's £5 over once and £5 under the next time averages to
	 * nothing and is correctly ignored.
	 */
	@MainActor
	private static func amountDrift(
		events: [ScheduledEvent],
		transactions: [Transaction],
		calendar: Calendar
	) -> [Recommendation] {
		// only settled occurrences tell us anything about real cost
		var observations: [PersistentIdentifier: [Observation]] = [:]

		let bySlot = settledIndex(transactions: transactions, calendar: calendar)

		for event in events {
			guard let sourceID = event.sourceID, event.date <= .now else { continue }
			// envelopes are spent against many times; "what it cost" isn't a
			// question a single funding occurrence can answer
			guard event.kind != .envelopeFunding else { continue }

			let slot = OccurrenceSlot(sourceID: sourceID, occurrenceDate: event.occurrenceDate, calendar: calendar)
			guard let matched = bySlot[slot], !matched.isEmpty else { continue }

			let actual = matched.reduce(Decimal(0)) { $0 + $1.amount }
			observations[sourceID, default: []].append(
				Observation(
					name: event.name,
					emoji: event.emoji,
					kind: event.kind,
					date: event.date,
					expected: event.amount,
					actual: actual
				)
			)
		}

		return observations.compactMap { sourceID, sample in
			guard sample.count >= minimumOccurrences else { return nil }

			let differences = sample.map { $0.actual - $0.expected }
			let significant = zip(sample, differences).filter { isSignificant($1, against: $0.expected) }

			// most of the sample has to be meaningfully off, not just one outlier
			let hitRate = Double(significant.count) / Double(sample.count)
			guard hitRate >= consistencyThreshold else { return nil }

			// ...and leaning the same way. over one month and under the next is
			// volatility, not a wrong number.
			let overs = significant.filter { $0.1 > 0 }.count
			let unders = significant.count - overs
			let leaning = Double(max(overs, unders)) / Double(significant.count)
			guard leaning >= consistencyThreshold else { return nil }

			let typicalActual = median(sample.map(\.actual))
			let planned = sample.last?.expected ?? 0
			let difference = typicalActual - planned
			guard isSignificant(difference, against: planned) else { return nil }

			let item = sample[0]
			let isOver = difference > 0
			// for income, coming in *under* plan is the bad direction
			let isBadNews = item.kind == .income ? !isOver : isOver

			let perYear = annualise(abs(difference), sample: sample, calendar: calendar)

			return Recommendation(
				id: "drift-\(sourceID.hashValue)",
				kind: .amountDrift,
				severity: severity(forYearly: perYear, consistency: hitRate, isBadNews: isBadNews),
				title: "\(item.emoji) \(item.name) is consistently \(isOver ? "more" : "less") than planned",
				detail: "\(sample.count) of the last \(sample.count) came in "
					+ "\(isOver ? "over" : "under") by about \(abs(difference).money). "
					+ "You've budgeted \(planned.money); it's really \(typicalActual.money).",
				suggestion: "Change it to \(typicalActual.money) from today",
				sourceID: sourceID,
				suggestedAmount: typicalActual,
				sampleSize: sample.count,
				yearlyImpact: perYear
			)
		}
	}

	// MARK: - Detector 2: this keeps happening, plan for it

	/* unplanned transactions that look like the same thing over and over.
	 *
	 * grouped by normalised name, because that's the signal people actually
	 * generate — the same shop, the same subscription. we then check the spacing
	 * is regular enough to be worth a recurrence rule, and report the interval we
	 * found so the suggestion is concrete rather than "you spend a lot here".
	 */
	@MainActor
	private static func unplannedPatterns(
		transactions: [Transaction],
		calendar: Calendar
	) -> [Recommendation] {
		let unplanned = transactions.filter {
			$0.expected == nil && ($0 as? Savings)?.goal == nil
		}

		let grouped = Dictionary(grouping: unplanned) { normalise($0.name) }

		return grouped.compactMap { key, group -> Recommendation? in
			guard key.count > 2, group.count >= minimumRepeats else { return nil }

			let sorted = group.sorted { $0.date < $1.date }
			let amounts = sorted.map(\.amount)
			let typical = median(amounts)
			let total = amounts.reduce(Decimal(0), +)

			// gaps between sightings, in days
			let gaps = zip(sorted, sorted.dropFirst()).map {
				calendar.dateComponents([.day], from: $0.date, to: $1.date).day ?? 0
			}
			guard !gaps.isEmpty else { return nil }

			let averageGap = gaps.reduce(0, +) / gaps.count
			guard averageGap >= 1 else { return nil }

			// regular enough to be worth a rule? spacing within ~40% of the mean
			let spread = gaps.map { abs(Double($0 - averageGap)) / Double(max(averageGap, 1)) }
			let isRegular = (spread.reduce(0, +) / Double(spread.count)) <= 0.4

			let name = sorted.last?.name ?? key
			let emoji = sorted.last?.category?.emoji ?? "🔁"
			let perYear = typical * Decimal(365 / max(averageGap, 1))

			return Recommendation(
				id: "pattern-\(key)",
				kind: .unplannedPattern,
				severity: severity(forYearly: perYear, consistency: isRegular ? 1 : 0.6, isBadNews: true),
				title: "\(emoji) “\(name)” keeps coming back",
				detail: "\(group.count) unplanned transactions totalling \(total.money), "
					+ (isRegular
						? "about every \(averageGap) day\(averageGap == 1 ? "" : "s")."
						: "with no regular spacing.")
					+ " Typically \(typical.money) each.",
				suggestion: isRegular
					? "Add it as an expected expense of \(typical.money) every \(averageGap) days"
					: "Consider an envelope for this",
				sourceID: nil,
				suggestedAmount: typical,
				sampleSize: group.count,
				yearlyImpact: perYear
			)
		}
	}

	// MARK: - Shared

	private struct Observation {
		let name: String
		let emoji: String
		let kind: EventKind
		let date: Date
		let expected: Decimal
		let actual: Decimal
	}

	@MainActor
	private static func settledIndex(
		transactions: [Transaction],
		calendar: Calendar
	) -> [OccurrenceSlot: [Transaction]] {
		var index: [OccurrenceSlot: [Transaction]] = [:]
		for transaction in transactions {
			let sourceID: PersistentIdentifier?
			if let savings = transaction as? Savings, let goal = savings.goal {
				sourceID = goal.persistentModelID
			} else {
				sourceID = transaction.expected?.persistentModelID
			}
			guard let sourceID else { continue }

			let slotDate = transaction.occurrenceDate ?? transaction.date
			let slot = OccurrenceSlot(sourceID: sourceID, occurrenceDate: slotDate, calendar: calendar)
			index[slot, default: []].append(transaction)
		}
		return index
	}

	/// the noise gate: a difference has to clear *both* an absolute floor and a
	/// proportional one. £0.20 on £10 fails both; £0.20 on £1 fails the absolute.
	static func isSignificant(_ difference: Decimal, against baseline: Decimal) -> Bool {
		let magnitude = abs(difference)
		guard magnitude >= absoluteNoiseFloor else { return false }
		guard baseline > 0 else { return true }
		return magnitude / baseline >= proportionalNoiseFloor
	}

	/// median, not mean: one forgotten annual payment shouldn't drag the
	/// "typical" figure somewhere no individual month ever was
	private static func median(_ values: [Decimal]) -> Decimal {
		guard !values.isEmpty else { return 0 }
		let sorted = values.sorted()
		let middle = sorted.count / 2
		if sorted.count % 2 == 1 { return sorted[middle] }
		return (sorted[middle - 1] + sorted[middle]) / 2
	}

	/// scale a per-occurrence difference up to a year, using the observed spacing
	private static func annualise(
		_ perOccurrence: Decimal,
		sample: [Observation],
		calendar: Calendar
	) -> Decimal {
		let dates = sample.map(\.date).sorted()
		guard let first = dates.first, let last = dates.last, dates.count > 1 else {
			return perOccurrence
		}
		let days = calendar.dateComponents([.day], from: first, to: last).day ?? 0
		guard days > 0 else { return perOccurrence }

		let perYear = Decimal(365 * (dates.count - 1)) / Decimal(days)
		return perOccurrence * perYear
	}

	private static func severity(
		forYearly yearly: Decimal,
		consistency: Double,
		isBadNews: Bool
	) -> Severity {
		// money first: something costing you £600/yr matters more than something
		// costing £6, however neatly it repeats
		if yearly >= 500 && isBadNews { return .high }
		if yearly >= 100 || (consistency >= 0.95 && isBadNews) { return .medium }
		return .low
	}

	/// strip case, punctuation and trailing digits so "Corner Store #4" and
	/// "corner store" are recognised as the same thing
	private static func normalise(_ name: String) -> String {
		name.lowercased()
			.components(separatedBy: CharacterSet.alphanumerics.inverted)
			.filter { !$0.isEmpty && Int($0) == nil }
			.joined(separator: " ")
			.trimmingCharacters(in: .whitespaces)
	}
}
