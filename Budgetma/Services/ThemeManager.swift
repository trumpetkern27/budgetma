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
		if !tooClose(col1: newValue, col2: bgColour) {
			fgColour = newValue
			fgColourHex = newValue.toHex() ?? "#FFFFFF"
		}
	}
	func setBackground(_ newValue: Color) {
		if !tooClose(col1: newValue, col2: fgColour) {
			bgColour = newValue
			bgColourHex = newValue.toHex() ?? "#000000"
		}
	}

	func tooClose(col1: Color, col2: Color) -> Bool {

		let uiColor1 = UIColor(col1)
		var red1: CGFloat = 0
		var green1: CGFloat = 0
		var blue1: CGFloat = 0
		var alpha1: CGFloat = 0

		let uiColor2 = UIColor(col2)
		var red2: CGFloat = 0
		var green2: CGFloat = 0
		var blue2: CGFloat = 0
		var alpha2: CGFloat = 0

		uiColor1.getRed(&red1, green: &green1, blue: &blue1, alpha: &alpha1)
		uiColor2.getRed(&red2, green: &green2, blue: &blue2, alpha: &alpha2)

		let distance = pow(red1 - red2, 2) +
			pow(green1 - green2, 2) +
			pow(blue1 - blue2, 2)

		return distance < 0.1

	}

	func applySegmentedControlAppearance() {
		UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(fgColour)
		UISegmentedControl.appearance().backgroundColor = UIColor(bgColour)
		UISegmentedControl.appearance().setTitleTextAttributes(
			[.foregroundColor: UIColor(bgColour)], for: .selected
		)
		UISegmentedControl.appearance().setTitleTextAttributes(
			[.foregroundColor: UIColor(fgColour)], for: .normal
		)

	}
}

struct Themed: ViewModifier {
	@EnvironmentObject var theme: ThemeManager
	func body(content: Content) -> some View {
		content
			.foregroundColor(theme.fgColour)
			.background(theme.bgColour)
			.listRowBackground(theme.bgColour)
			.scrollContentBackground(.hidden)
			.onAppear { theme.applySegmentedControlAppearance() }
			.onChange(of: theme.fgColour) {_, _ in theme.applySegmentedControlAppearance() }
			.onChange(of: theme.bgColour) {_, _ in theme.applySegmentedControlAppearance() }
	}
}

extension View {
	func themed() -> some View { self.modifier(Themed()) }
}
