import SwiftUI

struct SettingsView: View {
	@State private var colour = Color.white

	var body: some View {
		Form {
			ColorPicker("Font colour", selection: $colour)
		}
	}

}
