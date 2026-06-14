import SwiftUI
import SwiftData

/* --- Expected Transaction base class ---
 * this is whence the other expected transactions derive
 * this allows for better abstraction elsewhere
 * also allows for income to be a transaction as well
 */
@available(iOS 26, *) // needed for whatever reason
@Model
class ExpectedTransaction {
	var amount: Decimal
	var name: String
	var regularity: RecurrenceRule?
	var category: Category?

	init(
		name: String,
		amount: Decimal,
		regularity: RecurrenceRule?,
		category: Category?
	) {
		self.name = name
		self.amount = amount
		self.regularity = regularity
		self.category = category
	}
}

/* --- Expected Income Model ---
 * this is exactly as it sounds
 * has recurrence rule as optional
 */
@available(iOS 26, *)
@Model
final class ExpectedIncome: ExpectedTransaction {
	override init(
		name: String,
		amount: Decimal,
		regularity: RecurrenceRule?,
		category: Category?
	) {
		super.init(
			name: name,
			amount: amount,
			regularity: regularity,
			category: category
		)
	}
}

/* --- Expected Expense Model ---
 * this is exacly as it sounds
 * you can make this whatever category you'd like, a specific thing, whatever
 * a good use for this would be subscriptions
 */
@available(iOS 26, *)
@Model
final class ExpectedExpense: ExpectedTransaction {
	override init(
		name: String,
		amount: Decimal,
		regularity: RecurrenceRule?,
		category: Category?
	) {
		super.init(
			name: name,
			amount: amount,
			regularity: regularity,
			category: category
		)
	}
}

/* --- Envelope Model ---
 * imagine when you get your paycheck,
 * you put your money into literal envelopes
 * these are for certain categories (e.g., grocery, fun money, etc.)
 * then you only have that money to use for those things
 * perhaps you'd like to carry over the money from your last envelope to the next one
 * you can do that if you will
 * personally, i'd use this for the barber;
 * idk when i'll get my next haircut, but it's usually within every ~6wks
 */
@available(iOS 26, *)
@Model
final class Envelope: ExpectedTransaction {
	var carryOver: Bool

	init(
		name: String,
		amount: Decimal,
		regularity: RecurrenceRule?,
		category: Category?,
		carryOver: Bool = false
	) {
		self.carryOver = carryOver
		super.init(
			name: name,
			amount: amount,
			regularity: regularity,
			category: category
		)
	}
}
