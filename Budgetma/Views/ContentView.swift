import SwiftUI
import SwiftData

struct ContentView: View {
	@Environment(\.modelContext)
	private var context

	@State private var selected: Tab = .home

    var body: some View {
		ZStack(alignment: .bottom) {
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
						ZStack {
							Image(systemName: "house")
						}
						.padding()
						.tag("Expenses")
					case .income:
						ZStack {
							Image(systemName: "start")
						}
						.padding()
						.tag("Income")
					case .settings:
						NavigationStack{
							SettingsView()
						}
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.safeAreaInset(edge: .bottom) {
				TabBar(selected: $selected)
			}

		}
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
