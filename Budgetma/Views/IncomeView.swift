import SwiftUI
import SwiftData

// main view
struct IncomeView: View {
	@EnvironmentObject var theme: ThemeManager
	@Query private var incomes: [ExpectedIncome]

	@State var expandedCategories: Set<String> = []

	var grouped: [(key: String, category: Category?, incomes: [ExpectedIncome])] {
		let dict = Dictionary(grouping: incomes) {income in
			income.category?.name ?? "__uncategorized__"
		}
		return dict.keys
			.sorted()
			.map { key in
				let items = dict[key]!
				let cat = items.first?.category
				return (key: key, category: cat, incomes: items)
			}
	}

	@Environment(\.modelContext)
	private var context
	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				ForEach(grouped, id: \.key) {group in
					Section {
						if expandedCategories.contains(group.key) {
							ForEach(group.incomes) { income in
								NavigationLink {
									SingleIncomeView(income: income)
								} label: {
									HStack {
										Text(income.name)

										Spacer()

										Text(income.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
									}
								}
							}
						}
					} header: {
						CategoryHeader(
							name: group.category?.name ?? "Uncategorized",
							emoji: group.category?.emoji ?? "🍌",
							total: group.incomes.reduce(0) { $0 + $1.amount },
							isExpanded: expandedCategories.contains(group.key)
						) {
							toggleCategory(group.key)
						}
					}
					.padding()
					.frame(maxWidth: .infinity, alignment: .leading)

					Divider()
					.background(theme.fgColour)
				}
			}

			NavigationLink {
				SingleIncomeView(income: nil)
			} label: {
				Label("New Income", systemImage: "plus")
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)

		}
		.scrollContentBackground(.hidden)
		.themed()

	}

	private func toggleCategory(_ key: String) {
		if expandedCategories.contains(key) {
			expandedCategories.remove(key)
		} else {
			expandedCategories.insert(key)
		}
	}
}


// category header
struct CategoryHeader: View {
	let name: String
	let emoji: String
	let total: Decimal
	let isExpanded: Bool
	let onTap: () -> Void

	var body: some View {
		Button(action: onTap) {
			HStack {
				Text("\(emoji) \(name)")
					.font(.headline)
					.foregroundStyle(.primary)
				Spacer()
				Text(total, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
					.font(.subheadline)
					.foregroundStyle(.secondary)
				Image(systemName: "chevron.right")
					.font(.caption)
					.foregroundStyle(.tertiary)
					.rotationEffect(.degrees(isExpanded ? 90 : 0))
					.animation(.easeInOut(duration: 0.2), value: isExpanded)
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}
}

// view for single income crud
struct SingleIncomeView: View {
	@EnvironmentObject var theme: ThemeManager

	@Environment(\.modelContext)
	private var context

	@Environment(\.dismiss)
	private var dismiss

	@State var income: ExpectedIncome?
	@State private var name: String
	@State private var amount: Decimal
	@State private var startDate: Date
	@State private var regularity: RecurrenceRule?
	@State private var category: Category?

	@Query(
		filter: #Predicate<Category> {
			$0.isActive
		},
		sort: \Category.name
	) private var categories: [Category]

	init(income: ExpectedIncome?) {
		_income = State(initialValue: income)
		_name = State(initialValue: income?.name ?? "")
		_amount = State(initialValue: income?.amount ?? 0)
		_startDate = State(initialValue: income?.startDate ?? Date.now)
		_regularity = State(initialValue: income?.regularity)
		_category = State(initialValue: income?.category)
	}

	var body: some View {

		ScrollView {
			VStack(spacing: 0) {
				InputField(field: "Name", placeholder: "the air", text: $name)
				.padding()

				InputFieldCurrency(field: "Amount", amount: $amount)
				.padding()

				HStack {
					Text("Category")

					Spacer()

					Picker("Category", selection: $category) {
						Text("None").tag(nil as Category?)
						ForEach(categories) { category in
							Text(category.name)
							.tag(category as Category?)
						}
					}
				}
				.padding()

				HStack {
					Text("Regularity")

					Spacer()

					RecurrenceRulePicker(rule: $regularity, startDate: $startDate)
				}

				Spacer()

				HStack {
					Spacer()

					Button(role: .destructive) {
						if let income {
							context.delete(income)
						}
						dismiss()
					} label: {
						Label("", systemImage: "trash")
					}

					Spacer()
				}
			}
			.scrollContentBackground(.hidden)
		}
		.scrollContentBackground(.hidden)
		.themed()
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button("Cancel") {
					dismiss()
				}
			}
			ToolbarItem(placement: .confirmationAction) {
				Button("Save") {
					if let income {
						income.name = name
						income.amount = amount
						income.startDate = startDate
						income.regularity = regularity
						income.category = category
					} else {
						context.insert(
							ExpectedIncome(
								name: name.isEmpty ? "the air" : name,
								amount: amount,
								startDate: startDate,
								regularity: regularity,
								category: category
							)
						)
					}
					do {
						try context.save()
						print("regularity id right after save: \(String(describing: income?.regularity?.persistentModelID))")
					} catch {
						print("SAVE FAILED: \(error)")
					}
					dismiss()
				}
			}
		}


		// }
		// .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		// .scrollContentBackground(.hidden)
		// .themed()
		// .ignoresSafeArea(.keyboard)
		// .onDisappear {
		// 	guard !income.name.isEmpty else { return }
		// 	try? context.save()
		// }
	}
}
