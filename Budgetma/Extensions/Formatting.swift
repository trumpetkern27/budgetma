import Foundation

/* --- Formatting helpers ---
 * the currency-code dance was copy-pasted about twenty times across the views;
 * it lives here now
 */

nonisolated extension Decimal {
	static var currencyCode: String {
		Locale.current.currency?.identifier ?? "USD"
	}

	/// $1,234.56
	var money: String {
		formatted(.currency(code: Decimal.currencyCode))
	}

	/// $1,235 -- for dense places like calendar cells
	var moneyRounded: String {
		formatted(.currency(code: Decimal.currencyCode).precision(.fractionLength(0)))
	}

	/// $1.2k / $3.4M -- for chart axes, where full numbers collide
	var moneyCompact: String {
		let value = NSDecimalNumber(decimal: self).doubleValue
		let magnitude = abs(value)
		let sign = value < 0 ? "-" : ""
		let symbol = Locale.current.currencySymbol ?? "$"

		switch magnitude {
		case 1_000_000_000...:
			return "\(sign)\(symbol)\((magnitude / 1_000_000_000).formatted(.number.precision(.fractionLength(0...1))))B"
		case 1_000_000...:
			return "\(sign)\(symbol)\((magnitude / 1_000_000).formatted(.number.precision(.fractionLength(0...1))))M"
		case 1_000...:
			return "\(sign)\(symbol)\((magnitude / 1_000).formatted(.number.precision(.fractionLength(0...1))))k"
		default:
			return "\(sign)\(symbol)\(magnitude.formatted(.number.precision(.fractionLength(0))))"
		}
	}

	/// always carries an explicit + or -, for variances
	var moneySigned: String {
		(self > 0 ? "+" : "") + money
	}

	var doubleValue: Double {
		NSDecimalNumber(decimal: self).doubleValue
	}
}

nonisolated extension Double {
	var asDecimal: Decimal {
		Decimal(self)
	}
}
