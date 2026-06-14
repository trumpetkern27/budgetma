import SwiftUI
import UIKit

extension Color {
	// use hex to convert colour to hex string and set colour to hex string
	init(hex: String) {
		let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

		var int: UInt64 = 0
		Scanner(string: hex).scanHexInt64(&int)

		let red = Double((int >> 16) & 0xff) / 255
		let green = Double((int >> 8) & 0xff) / 255
		let blue = Double(int & 0xff) / 255
		self.init(red: red, green: green, blue: blue)
	}

	// convert color to hex string
	func toHex() -> String? {
		let uiColor = UIColor(self)
		var red: CGFloat = 0
		var green: CGFloat = 0
		var blue: CGFloat = 0
		var alpha: CGFloat = 0

		guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
			return nil
		}

		return String(
			format: "#%02X%02X%02X",
			Int(red * 255),
			Int(green * 255),
			Int(blue * 255)
		)
	}
}
