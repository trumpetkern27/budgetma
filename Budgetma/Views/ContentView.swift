import SwiftUI

struct ContentView: View {
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
						SettingsView()
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			TabBar(selected: $selected)
		}
	}
}

#Preview {
    ContentView()
}
