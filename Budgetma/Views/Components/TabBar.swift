import SwiftUI
import UIKit

enum Tab: String, CaseIterable {
	case home = "Home"
	case budget = "Budget"
	case plan = "Plan"
	case goals = "Goals"
	case settings = "Settings"

	var icon: String {
		switch self {
			case .home: return "🛖"
			case .budget: return "🧾"
			case .plan: return "📈"
			case .goals: return "🎯"
			case .settings: return "⚙️"
		}
	}
}

struct TabBar: View {
	@Binding var selected: Tab
	@EnvironmentObject var theme: ThemeManager

	var body: some View {
		HStack(spacing: 0) {
			ForEach(Tab.allCases, id: \.self) { tab in
				tabButton(tab)
			}
		}
		.padding(.horizontal, 10)
		.padding(.top, 12)
		.padding(.bottom, 12)
	}

	@ViewBuilder func tabButton(_ tab: Tab) -> some View {
		Button {

			withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
				selected = tab
			}

			let impact = UIImpactFeedbackGenerator(style: .light)
			impact.impactOccurred()

		} label: {
			VStack(spacing: 5) {
				Text(tab.icon)
					.font(.system(size: 14))
					.scaleEffect(selected == tab ? 1.25 : 1.0)
					.opacity(selected == tab ? 1 : 0.75)

				Text(tab.rawValue)
					.font(.system(size: 10))
					.lineLimit(1)
					.minimumScaleFactor(0.8)
					.scaleEffect(selected == tab ? 1.15 : 1.0)
					.opacity(selected == tab ? 1 : 0.75)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 6)
			.padding(.horizontal, 2)
			.overlay {
				if selected == tab {
					RoundedRectangle(cornerRadius: 12)
						.stroke(theme.fgColour, lineWidth: 1)
				}
			}
		}
	}
}
