import SwiftUI

struct InputField: View {
	@EnvironmentObject var theme: ThemeManager

	var placeholder: String
	@Binding var text: String

	var body: some View {
		ZStack {
			if text.isEmpty {
				Text(placeholder)
					.foregroundColor(theme.fgColour.opacity(0.8))
					.listRowBackground(theme.bgColour)
					.background(theme.bgColour)
			}

			TextField("", text: $text)
				.foregroundColor(theme.fgColour)
				.tint(theme.fgColour)
				.listRowBackground(theme.bgColour)
				.background(theme.bgColour)
		}
		.scrollContentBackground(.hidden)
		.background(theme.bgColour)
	}
}
