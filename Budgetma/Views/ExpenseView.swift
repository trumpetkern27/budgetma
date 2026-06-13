import SwiftUI
import SwiftData

// main view
struct ExpenseView: View {
	@EnvironmentObject var theme: ThemeManager
	@Query private var expectedTransactions: [ExpectedTransaction]
	@Query private var envelopes: [Envelope]

	@State var expandedTransactionCategories: Set<String> = []
	@State var expandedEnvelopeCategories: Set<String> = []
	@State private var transactionsExpanded: Bool = false
	@State private var envelopesExpanded: Bool = false

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
			SectionHeader(
				title: "Expected transactions",
				isExpanded: $transactionsExpanded
			)
			.padding()
			if transactionsExpanded {
				VStack(spacing: 0) {
					ForEach(groupedTransactions, id: \.key) {group in
						VStack {
							CategoryHeader(
								name: group.category?.name ?? "Uncategorized",
								total: group.transactions.reduce(0) { $0 + $1.amount },
								isExpanded: expandedTransactionCategories.contains(group.key)
							) {
								toggleTransactionCategory(group.key)
							}
							if expandedTransactionCategories.contains(group.key) {
								ForEach(group.transactions) { transaction in 
									NavigationLink {
										SingleExpectedTransactionView(transaction: transaction)
									} label: {
										HStack {
											Text(transaction.name)

											Spacer()

											Text(transaction.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
										}
									}
									.padding()
								}
							}
							Divider()
							.background(theme.fgColour)
						}
						.padding()
						.frame(maxWidth: .infinity, alignment: .leading)
					}
					NavigationLink {
						NewTransactionView()
					} label: {
						Label("New Expected Transaction", systemImage: "plus")
					}
					.padding()
				}
			}

			SectionHeader(
				title: "Envelopes",
				isExpanded: $envelopesExpanded
			)
			.padding()
			if envelopesExpanded {
				VStack(spacing: 0) {
					ForEach(groupedEnvelopes, id: \.key) {group in
						VStack {
							CategoryHeader(
								name: group.category?.name ?? "Uncategorized",
								total: group.envelopes.reduce(0) { $0 + $1.amount },
								isExpanded: expandedEnvelopeCategories.contains(group.key)
							) {
								toggleEnvelopeCategory(group.key)
							}
							if expandedEnvelopeCategories.contains(group.key) {
								ForEach(group.envelopes) { envelope in 
									NavigationLink {
										SingleEnvelopeView(envelope: envelope)
									} label: {
										HStack {
											Text(envelope.name)

											Spacer()

											Text(envelope.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
										}
									}
									.padding()
								}
							}
							Divider()
							.background(theme.fgColour)
						}
						.padding()
						.frame(maxWidth: .infinity, alignment: .leading)
					}
					NavigationLink {
						NewEnvelopeView()
					} label: {
						Label("New Envelope", systemImage: "plus")
					}
					.padding()
				}
			}
		}
		.scrollContentBackground(.hidden)
		.themed()

	}

	private func toggleTransactionCategory(_ key: String) {
		if expandedTransactionCategories.contains(key) {
			expandedTransactionCategories.remove(key)
		} else {
			expandedTransactionCategories.insert(key)
		}
	}
	private func toggleEnvelopeCategory(_ key: String) {
		if expandedEnvelopeCategories.contains(key) {
			expandedEnvelopeCategories.remove(key)
		} else {
			expandedEnvelopeCategories.insert(key)
		}
	}
}

struct NewTransactionView: View {
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
						ExpectedTransaction(
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

struct NewEnvelopeView: View {
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
	@State private var carryOver: Bool = false

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

				Toggle("Carry Over", isOn: $carryOver)
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
						Envelope(
							name: name.isEmpty ? "the air" : name,
							amount: amount,
							regularity: nil,
							category: category,
							carryOver: carryOver
						)
					)
					try? context.save()
					dismiss()
				}
			}
		}
	}
}

// view for single expected transaction crud
struct SingleExpectedTransactionView: View {
	@Environment(\.modelContext)
	private var context

	@Environment(\.dismiss)
	private var dismiss

	@State var transaction: ExpectedTransaction
	@Query(
		filter: #Predicate<Category> {
			$0.isActive
		},
		sort: \Category.name
	) private var categories: [Category]

	var body: some View {

		VStack(spacing: 0) {
			InputField(field: "Name", placeholder: "the air", text: $transaction.name)
			.padding()

			InputFieldCurrency(field: "Amount", amount: $transaction.amount)
			.padding()

			HStack {
				Text("Category")

				Spacer()

				Picker("Category", selection: $transaction.category) {
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

				RecurrenceRulePicker(rule: $transaction.regularity)
			}

			Spacer()

			HStack {
				Spacer()

				Button(role: .destructive) {
					context.delete(transaction)
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
			guard !transaction.name.isEmpty else { return }
			try? context.save()
		}
	}
}

// view for single envelope crud
struct SingleEnvelopeView: View {
	@Environment(\.modelContext)
	private var context

	@Environment(\.dismiss)
	private var dismiss

	@State var envelope: Envelope
	@Query(
		filter: #Predicate<Category> {
			$0.isActive
		},
		sort: \Category.name
	) private var categories: [Category]

	var body: some View {

		VStack(spacing: 0) {
			InputField(field: "Name", placeholder: "the air", text: $envelope.name)
			.padding()

			InputFieldCurrency(field: "Amount", amount: $envelope.amount)
			.padding()

			HStack {
				Text("Category")

				Spacer()

				Picker("Category", selection: $envelope.category) {
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

				RecurrenceRulePicker(rule: $envelope.regularity)
			}

			Spacer()

			HStack {
				Spacer()

				Button(role: .destructive) {
					context.delete(envelope)
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
			guard !envelope.name.isEmpty else { return }
			try? context.save()
		}
	}
}

struct SectionHeader: View {
	let title: String
	@Binding var isExpanded: Bool

	var body: some View {
		Button(action: onTap) {
			HStack {
				Text(title)
					.font(.headline)
					.foregroundStyle(.primary)
				Spacer()
				Image(systemName: "chevron.right")
					.font(.caption)
					.foregroundStyle(.tertiary)
					.rotationEffect(.degrees(isExpanded ? 90 : 0))
					.animation(.easeInOut(duration: 0.2), value: isExpanded)
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.themed()
	}

	private func onTap() {
		isExpanded = !isExpanded
	}
}
