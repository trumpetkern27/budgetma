import SwiftUI
import SwiftData

// main view
struct IncomeView: View {
	@EnvironmentObject var theme: ThemeManager
	@Query private var incomes: [Income]

	@State var expandedCategories: Set<String> = []

	var grouped: [(key: String, category: Category?, incomes: [Income])] {
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
										.foregroundColor(theme.fgColour)
										.listRowBackground(theme.bgColour)

										Spacer()

										Text(income.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
										.foregroundColor(theme.fgColour)
										.listRowBackground(theme.bgColour)
									}
								}
								.listRowBackground(theme.bgColour)
								.foregroundColor(theme.fgColour)
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
					.foregroundColor(theme.fgColour)
					.listRowBackground(theme.bgColour)
					.frame(maxWidth: .infinity, alignment: .leading)

					Divider()
					.foregroundColor(theme.fgColour)
					.background(theme.fgColour)
				}
			}
			.foregroundColor(theme.fgColour)
			.listRowBackground(theme.bgColour)
			.background(theme.bgColour)

			NavigationLink {
				NewIncomeView()
			} label: {
				Label("New Income", systemImage: "plus")
			}
			.padding()
			.foregroundColor(theme.fgColour)
			.listRowBackground(theme.bgColour)
			.frame(maxWidth: .infinity, alignment: .leading)

		}
		.scrollContentBackground(.hidden)
		.foregroundColor(theme.fgColour)
		.background(theme.bgColour)
		.listRowBackground(theme.bgColour)

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

	@State private var name = ""
	@State private var amount: Decimal = 0

	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				InputField(field: "Name", placeholder: "the air", text: $name)
				.listRowBackground(theme.bgColour)
				.padding()

				Divider()
				.foregroundColor(theme.fgColour)
				.background(theme.fgColour)

				InputFieldCurrency(field: "Amount", amount: $amount)
				.listRowBackground(theme.bgColour)
				.padding()

			}
			.scrollContentBackground(.hidden)
			.background(theme.bgColour)
		}
		.scrollContentBackground(.hidden)
		.background(theme.bgColour)
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
							category: nil
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

	var body: some View {

		VStack(spacing: 0) {
			InputField(field: "Name", placeholder: "the air", text: $income.name)
			.listRowBackground(theme.bgColour)
			.padding()

			InputFieldCurrency(field: "Amount", amount: $income.amount)
			.listRowBackground(theme.bgColour)
			.padding()

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
		.background(theme.bgColour)
		.onDisappear {
			guard !income.name.isEmpty else { return }
			try? context.save()
		}
	}
}
