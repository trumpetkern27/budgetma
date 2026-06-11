import SwiftUI
import SwiftData

// main view
struct ExpenseView: View {
	@EnvironmentObject var theme: ThemeManager
	@Query private var expectedTransactions: [ExpectedTransaction]
	@Query private var envelopes: [Envelope]

	@State var expandedCategories: Set<String> = []

	var groupedTransactions: [(key: String, category: Category?, transactions: [ExpectedTransaction])] {
		let dict = Dictionary(grouping: expectedTransactions) {transaction in 
			transaction.category?.name ?? "__uncategorized__"
		}
		return dict.keys
			.sorted()
			.map { key in
				let items = dict[key]!
				let cat = items.first?.category
				return (key: key, category: cat, transactions: items)
			}
	}

	var groupedEnvelopes: [(key: String, category: Category?, envelopes: [Envelope])] {
		let dict = Dictionary(grouping: envelopes) {envelope in 
			envelope.category?.name ?? "__uncategorized__"
		}
		return dict.keys
			.sorted()
			.map { key in
				let items = dict[key]!
				let cat = items.first?.category
				return (key: key, category: cat, envelopes: items)
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
				NewIncomeView()
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

struct NewIncomeView: View {
	@EnvironmentObject var theme: ThemeManager

	@Environment(\.modelContext)
	private var context

	@Environment(\.dismiss)
	private var dismiss

	@Query(
		filter: #Predicate<Category> {
			$0.isActive
		},
		sort: \Category.name
	) private var categories: [Category]

	@State private var name = ""
	@State private var amount: Decimal = 0
	@State private var category: Category?

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
					context.insert(
						Income(
							name: name.isEmpty ? "the air" : name,
							amount: amount,
							regularity: nil,
							category: category
						)
					)
					try? context.save()
					dismiss()
				}
			}
		}
	}
}


// category header
struct CategoryHeader: View {
	let name: String
	let total: Decimal
	let isExpanded: Bool
	let onTap: () -> Void

	var body: some View {
		Button(action: onTap) {
			HStack {
				Text(name)
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

	@State var income: Income
	@Query(
		filter: #Predicate<Category> {
			$0.isActive
		},
		sort: \Category.name
	) private var categories: [Category]

	var body: some View {

		VStack(spacing: 0) {
			InputField(field: "Name", placeholder: "the air", text: $income.name)
			.padding()

			InputFieldCurrency(field: "Amount", amount: $income.amount)
			.padding()

			HStack {
				Text("Category")

				Spacer()

				Picker("Category", selection: $income.category) {
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

				RecurrenceRulePicker(rule: $income.regularity)
			}

			Spacer()

			HStack {
				Spacer()

				Button(role: .destructive) {
					context.delete(income)
					dismiss()
				} label: {
					Label("", systemImage: "trash")
				}

				Spacer()
			}

		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.scrollContentBackground(.hidden)
		.themed()
		.ignoresSafeArea(.keyboard)
		.onDisappear {
			guard !income.name.isEmpty else { return }
			try? context.save()
		}
	}
}
