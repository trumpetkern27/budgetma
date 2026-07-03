import SwiftUI

struct DatePill: View {
	@EnvironmentObject var theme: ThemeManager
	let label: String
	@Binding var date: Date
	@State private var visible = false

	var body: some View {
		HStack {
			Text(label)

			Spacer()

			Button {
				visible = true
			} label: {
				Text(date.formatted(date: .abbreviated, time: .omitted))
					.foregroundColor(theme.fgColour)
					.padding(.horizontal, 12)
					.padding(.vertical, 6)
					.background(theme.bgColour)
					.clipShape(Capsule())
					.overlay(Capsule().stroke(theme.fgColour, lineWidth: 1))
			}
			.sheet(isPresented: $visible) {
				DatePicker(label, selection: $date, displayedComponents: .date)
					.datePickerStyle(.graphical)
					.tint(theme.fgColour)
					.padding()
					.presentationDetents([.medium])
					.presentationDragIndicator(.visible)
			}
		}
		.themed()
	}
}
