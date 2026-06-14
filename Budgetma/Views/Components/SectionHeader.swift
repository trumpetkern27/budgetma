import SwiftUI

struct SectionHeader: View {
	let title: String
	@Binding var isExpanded: Bool

	var body: some View {
		Button(action: onTap) {
			HStack {
				Text(title)
					.font(.headline)
					.foregroundStyle(.primary)
				Spacer()
				Image(systemName: "chevron.right")
					.font(.caption)
					.foregroundStyle(.tertiary)
					.rotationEffect(.degrees(isExpanded ? 90 : 0))
					.animation(.easeInOut(duration: 0.2), value: isExpanded)
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.themed()
	}

	private func onTap() {
		isExpanded = !isExpanded
	}
}
