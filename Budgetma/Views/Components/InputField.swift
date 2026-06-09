import SwiftUI

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
					.themed()
					.foregroundColor(theme.fgColour.opacity(0.8))
				}

				TextField("", text: $text)
				.themed()
				.tint(theme.fgColour)
				.multilineTextAlignment(.trailing)

			}
			.scrollContentBackground(.hidden)
			.themed()
		}
	}
}

struct InputFieldCurrency: View {
	@EnvironmentObject var theme: ThemeManager

	var field: String
	@Binding var amount: Decimal

	var body: some View {
		HStack {
			Text(field)
			.themed()

			Spacer()

			ZStack(alignment: .trailing) {
				TextField("", value: $amount,
					format: .currency(
						code: Locale.current.currency?.identifier ?? "USD"
						)
					)
					.themed()
					.tint(theme.fgColour)
					.multilineTextAlignment(.trailing)
					.keyboardType(.decimalPad)

			}
			.scrollContentBackground(.hidden)
			.themed()
		}
	}
}
