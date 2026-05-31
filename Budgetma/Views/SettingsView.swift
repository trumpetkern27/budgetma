import SwiftUI

struct SettingsView: View {
	@EnvironmentObject var theme: ThemeManager

	var body: some View {
		Form {
			ColorPicker("Font colour", selection: Binding(
				get: { theme.fgColour },
				set: { theme.setForeground($0)}
			))
			.listRowBackground(theme.bgColour) // otherwise white box

			ColorPicker("Background colour", selection: Binding(
				get: { theme.bgColour },
				set: { theme.setBackground($0)}
			))
			.listRowBackground(theme.bgColour)
		}
		.scrollContentBackground(.hidden)
	}
}
