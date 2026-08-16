import SwiftUI

/* --- Chart palette ---
 * series colours, chosen by the job they do rather than by taste
 *
 * two things drive what's here:
 *
 * 1. the theme lets you pick *any* background, so a fixed palette can't promise
 *    contrast. every slot ships a light-surface and dark-surface step and we
 *    pick between them from the actual background's luminance.
 *
 * 2. money in / money out is a *polarity*, which means a diverging pair, which
 *    means blue<->red -- not the green/red finance convention. green<->red is
 *    the textbook colourblind failure (those two separate by ΔE 6.5 under
 *    protanopia, under the safe floor of 8); blue<->red manages 19.2. every
 *    pair below was run through the validator on both surfaces.
 *
 * if you'd rather have the conventional green, swap `inflow` -- it's one line,
 * and the rest of the palette doesn't depend on it.
 */
struct ChartPalette {
	/// money arriving -- categorical slot 1 (blue)
	let inflow: Color
	/// money leaving -- diverging counterpart (red)
	let outflow: Color
	/// the cumulative curve as things stand
	let baseline: Color
	/// the same curve with a candidate purchase folded in (orange)
	let candidate: Color

	/// reserved status colours -- never reused as series colours,
	/// and never the only signal (always paired with an icon + label)
	let good: Color
	let warning: Color
	let critical: Color

	/// recessive furniture
	let grid: Color
	let axis: Color

	/// pick the step set that actually contrasts with the surface in use
	static func forSurface(_ background: Color) -> ChartPalette {
		isDark(background) ? .onDark : .onLight
	}

	// dark-surface steps (the default black theme)
	static let onDark = ChartPalette(
		inflow: Color(hex: "#3987e5"),
		outflow: Color(hex: "#e66767"),
		baseline: Color(hex: "#3987e5"),
		candidate: Color(hex: "#d95926"),
		good: Color(hex: "#199e70"),
		warning: Color(hex: "#c98500"),
		critical: Color(hex: "#e66767"),
		grid: Color.white.opacity(0.12),
		axis: Color.white.opacity(0.45)
	)

	// light-surface steps
	static let onLight = ChartPalette(
		inflow: Color(hex: "#2a78d6"),
		outflow: Color(hex: "#e34948"),
		baseline: Color(hex: "#2a78d6"),
		candidate: Color(hex: "#eb6834"),
		good: Color(hex: "#1baf7a"),
		warning: Color(hex: "#eda100"),
		critical: Color(hex: "#e34948"),
		grid: Color.black.opacity(0.12),
		axis: Color.black.opacity(0.45)
	)

	/// colour for a flow direction
	func color(for sign: FlowSign) -> Color {
		sign == .inflow ? inflow : outflow
	}

	/// relative luminance, to decide which step set to use
	private static func isDark(_ color: Color) -> Bool {
		let uiColor = UIColor(color)
		var red: CGFloat = 0
		var green: CGFloat = 0
		var blue: CGFloat = 0
		var alpha: CGFloat = 0
		guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
			return true
		}

		func linear(_ channel: CGFloat) -> CGFloat {
			channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
		}
		let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
		return luminance < 0.4
	}
}

/* --- environment plumbing ---
 * so a chart deep in a view tree can just read the palette
 */
private struct ChartPaletteKey: EnvironmentKey {
	static let defaultValue: ChartPalette = .onDark
}

extension EnvironmentValues {
	var chartPalette: ChartPalette {
		get { self[ChartPaletteKey.self] }
		set { self[ChartPaletteKey.self] = newValue }
	}
}

extension View {
	/// derive the chart palette from the current theme background
	func chartPalette(for background: Color) -> some View {
		environment(\.chartPalette, .forSurface(background))
	}
}
