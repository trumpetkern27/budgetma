import SwiftUI
import SwiftData

// main view
struct SettingsView: View {
	@EnvironmentObject var theme: ThemeManager

	var body: some View {
		ScrollView {
			VStack(spacing: 5) {
				ColorPicker("Font colour", selection: Binding(
					get: { theme.fgColour },
					set: { theme.setForeground($0)}
				))
				.padding()
				.listRowBackground(theme.bgColour)

				Divider()
				.foregroundColor(theme.fgColour)
				.background(theme.fgColour)

				ColorPicker("Background colour", selection: Binding(
					get: { theme.bgColour },
					set: { theme.setBackground($0)}
				))
				.padding()
				.listRowBackground(theme.bgColour)

				Divider()
				.foregroundColor(theme.fgColour)
				.background(theme.fgColour)

				NavigationLink("Categories") {
					CategoriesView()
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding()
				.listRowBackground(theme.bgColour)
			}
			.scrollContentBackground(.hidden)
			.background(theme.bgColour)
		}
		.scrollContentBackground(.hidden)
		.background(theme.bgColour)
	}

}

// view for categories
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
		ScrollView {
			VStack(spacing: 0) {
				ForEach(categories) {category in
					VStack(spacing: 0) {
						NavigationLink {
							CategoryView(category: category)
						} label: {
							HStack {
								Text("\(category.emoji) \(category.name)")
								.foregroundColor(theme.fgColour)
								.listRowBackground(theme.bgColour)

								Spacer()

								Button(role: .destructive) {
									delete(category)
								} label: {
									Label("", systemImage: "trash")
								}
							}
						}
						.listRowBackground(theme.bgColour)
						.padding()
						.foregroundColor(theme.fgColour)
						.listRowBackground(theme.bgColour)
						.frame(maxWidth: .infinity, alignment: .leading)
					}
					.foregroundColor(theme.fgColour)
					.listRowBackground(theme.bgColour)
					.background(theme.bgColour)

				}
				NavigationLink {
					NewCategoryView()
				} label: {
					Label("New Category", systemImage: "plus")
				}
				.padding()
				.listRowBackground(theme.bgColour)
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.scrollContentBackground(.hidden)
			.background(theme.bgColour)
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

// view for an individual category
struct CategoryView: View {
	@EnvironmentObject var theme: ThemeManager
	@Bindable var category: Category
	@Environment(\.modelContext)
	private var context

	var body: some View {
		ScrollView {
			VStack {
				InputField(field: "Name", placeholder: "Something", text: $category.name)
				.listRowBackground(theme.bgColour)
				.padding()

				InputField(field: "Emoji", placeholder: "😳", text: $category.emoji)
				.listRowBackground(theme.bgColour)
				.padding()
			}
			.scrollContentBackground(.hidden)
			.background(theme.bgColour)
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

// new category view
struct NewCategoryView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext)
	private var context

	@Environment(\.dismiss)
	private var dismiss

	@State private var name = ""
	@State private var emoji = ""

	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				InputField(field: "Name", placeholder: "Something", text: $name)
				.listRowBackground(theme.bgColour)
				.padding()

				InputField(field: "Emoji", placeholder: "😳", text: $emoji)
				.listRowBackground(theme.bgColour)
				.padding()
			}
			.scrollContentBackground(.hidden)
			.background(theme.bgColour)
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
						name: name.isEmpty ? "Something" : name,
						emoji: emoji.isEmpty ? "😳" : emoji
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
