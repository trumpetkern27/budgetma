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

// default category so that there's always at least one
let defaultCategory = Category(name: "Misc", emoji: "🗿")
