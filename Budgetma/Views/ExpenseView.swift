import SwiftUI
import SwiftData

// main view
struct ExpenseView: View {
	@EnvironmentObject var theme: ThemeManager
	@Query private var expectedTransactions: [ExpectedExpense]
	@Query private var envelopes: [Envelope]

	@State var expandedTransactionCategories: Set<String> = []
	@State var expandedEnvelopeCategories: Set<String> = []
	@State private var transactionsExpanded: Bool = false
	@State private var envelopesExpanded: Bool = false

	var groupedTransactions: [(key: String, category: Category?, transactions: [ExpectedExpense])] {
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
								emoji: group.category?.emoji ?? "🍌",
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
											Text("\(transaction.category?.emoji ?? "🍌")  \(transaction.name)")

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
						SingleExpectedTransactionView(transaction: nil)
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
								emoji: group.category?.emoji ?? "🍌",
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
											Text("\(envelope.category?.emoji ?? "🍌")  \(envelope.name)")

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
						SingleEnvelopeView(envelope: nil)
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

// view for single expected transaction crud
struct SingleExpectedTransactionView: View {
	@Environment(\.modelContext)
	private var context

	@Environment(\.dismiss)
	private var dismiss

	@State var transaction: ExpectedExpense?
	@State private var name = ""
	@State private var amount: Decimal
	@State private var startDate: Date
	@State private var category: Category?
	@State private var regularity: RecurrenceRule?
	@Query(
		filter: #Predicate<Category> {
			$0.isActive
		},
		sort: \Category.name
	) private var categories: [Category]

	init(transaction: ExpectedExpense?) {
		_transaction = State(initialValue: transaction)
		_name = State(initialValue: transaction?.name ?? "")
		_amount = State(initialValue: transaction?.amount ?? 0)
		_startDate = State(initialValue: transaction?.startDate ?? Date.now)
		_regularity = State(initialValue: transaction?.regularity)
		_category = State(initialValue: transaction?.category)
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
						if let transaction {
							context.delete(transaction)
						}
						dismiss()
					} label: {
						Label("", systemImage: "trash")
					}

					Spacer()
				}

			}
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
					if let transaction {
						transaction.name = name
						transaction.amount = amount
						transaction.startDate = startDate
						transaction.regularity = regularity
						transaction.category = category
					} else {
						context.insert(
							ExpectedExpense(
								name: name.isEmpty ? "the air" : name,
								amount: amount,
								startDate: startDate,
								regularity: regularity,
								category: category
							)
						)
					}
					try? context.save()
					dismiss()
				}
			}
		}
	}
}

// view for single envelope crud
struct SingleEnvelopeView: View {
	@Environment(\.modelContext)
	private var context

	@Environment(\.dismiss)
	private var dismiss

	@State var envelope: Envelope?
	@State private var name: String
	@State private var amount: Decimal
	@State private var startDate: Date
	@State private var category: Category?
	@State private var carryOver: Bool
	@State private var regularity: RecurrenceRule?

	@Query(
		filter: #Predicate<Category> {
			$0.isActive
		},
		sort: \Category.name
	) private var categories: [Category]

	init(envelope: Envelope?) {
		_envelope = State(initialValue: envelope)
		_name = State(initialValue: envelope?.name ?? "")
		_amount = State(initialValue: envelope?.amount ?? 0)
		_startDate = State(initialValue: envelope?.startDate ?? Date.now)
		_category = State(initialValue: envelope?.category)
		_carryOver = State(initialValue: envelope?.carryOver ?? false)
		// was `initialValue: regularity` -- the property referencing itself, so
		// editing an envelope always opened with its recurrence blanked out
		_regularity = State(initialValue: envelope?.regularity)
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
						if let envelope {
							context.delete(envelope)
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
					if let envelope {
						envelope.name = name
						envelope.amount = amount
						envelope.startDate = startDate
						envelope.regularity = regularity
						envelope.category = category
						envelope.carryOver = carryOver
					} else {
						context.insert(
							Envelope(
								name: name.isEmpty ? "the air" : name,
								amount: amount,
								startDate: startDate,
								// was hardcoded nil -- new envelopes silently
								// dropped whatever recurrence you'd just set
								regularity: regularity,
								category: category,
								carryOver: carryOver
							)
						)
					}
					try? context.save()
					dismiss()
				}
			}
		}
	}
}
