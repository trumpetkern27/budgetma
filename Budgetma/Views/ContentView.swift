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
					VStack {
						Image(systemName: "globe")
							.imageScale(.large)
							.foregroundStyle(.tint)
						Text("Hello, world!")
					}
					.padding()
					.tag("Home")
				case .expenses:
					NavigationStack {
						ExpenseView()
					}
					.tag("Expenses")
				case .income:
					NavigationStack {
						IncomeView()
					}
					.tag("Income")
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
