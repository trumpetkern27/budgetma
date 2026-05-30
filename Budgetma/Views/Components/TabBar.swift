import SwiftUI
import UIKit

enum Tab: String, CaseIterable {
	case home = "Home"
	case income = "Income"
	case expenses = "Expenses"
	case settings = "Settings"

	var icon: String {
		switch self {
			case .home: return "🛖"
			case .income: return "💰"
			case .expenses: return "💸"
			case .settings: return "⚙️"
		}
	}
}

struct TabBar: View {
	@Binding var selected: Tab

	var body: some View {
		HStack(spacing: 0) {
			tabButton(.home)
			tabButton(.income)
			tabButton(.expenses)
			tabButton(.settings)
		}
		.padding(.horizontal, 18)
		.padding(.top, 12)
		.padding(.bottom, 12)
		// .background(.ultraThinMaterial)
		// .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
		// .padding(.horizontal, 12)
		// .padding(.bottom, 8)
	}

	@ViewBuilder func tabButton(_ tab: Tab) -> some View {
		Button {

			withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
				selected = tab
			}

			let impact = UIImpactFeedbackGenerator(style: .light)
			impact.impactOccurred()

		} label: {
			VStack(spacing: 6) {
				Text(tab.icon)
					.font(.system(size: 15))
					.scaleEffect(selected == tab ? 1.2 : 1.0)
					.opacity(selected == tab ? 1 : 0.45)

				Text(tab.rawValue)
					.font(.caption)
					.scaleEffect(selected == tab ? 1.2 : 1.0)
					.opacity(selected == tab ? 1 : 0.45)
			}
			.foregroundColor(.primary)
			.frame(maxWidth: .infinity)
			.padding(.top, 6)
		}
	}
}
