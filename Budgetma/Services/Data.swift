import SwiftUI
import SwiftData

@Model
final class Transaction {
	var date: Date
	var amount: Double
	var category: Category?
	var note: String

	init(
		date: Date,
		amount: Double,
		category: Category?,
		note: String
	) {
		self.date = date
		self.amount = amount
		self.category = category
		self.note = note
	}
}

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

@Model
final class ExpectedTransaction {
	var name: String
	var category: Category?
	// var regularity: Calendar.RecurrenceRule?

	init(
		name: String,
		category: Category?,
		// regularity: Calendar.RecurrenceRule?
	) {
		self.name = name
		self.category = category
		// self.regularity = regularity
	}
}

let defaultCategory = Category(name: "Misc", emoji: "🗿")
