import SwiftUI
import SwiftData

/* --- Transaction base class ---
 * this is whence the other transactions derive
 * these are actual transactions
 */
@available(iOS 26, *)
@Model
class Transaction {
	var name: String
	var date: Date
	var amount: Decimal
	var category: Category?
	var note: String?

	init(
		name: String,
		date: Date,
		amount: Decimal,
		category: Category?,
		note: String?
	) {
		self.name = name
		self.date = date
		self.amount = amount
		self.category = category
		self.note = note
	}
}

/* --- Expense Model ---
 * actual expense
 * can be linked to an envelope / expected expense
 */
@available(iOS 26, *)
@Model
final class Expense: Transaction {
	var expectedExpense: ExpectedExpense?
	var envelope: Envelope?

	init(
		name: String,
		date: Date,
		amount: Decimal,
		category: Category?,
		note: String?,
		expectedExpense: ExpectedExpense?,
		envelope: Envelope
	) {
		self.expectedExpense = expectedExpense
		self.envelope = envelope
		super.init(
			name: name,
			date: date,
			amount: amount,
			category: category,
			note: note
		)
	}
}

/* --- Income Model ---
 * actual income
 */
@available(iOS 26, *)
@Model
final class Income: Transaction {
	var expectedIncome: ExpectedIncome?

	init(
		name: String,
		date: Date,
		amount: Decimal,
		category: Category?,
		note: String?,
		expectedExpense: ExpectedIncome?
	) {
		super.init(
			name: name,
			date: date,
			amount: amount,
			category: category,
			note: note
		)
		self.expectedIncome = expectedIncome
	}
}

/* --- Savings Model ---
 * this puts money into a Goal
 */

