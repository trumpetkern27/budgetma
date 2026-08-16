import SwiftUI
import SwiftData

/* --- Log an actual ---
 * where real transactions get entered by hand
 *
 * the interesting part is "settles": an actual can point at a scheduled
 * occurrence, which is what turns two separate lists into an expected-vs-actual
 * comparison. we pre-select the most likely slot using exactly the same
 * ActualMatcher a csv import would use -- manual entry and automated ingestion
 * take the same path, so they can't drift apart.
 */
@available(iOS 26, *)
struct LogTransactionView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss

	/// when opened from an upcoming item, everything arrives pre-filled
	var prefill: ScheduledEvent?
	/// the item being edited, when this is an edit rather than a new entry
	var editing: Transaction?

	@Query(filter: #Predicate<Category> { $0.isActive }, sort: \Category.name)
	private var categories: [Category]
	@Query private var envelopes: [Envelope]
	@Query private var goals: [Goal]

	@State private var kind: EntryKind = .expense
	@State private var name: String = ""
	@State private var amount: Decimal = 0
	@State private var date: Date = .now
	@State private var note: String = ""
	@State private var category: Category?
	@State private var envelope: Envelope?
	@State private var goal: Goal?
	@State private var settles: ScheduledEvent?
	@State private var candidateSlots: [ScheduledEvent] = []

	enum EntryKind: String, CaseIterable, Identifiable {
		case expense, income, savings
		var id: String { rawValue }
		var label: String {
			switch self {
			case .expense: return "Expense"
			case .income: return "Income"
			case .savings: return "Savings"
			}
		}
		var sign: FlowSign { self == .income ? .inflow : .outflow }
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				kindPicker
				detailsCard
				settlesCard

				if kind == .expense { envelopeCard }
				if kind == .savings { goalCard }

				if editing != nil { deleteButton }
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.navigationTitle(editing == nil ? "Log transaction" : "Edit transaction")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button("Cancel") { dismiss() }
			}
			ToolbarItem(placement: .confirmationAction) {
				Button("Save") { save() }
					.disabled(amount <= 0)
			}
		}
		.onAppear(perform: load)
		.onChange(of: date) { _, _ in refreshSlots() }
		.onChange(of: kind) { _, _ in refreshSlots() }
	}

	// MARK: - Sections

	private var kindPicker: some View {
		Picker("Kind", selection: $kind) {
			ForEach(EntryKind.allCases) { kind in
				Text(kind.label).tag(kind)
			}
		}
		.pickerStyle(.segmented)
		.disabled(editing != nil)
	}

	private var detailsCard: some View {
		Card {
			VStack(spacing: 14) {
				InputField(field: "Name", placeholder: "Groceries", text: $name)
				InputFieldCurrency(field: "Amount", amount: $amount)
				DatePill(label: "Date", date: $date)

				HStack {
					Text("Category")
					Spacer()
					Picker("Category", selection: $category) {
						Text("None").tag(nil as Category?)
						ForEach(categories) { category in
							Text("\(category.emoji) \(category.name)").tag(category as Category?)
						}
					}
					.tint(theme.fgColour)
				}

				InputField(field: "Note", placeholder: "optional", text: $note)
			}
		}
	}

	private var settlesCard: some View {
		Card(
			title: "Settles",
			subtitle: "Link this to something you planned, or leave it unplanned"
		) {
			if candidateSlots.isEmpty {
				Text("Nothing scheduled near this date.")
					.font(.caption)
					.foregroundStyle(theme.fgColour.opacity(0.55))
			} else {
				Picker("Settles", selection: $settles) {
					Text("Unplanned").tag(nil as ScheduledEvent?)
					ForEach(candidateSlots) { slot in
						Text("\(slot.emoji) \(slot.name) · \(slot.date.formatted(.dateTime.month(.abbreviated).day())) · \(slot.amount.moneyRounded)")
							.tag(slot as ScheduledEvent?)
					}
				}
				.pickerStyle(.inline)
				.labelsHidden()
				.tint(theme.fgColour)
			}
		}
	}

	private var envelopeCard: some View {
		Card(
			title: "Envelope",
			subtitle: "Draw this spending down from an envelope"
		) {
			Picker("Envelope", selection: $envelope) {
				Text("None").tag(nil as Envelope?)
				ForEach(envelopes) { envelope in
					Text("\(envelope.category?.emoji ?? "✉️") \(envelope.name)").tag(envelope as Envelope?)
				}
			}
			.pickerStyle(.menu)
			.tint(theme.fgColour)
		}
	}

	private var goalCard: some View {
		Card(title: "Goal") {
			Picker("Goal", selection: $goal) {
				Text("None").tag(nil as Goal?)
				ForEach(goals.filter(\.isActive)) { goal in
					Text("\(goal.emoji) \(goal.name)").tag(goal as Goal?)
				}
			}
			.pickerStyle(.menu)
			.tint(theme.fgColour)
		}
	}

	private var deleteButton: some View {
		Button(role: .destructive) {
			if let editing {
				context.delete(editing)
				try? context.save()
			}
			dismiss()
		} label: {
			Label("Delete", systemImage: "trash")
				.frame(maxWidth: .infinity)
		}
		.padding(.top, 4)
	}

	// MARK: - Loading

	private func load() {
		if let editing {
			name = editing.name
			amount = editing.amount
			date = editing.date
			note = editing.note ?? ""
			category = editing.category
			if let expense = editing as? Expense { envelope = expense.envelope; kind = .expense }
			if editing is Income { kind = .income }
			if let saving = editing as? Savings { goal = saving.goal; kind = .savings }
		} else if let prefill {
			name = prefill.name
			amount = prefill.amount
			date = prefill.date
			kind = prefill.isInflow ? .income : .expense
		}

		refreshSlots()

		// pre-select the slot this most likely settles
		if editing == nil, settles == nil {
			if let prefill {
				settles = candidateSlots.first { $0.id == prefill.id } ?? prefill
			} else {
				suggestMatch()
			}
		}
	}

	/// scheduled occurrences near the entered date, to pick from
	private func refreshSlots() {
		let window = 21.0 * 86_400
		let range = date.addingTimeInterval(-window) ..< date.addingTimeInterval(window)
		let service = BudgetService(context: context)
		candidateSlots = service.events(in: range)
			.filter { $0.sign == kind.sign }
			.sorted { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
	}

	/// the same matcher the import pipeline uses
	private func suggestMatch() {
		guard amount > 0 else { return }
		let matcher = ActualMatcher(events: candidateSlots)
		guard let match = matcher.bestMatch(amount: amount, sign: kind.sign, date: date) else { return }
		settles = candidateSlots.first {
			$0.sourceID == match.sourceID && $0.occurrenceDate == match.occurrenceDate
		}
	}

	// MARK: - Saving

	private func save() {
		let expected = settles?.sourceID.flatMap {
			context.model(for: $0) as? ExpectedTransaction
		}
		let occurrenceDate = settles?.occurrenceDate
		let finalName = name.isEmpty ? (settles?.name ?? kind.label) : name
		let finalNote = note.isEmpty ? nil : note

		if let editing {
			editing.name = finalName
			editing.amount = amount
			editing.date = date
			editing.note = finalNote
			editing.category = category
			editing.expected = expected
			editing.occurrenceDate = occurrenceDate
			if let expense = editing as? Expense { expense.envelope = envelope }
			if let saving = editing as? Savings { saving.goal = goal }
		} else {
			let transaction: Transaction
			switch kind {
			case .expense:
				transaction = Expense(
					name: finalName, date: date, amount: amount,
					category: category, note: finalNote,
					expected: expected, occurrenceDate: occurrenceDate,
					envelope: envelope
				)
			case .income:
				transaction = Income(
					name: finalName, date: date, amount: amount,
					category: category, note: finalNote,
					expected: expected, occurrenceDate: occurrenceDate
				)
			case .savings:
				transaction = Savings(
					name: finalName, date: date, amount: amount,
					category: category, note: finalNote,
					goal: goal,
					expected: expected, occurrenceDate: occurrenceDate
				)
			}
			context.insert(transaction)
		}

		try? context.save()
		dismiss()
	}
}
