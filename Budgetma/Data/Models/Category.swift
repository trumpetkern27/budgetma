import SwiftUI
import SwiftData

/* --- Category Model ---
 * this allows for any Transaction to be of a category
 * categories are unique
 * you can choose an emoji to display with it for funsies
 */
@Model
final class Category {
	@Attribute(.unique)
	var id: UUID
	@Attribute(.unique)
	var name: String
	var emoji: String
	var isActive: Bool

	init(
		name: String,
		emoji: String,
		isActive: Bool = true
	) {
		self.id = UUID()
		self.name = name
		self.emoji = emoji
		self.isActive = isActive
	}
}

// note: the "Misc" fallback category is created on first launch by
// ContentView.createDefaultCategoryIfNeeded(), inside the model context.
// there used to be a global `defaultCategory` here, which built a @Model
// instance at process start with no container attached -- unused, and not
// something you want happening at launch.
