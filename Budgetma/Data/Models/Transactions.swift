import SwiftUI
import SwiftData

/* --- Transaction source ---
 * where an actual came from
 *
 * everything is .manual today. this exists now so that csv import or a bank
 * connection later is a new case + a new ActualsImporter conformance, rather
 * than a migration of every row in the table.
 */
enum TransactionSource: String, Codable, CaseIterable, Sendable {
	case manual
	case csv
	case bank

	var label: String {
		switch self {
		case .manual: return "Manual"
		case .csv: return "Imported"
		case .bank: return "Bank"
		}
	}
}

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
	var category: Category? = nil
	var note: String? = nil

	var expected: ExpectedTransaction? = nil
	var occurrenceDate: Date? = nil

	var sourceRaw: String = TransactionSource.manual.rawValue
	var externalID: String? = nil

	var source: TransactionSource {
		get { TransactionSource(rawValue: sourceRaw) ?? .manual }
		set { sourceRaw = newValue.rawValue }
	}

	init(
		name: String,
		date: Date,
		amount: Decimal,
		category: Category?,
		note: String?,
		expected: ExpectedTransaction? = nil,
		occurrenceDate: Date? = nil,
		source: TransactionSource = .manual,
		externalID: String? = nil
	) {
		self.name = name
		self.date = date
		self.amount = amount
		self.category = category
		self.note = note
		self.expected = expected
		self.occurrenceDate = occurrenceDate
		self.sourceRaw = source.rawValue
		self.externalID = externalID
	}
}

/* --- Expense Model ---
 * actual expense
 * can settle an expected expense, and/or draw down an envelope
 *
 * note `expected` (inherited) and `envelope` are different relationships on
 * purpose: `expected` means "this is the rent payment for march", `envelope`
 * means "this $40 came out of the groceries envelope". an envelope gets spent
 * against many times but funded once per occurrence.
 */
@available(iOS 26, *)
@Model
final class Expense: Transaction {
	var envelope: Envelope?

	init(
		name: String,
		date: Date,
		amount: Decimal,
		category: Category? = nil,
		note: String? = nil,
		expected: ExpectedTransaction? = nil,
		occurrenceDate: Date? = nil,
		envelope: Envelope? = nil,
		source: TransactionSource = .manual,
		externalID: String? = nil
	) {
		self.envelope = envelope
		super.init(
			name: name,
			date: date,
			amount: amount,
			category: category,
			note: note,
			expected: expected,
			occurrenceDate: occurrenceDate,
			source: source,
			externalID: externalID
		)
	}
}

/* --- Income Model ---
 * actual income
 */
@available(iOS 26, *)
@Model
final class Income: Transaction {
	override init(
		name: String,
		date: Date,
		amount: Decimal,
		category: Category? = nil,
		note: String? = nil,
		expected: ExpectedTransaction? = nil,
		occurrenceDate: Date? = nil,
		source: TransactionSource = .manual,
		externalID: String? = nil
	) {
		super.init(
			name: name,
			date: date,
			amount: amount,
			category: category,
			note: note,
			expected: expected,
			occurrenceDate: occurrenceDate,
			source: source,
			externalID: externalID
		)
	}
}

/* --- Savings Model ---
 * this puts money into a Goal
 */
@available(iOS 26, *)
@Model
final class Savings: Transaction {
	var goal: Goal?

	init(
		name: String,
		date: Date,
		amount: Decimal,
		category: Category? = nil,
		note: String? = nil,
		goal: Goal? = nil,
		expected: ExpectedTransaction? = nil,
		occurrenceDate: Date? = nil,
		source: TransactionSource = .manual,
		externalID: String? = nil
	) {
		self.goal = goal
		super.init(
			name: name,
			date: date,
			amount: amount,
			category: category,
			note: note,
			expected: expected,
			occurrenceDate: occurrenceDate,
			source: source,
			externalID: externalID
		)
	}
}
