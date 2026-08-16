import SwiftUI

/* --- Card ---
 * the bordered container that was being hand-rolled with .overlay { RoundedRectangle }
 * in about six places
 */
struct Card<Content: View>: View {
	@EnvironmentObject var theme: ThemeManager

	var title: String?
	var subtitle: String?
	@ViewBuilder var content: () -> Content

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			if title != nil || subtitle != nil {
				VStack(alignment: .leading, spacing: 2) {
					if let title {
						Text(title)
							.font(.headline)
					}
					if let subtitle {
						Text(subtitle)
							.font(.caption)
							.foregroundStyle(theme.fgColour.opacity(0.6))
					}
				}
			}
			content()
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(16)
		.overlay {
			RoundedRectangle(cornerRadius: 14)
				.stroke(theme.fgColour.opacity(0.25), lineWidth: 1)
		}
	}
}

/* --- Stat tile ---
 * a single number that deserves to be read before any chart
 * per the form heuristic: when the job is one headline figure, it isn't a chart
 */
struct StatTile: View {
	@EnvironmentObject var theme: ThemeManager

	let label: String
	let value: String
	var accent: Color?
	var caption: String?
	/// paired with the accent so state is never colour-alone
	var systemImage: String?
	/// draws a chevron beside the label, so a tile you can open looks like one
	var showsDisclosure: Bool = false

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 3) {
				Text(label)
					.font(.caption2)
					.textCase(.uppercase)
				if showsDisclosure {
					Image(systemName: "chevron.right")
						.font(.system(size: 8, weight: .semibold))
				}
			}
			.foregroundStyle(theme.fgColour.opacity(0.55))

			HStack(spacing: 5) {
				if let systemImage {
					Image(systemName: systemImage)
						.font(.caption)
						.foregroundStyle(accent ?? theme.fgColour)
				}
				Text(value)
					.font(.title3.weight(.semibold))
					.monospacedDigit()
					.lineLimit(1)
					.minimumScaleFactor(0.6)
					.foregroundStyle(accent ?? theme.fgColour)
			}

			if let caption {
				Text(caption)
					.font(.caption2)
					.foregroundStyle(theme.fgColour.opacity(0.5))
					.lineLimit(2)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

/* --- Window picker ---
 * count + unit, because the app refuses to privilege the month
 */
struct WindowPicker: View {
	@EnvironmentObject var theme: ThemeManager

	@Binding var window: DateWindow
	var presets: [DateWindow] = []

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if !presets.isEmpty {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 8) {
						ForEach(presets, id: \.self) { preset in
							let isSelected = preset.count == window.count && preset.unit == window.unit
							Button {
								window = DateWindow(count: preset.count, unit: preset.unit, anchor: window.anchor)
							} label: {
								Text(preset.label)
									.font(.caption)
									.padding(.horizontal, 12)
									.padding(.vertical, 6)
									.background(isSelected ? theme.fgColour : .clear)
									.foregroundStyle(isSelected ? theme.bgColour : theme.fgColour)
									.clipShape(Capsule())
									.overlay {
										Capsule().stroke(theme.fgColour.opacity(0.4), lineWidth: 1)
									}
							}
							.buttonStyle(.plain)
						}
					}
					.padding(.horizontal, 1)
				}
			}

			HStack(spacing: 12) {
				Stepper(value: $window.count, in: 1...999) {
					Text(window.label)
						.font(.subheadline)
						.monospacedDigit()
				}

				Picker("Unit", selection: $window.unit) {
					ForEach(DateWindow.Unit.allCases) { unit in
						Text(unit.label(count: 2).capitalized).tag(unit)
					}
				}
				.pickerStyle(.menu)
				.tint(theme.fgColour)
			}
		}
	}
}
