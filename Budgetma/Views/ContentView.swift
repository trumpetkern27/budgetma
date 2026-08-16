import SwiftUI
import SwiftData

struct ContentView: View {
	@Environment(\.modelContext)
	private var context

	@State private var selected: Tab = .home

    var body: some View {
		VStack {
			Group {
				switch selected {
				case .home:
					NavigationStack {
						HomeView()
					}
					.tag("Home")
				case .budget:
					NavigationStack {
						BudgetView()
					}
					.tag("Budget")
				case .plan:
					NavigationStack {
						PlanView()
					}
					.tag("Plan")
				case .goals:
					NavigationStack {
						GoalsView()
					}
					.tag("Goals")
				case .settings:
					NavigationStack {
						SettingsView()
					}
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			TabBar(selected: $selected)

		}
		.themed()
		.ignoresSafeArea(.keyboard)
		.task {
			#if DEBUG
			SampleData.seedIfRequested(into: context)
			if let requested = SampleData.requestedTab,
			   let tab = Tab.allCases.first(where: { $0.rawValue.lowercased() == requested.lowercased() }) {
				selected = tab
			}
			#endif
			await createDefaultCategoryIfNeeded()
		}
	}

	// create default category misc if needed
	func createDefaultCategoryIfNeeded() async {
		let descriptor = FetchDescriptor<Category>()

		let categories = try? context.fetch(descriptor)

		guard categories?.isEmpty == true else {
			return
		}

		context.insert(Category(name: "Misc", emoji: "🗿"))

		try? context.save()
	}
}

#Preview {
    ContentView()
}
