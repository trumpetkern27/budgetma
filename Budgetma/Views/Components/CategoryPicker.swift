import SwiftUI
import SwiftData

/* --- Category picker ---
 * one labelled row for choosing a category
 *
 * this was hand-rolled in every editor that has a category, and the copies had
 * drifted: some showed the emoji, some didn't, and the ones outside
 * LogTransactionView left the picker on the default style and untinted, which
 * against a custom theme reads as a dead row rather than a control.
 *
 * one component, one look, and the emoji in every label so the thing you pick
 * here looks like the thing you'll see on every other screen.
 */
struct CategoryPicker: View {
	@EnvironmentObject var theme: ThemeManager

	var label: String = "Category"
	@Binding var category: Category?

	@Query(
		filter: #Predicate<Category> { $0.isActive },
		sort: \Category.name
	) private var categories: [Category]

	var body: some View {
		HStack {
			Text(label)

			Spacer()

			Picker(label, selection: $category) {
				Text("None").tag(nil as Category?)
				ForEach(categories) { category in
					Text("\(category.emoji) \(category.name)")
						.tag(category as Category?)
				}
			}
			.pickerStyle(.menu)
			.tint(theme.fgColour)
		}
	}
}
