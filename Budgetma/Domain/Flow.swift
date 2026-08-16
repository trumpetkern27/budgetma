import Foundation

/* --- Flow direction ---
 * every dated money event is either coming in or going out
 * amounts are always stored as positive magnitudes;
 * the sign lives here so nothing downstream has to guess
 */
nonisolated enum FlowSign: String, Codable, Hashable, Sendable {
	case inflow
	case outflow

	var multiplier: Decimal {
		switch self {
		case .inflow: return 1
		case .outflow: return -1
		}
	}
}

/* --- Event kind ---
 * what *sort* of thing produced this event
 * this is presentation + filtering metadata; the maths only cares about FlowSign
 */
nonisolated enum EventKind: String, Codable, Hashable, Sendable {
	case income
	case expense
	case envelopeFunding
	case goalContribution

	var sign: FlowSign {
		switch self {
		case .income: return .inflow
		case .expense, .envelopeFunding, .goalContribution: return .outflow
		}
	}

	var fallbackEmoji: String {
		switch self {
		case .income: return "💰"
		case .expense: return "💸"
		case .envelopeFunding: return "✉️"
		case .goalContribution: return "🎯"
		}
	}
}
