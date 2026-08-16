import SwiftUI
import UIKit

struct InputField: View {
	@EnvironmentObject var theme: ThemeManager

	var field: String
	var placeholder: String
	@Binding var text: String

	var body: some View {
		HStack {
			Text(field)
			.foregroundColor(theme.fgColour)
			.listRowBackground(theme.bgColour)
			.background(theme.bgColour)

			Spacer()

			ZStack(alignment: .trailing) {
				if text.isEmpty {
					Text(placeholder)
					.foregroundColor(theme.fgColour.opacity(0.4))
				}

				TextField("", text: $text)
				.tint(theme.fgColour)
				.multilineTextAlignment(.trailing)

			}
			.scrollContentBackground(.hidden)
		}
		.themed()
	}
}

/* --- Currency input ---
 * a money field that behaves like a money field
 *
 * the old one bound a TextField straight to a Decimal with .currency format,
 * which meant the entire "$0.00" was real editable text: you had to select and
 * delete it before you could type, and nothing stopped you entering letters.
 *
 * here the symbol is a separate, non-editable label that is always visible, the
 * "0.00" is a placeholder that occupies no text storage, and every keystroke is
 * filtered down to digits plus at most one decimal separator with at most two
 * digits after it. the Decimal binding only ever sees a value it can represent.
 */
struct InputFieldCurrency: View {
	@EnvironmentObject var theme: ThemeManager

	var field: String
	@Binding var amount: Decimal
	/// shown greyed out when nothing has been typed -- visual only
	var placeholder: String = "0.00"

	@State private var text: String = ""
	@FocusState private var focused: Bool

	private var separator: String { Locale.current.decimalSeparator ?? "." }

	var body: some View {
		HStack {
			Text(field)

			Spacer()

			HStack(spacing: 1) {
				// always present, never editable, never in the way of typing
				Text(CurrencySettings.symbol)
					.foregroundStyle(text.isEmpty ? theme.fgColour.opacity(0.4) : theme.fgColour)

				ZStack(alignment: .trailing) {
					if text.isEmpty {
						Text(placeholder)
							.foregroundStyle(theme.fgColour.opacity(0.4))
					}

					TextField("", text: $text)
						.keyboardType(.decimalPad)
						.multilineTextAlignment(.trailing)
						.tint(theme.fgColour)
						.focused($focused)
						.fixedSize()
				}
			}
			// the whole right-hand group is the hit target, not just the glyphs
			.contentShape(Rectangle())
			.onTapGesture { focused = true }
		}
		.themed()
		.onAppear { text = amount.plainDigits }
		.onChange(of: text) { _, new in
			let clean = sanitised(new)
			if clean != new { text = clean }
			amount = Decimal(string: clean.replacingOccurrences(of: separator, with: "."))?.rounded(2) ?? 0
		}
		.onChange(of: amount) { _, new in
			// only reformat when the change came from outside (a prefill, or the
			// settles autocomplete) -- reformatting mid-keystroke fights the user
			if Decimal(string: text.replacingOccurrences(of: separator, with: "."))?.rounded(2) != new.rounded(2) {
				text = new.plainDigits
			}
		}
	}

	/// digits, and at most one separator with at most two digits behind it
	private func sanitised(_ raw: String) -> String {
		var out = ""
		var seenSeparator = false
		var fractionDigits = 0

		for character in raw {
			if character.isNumber {
				if seenSeparator {
					guard fractionDigits < 2 else { continue }
					fractionDigits += 1
				}
				out.append(character)
			} else if String(character) == separator || character == "." || character == "," {
				// accept either mark and normalise: the decimal pad shows the
				// locale's, but a hardware keyboard or paste can produce the other
				guard !seenSeparator else { continue }
				seenSeparator = true
				out.append(separator)
			}
		}

		// "007" is never what anyone meant, but "0.5" is
		while out.count > 1, out.hasPrefix("0"), !out.hasPrefix("0" + separator) {
			out.removeFirst()
		}
		return out
	}
}

/* --- Keyboard dismissal ---
 * a decimal pad has no return key, so without this there is genuinely no way to
 * put the keyboard away except by navigating off the screen
 */
struct DismissableKeyboard: ViewModifier {
	@EnvironmentObject var theme: ThemeManager

	func body(content: Content) -> some View {
		content
			.scrollDismissesKeyboard(.interactively)
			.toolbar {
				ToolbarItemGroup(placement: .keyboard) {
					Spacer()
					Button("Done") { dismissKeyboard() }
						.fontWeight(.semibold)
				}
			}
	}
}

extension View {
	/// a Done button above the keyboard, plus swipe-down-to-dismiss on scroll
	func dismissableKeyboard() -> some View { modifier(DismissableKeyboard()) }
}

func dismissKeyboard() {
	UIApplication.shared.sendAction(
		#selector(UIResponder.resignFirstResponder),
		to: nil,
		from: nil,
		for: nil
	)
}
