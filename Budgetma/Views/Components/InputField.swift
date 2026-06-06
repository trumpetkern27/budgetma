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
						.foregroundColor(theme.fgColour.opacity(0.8))
						.listRowBackground(theme.bgColour)
				}

				TextField("", text: $text)
					.foregroundColor(theme.fgColour)
					.tint(theme.fgColour)
					.listRowBackground(theme.bgColour)
					.multilineTextAlignment(.trailing)
			}
			.scrollContentBackground(.hidden)
			.background(theme.bgColour)
		}
	}
}
