import Foundation

/* --- Formatting helpers ---
 * the currency-code dance was copy-pasted about twenty times across the views;
 * it lives here now
 *
 * money is formatted as symbol + number rather than through .currency(code:),
 * because the symbol is a user setting (Settings > Currency symbol) and not
 * necessarily one the locale knows about. the *number* is still formatted by the
 * locale, so grouping and decimal separators stay correct wherever you are.
 */

nonisolated enum CurrencySettings {
	static let symbolKey = "currencySymbol"

	/// whatever the user chose, falling back to the locale's own symbol
	static var symbol: String {
		let custom = UserDefaults.standard.string(forKey: symbolKey)
		if let custom, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
			return custom
		}
		return Locale.current.currencySymbol ?? "$"
	}

	/// the symbol the locale would have used, for the "reset to default" path
	static var localeSymbol: String { Locale.current.currencySymbol ?? "$" }
}

nonisolated extension Decimal {
	static var currencyCode: String {
		Locale.current.currency?.identifier ?? "USD"
	}

	/// the shared shape: -$1,234.56 -- sign outside the symbol, symbol outside
	/// the digits, digits formatted by the locale
	static func styled(_ value: Decimal, fractionDigits: Int) -> String {
		let magnitude = abs(value)
		let digits = magnitude.formatted(.number.precision(.fractionLength(fractionDigits)))
		return (value < 0 ? "-" : "") + CurrencySettings.symbol + digits
	}

	/// $1,234.56
	var money: String {
		Decimal.styled(self, fractionDigits: 2)
	}

	/// $1,235 -- for dense places like calendar cells
	var moneyRounded: String {
		Decimal.styled(self, fractionDigits: 0)
	}

	/// $1.2k / $3.4M -- for chart axes, where full numbers collide
	var moneyCompact: String {
		let value = NSDecimalNumber(decimal: self).doubleValue
		let magnitude = abs(value)
		let sign = value < 0 ? "-" : ""
		let symbol = CurrencySettings.symbol

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

	/// the editable form: digits only, no symbol and no grouping, so it can go
	/// straight back into a text field without the user having to delete commas
	var plainDigits: String {
		guard self != 0 else { return "" }
		let separator = Locale.current.decimalSeparator ?? "."
		let rounded = NSDecimalNumber(decimal: self)
			.rounding(accordingToBehavior: NSDecimalNumberHandler(
				roundingMode: .plain,
				scale: 2,
				raiseOnExactness: false,
				raiseOnOverflow: false,
				raiseOnUnderflow: false,
				raiseOnDivideByZero: false
			))
			.decimalValue

		// trailing ".00" is noise in an input field, but ".50" is not
		let whole = rounded == rounded.rounded(0)
		let text = whole
			? rounded.formatted(.number.precision(.fractionLength(0)).grouping(.never))
			: rounded.formatted(.number.precision(.fractionLength(2)).grouping(.never))

		return text.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: separator)
	}

	/// round-half-up to `places`, used by plainDigits and the input field
	func rounded(_ places: Int) -> Decimal {
		var source = self
		var result = Decimal()
		NSDecimalRound(&result, &source, places, .plain)
		return result
	}
}

nonisolated extension Double {
	var asDecimal: Decimal {
		Decimal(self)
	}
}
