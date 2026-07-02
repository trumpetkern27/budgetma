# Budgetma — Roadmap to a working v1

Audit of where things stand, what's missing, and how to build the two big
remaining pieces (Home dashboard + Goals) on top of what you already have.
Nothing in the repo was changed to produce this — it's just notes + example
code for you to adapt.

## 1. Where things stand today

**Data models (`Data/Models`, `Data/Assets`)**
- `Category` — done.
- `RecurrenceRule` — done. Wraps the new Foundation `Calendar.RecurrenceRule`
  (converts to/from it via `toRecurranceRule()` / `RecurrenceRule.from(_:)`).
- `ExpectedTransaction` (base) → `ExpectedIncome`, `ExpectedExpense`,
  `Envelope` — done, with CRUD screens.
- `Transaction` (base) → `Expense`, `Income` — models exist, but **there is
  no UI to create an actual `Expense` or `Income`**. Only the "Expected"
  versions and `Envelope`s are createable right now.
- Savings/Goal — **not started**. `Transactions.swift` ends with a dangling
  comment (`/* --- Savings Model --- ... */`) and no class body. No `Goal`
  model exists at all.

**Views**
- `ExpenseView` / `IncomeView` — grouped-by-category CRUD for expected
  expenses, envelopes, and expected income. Working.
- `SettingsView` — theme + category CRUD. Working.
- `ContentView` — home tab is a placeholder (`Image(systemName: "globe")` +
  "Hello, world!"). This is the big remaining piece.
- `Views/Components/CategoryListNav.swift` — a commented-out, unfinished
  attempt to de-duplicate the grouped-list pattern that's copy-pasted
  between `ExpenseView` and `IncomeView`. Not wired up to anything; either
  finish it or delete it (see §6).

**Known small bugs to fix eventually (not urgent, not touched here)**
- `Expense.init` takes a non-optional `envelope: Envelope` parameter, but
  the stored property is `var envelope: Envelope?`. As written you can't
  construct an `Expense` that isn't tied to an envelope, which contradicts
  the model. Loosen the init param to `Envelope?`.

## 2. The one architectural piece everything else depends on

Your `RecurrenceRule` model can produce a `Calendar.RecurrenceRule`, but
nothing ever *asks* it "what dates does this land on?" — and it can't,
because there's no anchor date to project from. `Calendar.RecurrenceRule`
needs a starting `Date` to generate occurrences:

```swift
// Confirmed API (SF-0009 / swift-foundation proposal 0009):
public func recurrences(
    of start: Date,
    in range: Range<Date>? = nil
) -> some (Sequence<Date> & Sendable)
```

It's a **lazy, synchronous** sequence (not async) — safe to call even when
`end == .never`, as long as you bound it with `.prefix(_:)` or the `in:`
range.

Right now `ExpectedTransaction` has no start/anchor date, so there's no
`start` to pass in. That's the first thing to add — everything else (Home
feed, "next haircut in 12 days", Goal contribution schedules) builds on it.

### Add `startDate` to `ExpectedTransaction`

```swift
@available(iOS 26, *)
@Model
class ExpectedTransaction {
	var amount: Decimal
	var name: String
	var startDate: Date          // NEW — the date the recurrence anchors to
	var regularity: RecurrenceRule?
	var category: Category?

	init(
		name: String,
		amount: Decimal,
		startDate: Date = .now,   // give it a default so old data migrates cleanly
		regularity: RecurrenceRule?,
		category: Category?
	) {
		self.name = name
		self.amount = amount
		self.startDate = startDate
		self.regularity = regularity
		self.category = category
	}
}
```

`ExpectedIncome`, `ExpectedExpense`, and `Envelope` just need `startDate`
threaded through their `override init`s to `super.init`. Then add a
`DatePicker("Starts", selection: $transaction.startDate, ...)` next to each
existing `RecurrenceRulePicker` in `NewTransactionView`, `NewIncomeView`,
`NewEnvelopeView`, and the `Single...View` edit screens — same pattern
you're already using for `Category` pickers there.

> SwiftData note: adding a required property to an existing `@Model` is a
> lightweight migration as long as it has a default value (`= .now` above
> covers it). Since you're pre-launch this is low-risk either way.

## 3. `RecurrenceProjector` — the engine the Home page and Goals both use

A tiny, view-independent service. Put it in `Services/`.

```swift
// Services/RecurrenceProjector.swift
import Foundation

enum RecurrenceProjector {
	/// The next date on/after `date` this item is expected to occur.
	static func nextOccurrence(
		startDate: Date,
		regularity: RecurrenceRule?,
		after date: Date = .now
	) -> Date? {
		guard let rule = regularity?.toRecurranceRule() else {
			// one-time item — it only "occurs" once, on its start date
			return startDate >= date ? startDate : nil
		}
		return rule.recurrences(of: startDate).first { $0 >= date }
	}

	/// Every occurrence that falls inside `range`.
	static func occurrences(
		startDate: Date,
		regularity: RecurrenceRule?,
		in range: Range<Date>
	) -> [Date] {
		guard let rule = regularity?.toRecurranceRule() else {
			return range.contains(startDate) ? [startDate] : []
		}
		return Array(rule.recurrences(of: startDate, in: range))
	}
}
```

This is the reason arbitrary intervals "just work" — a haircut every 6
weeks and a paycheck every 2 weeks both flow through the same
`occurrences(in:)` call; nothing in the app needs to know about "months."

## 4. Home page

### 4a. A unified "upcoming item" shape

```swift
// Views/Home/UpcomingItem.swift
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
		switch source {
		case .income(let i): return "income-\(i.id)-\(date.timeIntervalSince1970)"
		case .expense(let e): return "expense-\(e.id)-\(date.timeIntervalSince1970)"
		case .envelope(let e): return "envelope-\(e.id)-\(date.timeIntervalSince1970)"
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
```

(`.id` on `ExpectedIncome` etc. comes free — `@Model` types conform to
`PersistentModel`, which already gives you `Identifiable` via
`persistentModelID`. Same reason your existing `ForEach`s never needed an
explicit `id:`.)

### 4b. `HomeView`

```swift
// Views/HomeView.swift
import SwiftUI
import SwiftData

struct HomeView: View {
	@EnvironmentObject var theme: ThemeManager

	@Query private var expectedIncomes: [ExpectedIncome]
	@Query private var expectedExpenses: [ExpectedExpense]
	@Query private var envelopes: [Envelope]

	@State private var windowDays: Int = 30

	private var windowRange: Range<Date> {
		let start = Calendar.current.startOfDay(for: .now)
		let end = Calendar.current.date(byAdding: .day, value: windowDays, to: start)!
		return start..<end
	}

	private var upcoming: [UpcomingItem] {
		var items: [UpcomingItem] = []

		for income in expectedIncomes {
			items += RecurrenceProjector
				.occurrences(startDate: income.startDate, regularity: income.regularity, in: windowRange)
				.map { UpcomingItem(date: $0, source: .income(income)) }
		}
		for expense in expectedExpenses {
			items += RecurrenceProjector
				.occurrences(startDate: expense.startDate, regularity: expense.regularity, in: windowRange)
				.map { UpcomingItem(date: $0, source: .expense(expense)) }
		}
		for envelope in envelopes {
			items += RecurrenceProjector
				.occurrences(startDate: envelope.startDate, regularity: envelope.regularity, in: windowRange)
				.map { UpcomingItem(date: $0, source: .envelope(envelope)) }
		}

		return items.sorted { $0.date < $1.date }
	}

	private var groupedByDay: [(day: Date, items: [UpcomingItem])] {
		let dict = Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.date) }
		return dict.keys.sorted().map { ($0, dict[$0]!.sorted { $0.date < $1.date }) }
	}

	private var totalIncome: Decimal { upcoming.filter(\.isIncome).reduce(0) { $0 + $1.amount } }
	private var totalExpense: Decimal { upcoming.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount } }

	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				Picker("Window", selection: $windowDays) {
					Text("7 days").tag(7)
					Text("30 days").tag(30)
					Text("90 days").tag(90)
				}
				.pickerStyle(.segmented)
				.padding()

				SummaryCard(totalIncome: totalIncome, totalExpense: totalExpense)
					.padding(.horizontal)
					.padding(.bottom)

				ForEach(groupedByDay, id: \.day) { group in
					Text(group.day, format: .dateTime.weekday(.wide).month().day())
						.font(.headline)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.horizontal)
						.padding(.top)

					ForEach(group.items) { item in
						HStack {
							Text("\(item.emoji)  \(item.name)")
							Spacer()
							Text(item.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
								.foregroundStyle(item.isIncome ? .green : theme.fgColour)
						}
						.padding(.horizontal)
						.padding(.vertical, 6)
					}

					Divider()
				}

				if upcoming.isEmpty {
					Text("Nothing expected in this window.")
						.foregroundStyle(.secondary)
						.padding()
				}
			}
		}
		.scrollContentBackground(.hidden)
		.themed()
	}
}

struct SummaryCard: View {
	let totalIncome: Decimal
	let totalExpense: Decimal

	private var net: Decimal { totalIncome - totalExpense }

	var body: some View {
		VStack(spacing: 8) {
			HStack {
				Text("Expected income")
				Spacer()
				Text(totalIncome, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
					.foregroundStyle(.green)
			}
			HStack {
				Text("Expected expenses")
				Spacer()
				Text(totalExpense, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
			}
			Divider()
			HStack {
				Text("Net").bold()
				Spacer()
				Text(net, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
					.bold()
					.foregroundStyle(net >= 0 ? .green : .red)
			}
		}
		.padding()
		.overlay { RoundedRectangle(cornerRadius: 12).stroke(.secondary, lineWidth: 1) }
	}
}
```

Then in `ContentView.swift`, swap the placeholder:

```swift
case .home:
	NavigationStack {
		HomeView()
	}
	.tag("Home")
```

## 5. Goals

### 5a. Finish the models

Fill in the dangling comment at the bottom of `Transactions.swift` (or a
new `Goal.swift` file, your call) with a real `Goal` model plus a
`Savings` transaction subclass that deposits into it:

```swift
@available(iOS 26, *)
@Model
final class Goal {
	var name: String
	var emoji: String
	var targetAmount: Decimal
	var targetDate: Date?
	var isActive: Bool

	@Relationship(deleteRule: .cascade, inverse: \Savings.goal)
	var contributions: [Savings] = []

	init(
		name: String,
		emoji: String,
		targetAmount: Decimal,
		targetDate: Date? = nil,
		isActive: Bool = true
	) {
		self.name = name
		self.emoji = emoji
		self.targetAmount = targetAmount
		self.targetDate = targetDate
		self.isActive = isActive
	}

	var currentAmount: Decimal {
		contributions.reduce(0) { $0 + $1.amount }
	}

	var progress: Double {
		guard targetAmount > 0 else { return 0 }
		let ratio = currentAmount / targetAmount
		return min(NSDecimalNumber(decimal: ratio).doubleValue, 1.0)
	}
}

@available(iOS 26, *)
@Model
final class Savings: Transaction {
	var goal: Goal?

	init(
		name: String,
		date: Date,
		amount: Decimal,
		category: Category?,
		note: String?,
		goal: Goal?
	) {
		self.goal = goal
		super.init(name: name, date: date, amount: amount, category: category, note: note)
	}
}
```

Register both in `BudgetmaApp.swift`'s `.modelContainer(for: [...])` list
alongside the existing types.

### 5b. `GoalsView` (list + progress) and a detail screen

Mirrors the CRUD pattern you already use in `SettingsView`/`CategoriesView`.

```swift
// Views/GoalsView.swift
import SwiftUI
import SwiftData

struct GoalsView: View {
	@EnvironmentObject var theme: ThemeManager
	@Query(filter: #Predicate<Goal> { $0.isActive }) private var goals: [Goal]

	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				ForEach(goals) { goal in
					NavigationLink {
						GoalDetailView(goal: goal)
					} label: {
						GoalRow(goal: goal)
					}
					.padding()
				}

				NavigationLink {
					NewGoalView()
				} label: {
					Label("New Goal", systemImage: "plus")
				}
				.padding()
			}
		}
		.scrollContentBackground(.hidden)
		.themed()
	}
}

struct GoalRow: View {
	@EnvironmentObject var theme: ThemeManager
	let goal: Goal

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text("\(goal.emoji) \(goal.name)")
				Spacer()
				Text(goal.currentAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
			}
			ProgressView(value: goal.progress)
				.tint(theme.fgColour)
		}
	}
}
```

```swift
struct GoalDetailView: View {
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Bindable var goal: Goal
	@State private var contributionAmount: Decimal = 0

	var body: some View {
		VStack(spacing: 0) {
			InputField(field: "Name", placeholder: "New couch", text: $goal.name)
				.padding()

			InputFieldCurrency(field: "Target amount", amount: $goal.targetAmount)
				.padding()

			ProgressView(value: goal.progress)
				.padding(.horizontal)

			HStack {
				InputFieldCurrency(field: "Add contribution", amount: $contributionAmount)
				Button("Add") {
					context.insert(
						Savings(
							name: "\(goal.name) contribution",
							date: .now,
							amount: contributionAmount,
							category: nil,
							note: nil,
							goal: goal
						)
					)
					contributionAmount = 0
					try? context.save()
				}
			}
			.padding()

			List(goal.contributions.sorted { $0.date > $1.date }) { saving in
				HStack {
					Text(saving.date, format: .dateTime.month().day())
					Spacer()
					Text(saving.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
				}
			}
			.scrollContentBackground(.hidden)

			Button(role: .destructive) {
				context.delete(goal)
				dismiss()
			} label: {
				Label("Delete Goal", systemImage: "trash")
			}
			.padding()
		}
		.themed()
		.onDisappear { try? context.save() }
	}
}
```

`NewGoalView` is the same shape as `NewCategoryView`/`NewEnvelopeView` —
grab `name`, `emoji`, `targetAmount`, optional `targetDate`, insert, save,
dismiss.

### 5c. Add the tab

`Views/Components/TabBar.swift`:

```swift
enum Tab: String, CaseIterable {
	case home = "Home"
	case income = "Income"
	case expenses = "Expenses"
	case goals = "Goals"        // NEW
	case settings = "Settings"

	var icon: String {
		switch self {
			case .home: return "🛖"
			case .income: return "💰"
			case .expenses: return "💸"
			case .goals: return "🎯"     // NEW
			case .settings: return "⚙️"
		}
	}
}
```

...and add `tabButton(.goals)` in `TabBar.body`, plus a matching
`case .goals: NavigationStack { GoalsView() }` arm in `ContentView`'s
switch.

## 6. Cleanup, in rough priority order

1. **`startDate` on `ExpectedTransaction`** (§2) — do this first, nothing
   else in §4 compiles without it.
2. **`RecurrenceProjector`** (§3).
3. **Home page** (§4) — wire into `ContentView`/`TabBar`.
4. **Goal + Savings models**, registered in `BudgetmaApp.swift`'s
   `modelContainer`.
5. **Goals tab/screens** (§5).
6. *(stretch)* **Actual transaction logging.** Right now only "expected"
   items and envelopes are createable — there's no way to log a real
   `Expense` or `Income` in the UI. Worth adding once the above is stable:
   a "Log actual" quick-add, maybe a "mark as paid" swipe action straight
   from the Home upcoming list that creates an `Expense`/`Income` linked
   back to the `expectedExpense`/`expectedIncome` it came from. This is
   also what would let Home show "actual vs. expected" instead of just
   projected numbers.
7. *(stretch)* Fix the `Expense.init(envelope: Envelope)` non-optional
   param (§1).
8. *(stretch)* Finish or delete `Views/Components/CategoryListNav.swift` —
   it's a dead, commented-out attempt to de-duplicate the near-identical
   grouped-list code in `ExpenseView` and `IncomeView`. Not blocking
   anything, just tech debt.

## Reference

- Recurrence rule API: [SF-0009 proposal, swift-foundation](https://github.com/swiftlang/swift-foundation/blob/main/Proposals/0009-calendar-recurrence-rule.md)
