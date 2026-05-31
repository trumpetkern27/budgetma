import SwiftUI
import Combine

final class ThemeManager: ObservableObject {
	// persistent 
	@AppStorage("fgColourHex") private var fgColourHex: String = "#FFFFFF" {
		didSet {fgColour = Color(hex: fgColourHex) ?? .white}
	}
	@AppStorage("bgColourHex") private var bgColourHex: String = "#000000" {
		didSet {bgColour = Color(hex: bgColourHex) ?? .black}
	}

	@Published var fgColour: Color = .white
	@Published var bgColour: Color = .black

	init() {
		self.fgColour = Color(hex: fgColourHex)
		self.bgColour = Color(hex: bgColourHex)
	}

	func setForeground(_ newValue: Color) {
		fgColour = newValue
		fgColourHex = newValue.toHex() ?? "#FFFFFF"
	}
	func setBackground(_ newValue: Color) {
		bgColour = newValue
		bgColourHex = newValue.toHex() ?? "#000000"
	}
}
