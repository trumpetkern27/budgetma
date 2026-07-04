import Foundation

enum UpcomingSource {
	case income(ExpectedIncome)
	case expense(ExpectedExpense)
	case envelope(Envelope)
}

struct UpcomingItem: Identifiable {
	let date: Date
	let source: UpcomingSource

	var id: String {
		switch source{
		case .income(let i): return "income-\(i.id)-\(date.timeIntervalSince1970)"
		case .expense(let e): return "expense\(e.id)-\(date.timeIntervalSince1970)"
		case .envelope(let e): return "envelope\(e.id)-\(date.timeIntervalSince1970)"
		}
	}

	var name: String {
		switch source {
		case .income(let i): return i.name
		case .expense(let e): return e.name
		case .envelope(let e): return e.name
		}
	}

	var emoji: String {
		switch source {
		case .income(let i): return i.category?.emoji ?? "💰"
		case .expense(let e): return e.category?.emoji ?? "💸"
		case .envelope(let e): return e.category?.emoji ?? "✉️"
		}
	}

	var amount: Decimal {
		switch source {
		case .income(let i): return i.amount
		case .expense(let e): return e.amount
		case .envelope(let e): return e.amount
		}
	}

	var isIncome: Bool {
		if case .income = source { return true }
		return false
	}
}
