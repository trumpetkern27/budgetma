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
 *
 * picking a slot also *fills the form in*: name, amount, date, category, and the
 * envelope if it's envelope funding. everything stays editable afterwards -- the
 * autofill only ever overwrites a field you haven't touched, or one it filled in
 * itself last time round.
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
	/// open a blank entry already dated -- from tapping a day on the calendar
	var prefillDate: Date?

	@Query(filter: #Predicate<Category> { $0.isActive }, sort: \Category.name)
	private var categories: [Category]
	@Query private var envelopes: [Envelope]
	@Query private var goals: [Goal]

	/// after saving, stay put and clear the form instead of backing out
	@AppStorage("logAddsAnother") private var addsAnother: Bool = true

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
	@State private var showAllSlots = false

	/// what the settles autocomplete last wrote, so we can tell our own values
	/// apart from ones you typed and never clobber yours
	@State private var autofilled = Autofill()
	@State private var userEditedDate = false

	@State private var savedCount = 0
	@State private var flash: String?

	private struct Autofill {
		var name: String?
		var amount: Decimal?
		var category: Category?
		var envelope: Envelope?
		var goal: Goal?
		var date: Date?
	}

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

		/// the entry kind that can actually settle a given scheduled event
		init(settling kind: EventKind) {
			switch kind {
			case .income: self = .income
			case .goalContribution: self = .savings
			case .expense, .envelopeFunding: self = .expense
			}
		}

		/// which scheduled events this entry kind is allowed to settle
		///
		/// matching on FlowSign alone put goal contributions, envelope funding and
		/// ordinary expenses in one undifferentiated pile of outflows
		func settles(_ kind: EventKind) -> Bool {
			switch self {
			case .income: return kind == .income
			case .savings: return kind == .goalContribution
			case .expense: return kind == .expense || kind == .envelopeFunding
			}
		}
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
		.dismissableKeyboard()
		.navigationTitle(editing == nil ? "Log transaction" : "Edit transaction")
		.navigationBarTitleDisplayMode(.inline)
		.overlay(alignment: .top) { flashBanner }
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				// once you've saved something, backing out isn't a cancel any more
				Button(savedCount > 0 ? "Done" : "Cancel") { dismiss() }
			}
			ToolbarItem(placement: .confirmationAction) {
				Button("Save") { save() }
					.disabled(amount <= 0)
			}
		}
		.onAppear(perform: load)
		.onChange(of: date) { _, new in
			// a date we wrote ourselves isn't you editing it
			if new != autofilled.date { userEditedDate = true }
			refreshSlots()
		}
		.onChange(of: kind) { _, _ in refreshSlots() }
		.onChange(of: settles) { _, new in
			guard let new else { return }
			autocomplete(from: new)
		}
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

	/* this was a Picker(.inline), which outside a List renders as a *wheel*: a tall
	 * blank-looking well whose rows draw in the system label colour and vanish
	 * against a custom dark theme, showing only the selection capsule. a list of
	 * plain rows we draw ourselves reads at a glance, honours the theme, and has
	 * room for the date and the exact amount -- which is the whole point of the
	 * control.
	 */
	private var settlesCard: some View {
		Card(
			title: "Settles",
			subtitle: "Pick one and the rest of the form fills itself in"
		) {
			if candidateSlots.isEmpty {
				Text("Nothing scheduled near this date.")
					.font(.caption)
					.foregroundStyle(theme.fgColour.opacity(0.55))
			} else {
				VStack(spacing: 0) {
					settleRow(nil)

					// in date order: these are things happening around now, and a
					// chronology is the only ordering that reads as one
					ForEach(visibleSlots) { slot in
						Divider().background(theme.fgColour.opacity(0.12))
						settleRow(slot)
					}

					if candidateSlots.count > collapsedSlotLimit {
						Divider().background(theme.fgColour.opacity(0.12))
						Button {
							withAnimation(.easeInOut(duration: 0.18)) { showAllSlots.toggle() }
						} label: {
							HStack {
								Text(showAllSlots
									 ? "Show fewer"
									 : "Show all \(candidateSlots.count)")
									.font(.caption)
								Spacer()
								Image(systemName: showAllSlots ? "chevron.up" : "chevron.down")
									.font(.caption2)
							}
							.padding(.vertical, 9)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.foregroundStyle(theme.fgColour.opacity(0.7))
					}
				}
			}
		}
	}

	private let collapsedSlotLimit = 6

	private var visibleSlots: [ScheduledEvent] {
		showAllSlots ? candidateSlots : Array(candidateSlots.prefix(collapsedSlotLimit))
	}

	/// one selectable slot; `nil` is the "this settles nothing" row
	private func settleRow(_ slot: ScheduledEvent?) -> some View {
		let isSelected = settles == slot

		return Button {
			settles = slot
		} label: {
			HStack(spacing: 10) {
				Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
					.font(.system(size: 15))
					.foregroundStyle(isSelected ? theme.fgColour : theme.fgColour.opacity(0.35))

				if let slot {
					Text(slot.emoji)
					VStack(alignment: .leading, spacing: 1) {
						Text(slot.name)
							.font(.subheadline)
							.lineLimit(1)
						Text(slot.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
							.font(.caption2)
							.foregroundStyle(theme.fgColour.opacity(0.5))
					}
					Spacer()
					// exact, not rounded -- you're matching this against a receipt
					Text(slot.amount.money)
						.font(.subheadline)
						.monospacedDigit()
				} else {
					VStack(alignment: .leading, spacing: 1) {
						Text("Unplanned")
							.font(.subheadline)
						Text("Doesn't settle anything you planned")
							.font(.caption2)
							.foregroundStyle(theme.fgColour.opacity(0.5))
					}
					Spacer()
				}
			}
			.padding(.vertical, 9)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
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

	@ViewBuilder
	private var flashBanner: some View {
		if let flash {
			Text(flash)
				.font(.caption.weight(.semibold))
				.padding(.horizontal, 14)
				.padding(.vertical, 7)
				.background(theme.fgColour)
				.foregroundStyle(theme.bgColour)
				.clipShape(Capsule())
				.padding(.top, 6)
				.transition(.move(edge: .top).combined(with: .opacity))
		}
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
			userEditedDate = true
		} else if let prefill {
			name = prefill.name
			amount = prefill.amount
			date = prefill.date
			// a goal contribution is an outflow, but it is *not* an expense --
			// opening it as one is why tapping a scheduled contribution used to
			// land you on the wrong form with no way to settle it
			kind = EntryKind(settling: prefill.kind)
		} else if let prefillDate {
			date = prefillDate
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
			.filter { kind.settles($0.kind) }
			.sorted { $0.date < $1.date }
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

	// MARK: - Autocomplete from the settled slot

	/* fill in what the plan says, without ever overwriting what you said.
	 *
	 * a field is ours to fill when it's still empty, or when it still holds the
	 * value we put there for the previously selected slot -- switching your mind
	 * between two slots re-fills, typing a name and then picking a slot doesn't
	 * throw the name away.
	 */
	private func autocomplete(from slot: ScheduledEvent) {
		let source = slot.sourceID.flatMap { context.model(for: $0) as? ExpectedTransaction }
		let sourceGoal = slot.sourceID.flatMap { context.model(for: $0) as? Goal }

		if name.isEmpty || name == autofilled.name {
			name = slot.name
			autofilled.name = slot.name
		}

		if amount == 0 || amount == autofilled.amount {
			amount = slot.amount
			autofilled.amount = slot.amount
		}

		// the category the plan says this belongs to -- so settling something
		// carries its category through instead of leaving the actual uncategorised
		if let planned = source?.category, category == nil || category == autofilled.category {
			category = planned
			autofilled.category = planned
		}

		// an envelope funding occurrence knows exactly which envelope it funds
		if let fundedEnvelope = source as? Envelope,
		   envelope == nil || envelope == autofilled.envelope {
			envelope = fundedEnvelope
			autofilled.envelope = fundedEnvelope
		}

		// likewise a contribution occurrence knows its goal -- and picking the
		// goal is what makes the contribution settle, so it can't be left to you
		if let sourceGoal, goal == nil || goal == autofilled.goal {
			goal = sourceGoal
			autofilled.goal = sourceGoal
		}

		if !userEditedDate {
			autofilled.date = slot.date
			date = slot.date
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

		/* a goal contribution settles through its *goal*, because a Goal isn't an
		 * ExpectedTransaction and `expected` is typed to that family. the cast
		 * above quietly produced nil for one, which is exactly why settling a
		 * contribution silently did nothing however you logged it.
		 */
		let settledGoal = settles.flatMap { slot -> Goal? in
			guard slot.kind == .goalContribution else { return nil }
			return slot.sourceID.flatMap { context.model(for: $0) as? Goal }
		}
		let finalGoal = settledGoal ?? goal

		if let editing {
			editing.name = finalName
			editing.amount = amount
			editing.date = date
			editing.note = finalNote
			editing.category = category
			editing.expected = expected
			editing.occurrenceDate = occurrenceDate
			if let expense = editing as? Expense { expense.envelope = envelope }
			if let saving = editing as? Savings { saving.goal = finalGoal }
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
					goal: finalGoal,
					expected: expected, occurrenceDate: occurrenceDate
				)
			}
			context.insert(transaction)
		}

		try? context.save()

		// editing is always a one-shot; logging is usually a run of several
		guard editing == nil, addsAnother else {
			dismiss()
			return
		}

		savedCount += 1
		announce("Saved \(finalName)")
		resetForNext()
	}

	/// clear the entry, keep the context you're working in (kind and date)
	private func resetForNext() {
		dismissKeyboard()

		name = ""
		amount = 0
		note = ""
		category = nil
		envelope = nil
		goal = nil
		settles = nil
		autofilled = Autofill()

		refreshSlots()
	}

	private func announce(_ message: String) {
		withAnimation(.easeOut(duration: 0.2)) { flash = message }
		Task {
			try? await Task.sleep(for: .seconds(1.6))
			withAnimation(.easeIn(duration: 0.25)) { flash = nil }
		}
	}
}
