import SwiftUI
import SwiftData

struct SettingsView: View {
	@EnvironmentObject var theme: ThemeManager

	var body: some View {
		Form {
			ColorPicker("Font colour", selection: Binding(
				get: { theme.fgColour },
				set: { theme.setForeground($0)}
			))
			.listRowBackground(theme.bgColour)

			ColorPicker("Background colour", selection: Binding(
				get: { theme.bgColour },
				set: { theme.setBackground($0)}
			))
			.listRowBackground(theme.bgColour)

			NavigationLink("Categories") {
				CategoriesView()
			}
			.listRowBackground(theme.bgColour)
		}
		.scrollContentBackground(.hidden)
		.background(theme.bgColour)
	}

}

struct CategoriesView: View {
	@EnvironmentObject var theme: ThemeManager
	@Query(
		filter: #Predicate<Category> {
			$0.isActive
		},
		sort: \Category.name
	)
	private var categories: [Category]
	@Environment(\.modelContext)
	private var context
	var body: some View {
		List {
			ForEach(categories) {category in
				NavigationLink {
					CategoryView(category: category)
				} label: {
					Text("\(category.emoji) \(category.name)")
				}
				.listRowBackground(theme.bgColour)
				.swipeActions {
					Button(role: .destructive) {
						delete(category)
					} label: {
						Label("Delete", systemImage: "trash")
					}
				}
			}
			NavigationLink {
				NewCategoryView()
			} label: {
				Label("New Category", systemImage: "plus")
			}
			.listRowBackground(theme.bgColour)
		}
		.scrollContentBackground(.hidden)
		.background(theme.bgColour)
	}

	private func delete(_ category: Category) {
		var active = try? context.fetch(
			FetchDescriptor<Category>(
				predicate: #Predicate {
					$0.isActive == true
				}
			)
		)

		if active?.count ?? 0 > 1 {
			category.isActive = false
			try? context.save()
		}
	}

}

struct CategoryView: View {
	@EnvironmentObject var theme: ThemeManager
	@Bindable var category: Category
	@Environment(\.modelContext)
	private var context

	var body: some View {
		Form {
			InputField(placeholder: "Name", text: $category.name)
			.listRowBackground(theme.bgColour)
			InputField(placeholder: "Emoji", text: $category.emoji)
			.listRowBackground(theme.bgColour)
		}
		.scrollContentBackground(.hidden)
		.background(theme.bgColour)
		.onDisappear {
			if category.name == "" && category.emoji == "" {
				return
			} else {
				try? context.save()
			}
		}
	}

	init(category: Category) {
		self.category = category
	}
}

struct NewCategoryView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext)
	private var context

	@Environment(\.dismiss)
	private var dismiss

	@State private var name = ""
	@State private var emoji = ""

	var body: some View {
		Form {
			InputField(placeholder: "Name", text: $name)
			.listRowBackground(theme.bgColour)
			InputField(placeholder: "Emoji", text: $emoji)
			.listRowBackground(theme.bgColour)
		}
		.scrollContentBackground(.hidden)
		.background(theme.bgColour)
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button("Cancel") {
					dismiss()
				}
			}
			ToolbarItem(placement: .confirmationAction) {
				Button("Save") {
					let category = Category(
						name: name,
						emoji: emoji
					)

					let existing = try? context.fetch(
						FetchDescriptor<Category>(
							predicate: #Predicate<Category> {
								$0.name == name
							}
						)
					)

					if !(existing?.isEmpty ?? true) {
						existing?.first?.name = name
						existing?.first?.emoji = emoji
						existing?.first?.isActive = true
					} else {
						context.insert(category)
					}
					try? context.save()
					dismiss()
				}
			}
		}
	}
}
