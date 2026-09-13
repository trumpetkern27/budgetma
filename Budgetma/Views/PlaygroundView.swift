import SwiftUI
import SwiftData

/* --- Playground ---
 * what if things were different?
 *
 * "Adjust the plan" is the screen for a decision you've already made: it writes
 * amendments, from today, for real. this is the screen for *before* that. turn
 * the rent up, switch the car payment off, drop a hypothetical raise in, and
 * watch the curve move -- and then close it and nothing has happened. that's
 * the whole point: you can be as reckless with this screen as you like.
 *
 * nothing here touches the model context. it runs on the same Sendable value
 * types the affordability check does, which is exactly why a hypothetical is
 * cheap: a ScheduleSnapshot doesn't care whether anything behind it was ever
 * saved.
 *
 * a changed amount becomes an AmendmentPoint from today rather than a rewritten
 * base amount, for the same reason a real edit does -- the past is a fact even
 * inside a simulation, and the two curves have to differ only in the future or
 * the comparison means nothing.
 */
@available(iOS 26, *)
struct PlaygroundView: View {
	@EnvironmentObject var theme: ThemeManager

	@Query private var expectedIncomes: [ExpectedIncome]
	@Query private var expectedExpenses: [ExpectedExpense]
	@Query private var envelopes: [Envelope]
	@Query private var goals: [Goal]
	@Query private var overrides: [OccurrenceOverride]
	@Query private var amendments: [ScheduleAmendment]
	@Query private var suspensions: [ScheduleSuspension]

	@State var horizon: DateWindow

	/// what you've mocked up, keyed by the thing it's mocking
	@State private var tweaks: [PersistentIdentifier: Tweak] = [:]
	/// things that don't exist at all
	@State private var additions: [Addition] = []
	/// the curve is only readable in absolute terms if it starts somewhere real
	@AppStorage("playgroundOpeningBalance") private var openingCash: Double = 0

	@State private var rows: [Row] = []
	@State private var baseline: Projection?
	@State private var altered: Projection?
	@State private var isComputing = false
	@State private var composing: Addition?

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	// MARK: - Model

	/// one mock edit: a different amount, or gone entirely
	struct Tweak: Equatable {
		var amount: Decimal
		var isOff: Bool = false
	}

	/// something you're imagining that has no row in the database
	struct Addition: Identifiable {
		var id = UUID()
		var name: String = ""
		var amount: Decimal = 0
		var kind: EventKind = .expense
		var start: Date = .now
		/// built by RecurrenceRulePicker with persists: false, so this is a live
		/// RecurrenceRule that was never inserted anywhere -- see the picker
		var rule: RecurrenceRule?

		var emoji: String { kind.fallbackEmoji }

		func snapshot() -> ScheduleSnapshot {
			ScheduleSnapshot(
				sourceID: nil,
				name: name.isEmpty ? "Something new" : name,
				emoji: emoji,
				amount: amount,
				start: start,
				rule: rule?.toRecurranceRule(),
				kind: kind
			)
		}

		/// enough of it to notice a change, for the recompute trigger
		var signature: String {
			"\(id)|\(name)|\(amount)|\(kind.rawValue)|\(start.timeIntervalSince1970)"
				+ "|\(rule?.frequencyRaw ?? -1)|\(rule?.interval ?? 0)"
		}
	}

	/// one line in the list: a real commitment, priced over the horizon
	struct Row: Identifiable {
		let id: PersistentIdentifier
		let name: String
		let emoji: String
		let kind: EventKind
		/// what it's worth per occurrence today, before any mock edit
		let currentAmount: Decimal
		let occurrences: Int
		let projected: Decimal

		var isInflow: Bool { kind.sign == .inflow }
	}

	// MARK: - Body

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				intro
				setupCard

				if rows.isEmpty && additions.isEmpty {
					emptyState
				} else {
					outcomeCard
					comparisonCard
					planList
				}

				additionsCard
			}
			.padding()
			.padding(.bottom, 72)
		}
		.scrollContentBackground(.hidden)
		.themed()
		.chartPalette(for: theme.bgColour)
		.dismissableKeyboard()
		.navigationTitle("Playground")
		.navigationBarTitleDisplayMode(.inline)
		.safeAreaInset(edge: .bottom) { changeBar }
		.sheet(item: $composing) { draft in
			NavigationStack {
				AdditionEditor(draft: draft) { saved in
					if let index = additions.firstIndex(where: { $0.id == saved.id }) {
						additions[index] = saved
					} else {
						additions.append(saved)
					}
				}
			}
		}
		.task(id: structureSignature) { rebuildRows() }
		.task(id: scenarioSignature) { await recompute() }
	}

	// MARK: - Sections

	private var intro: some View {
		Text("Change anything here and watch the curve move. Nothing on this screen is saved — close it and your plan is exactly as you left it.")
			.font(.caption)
			.foregroundStyle(theme.fgColour.opacity(0.6))
			.fixedSize(horizontal: false, vertical: true)
	}

	private var setupCard: some View {
		Card(title: "Play it out over") {
			VStack(alignment: .leading, spacing: 14) {
				WindowPicker(
					window: $horizon,
					presets: [
						DateWindow(count: 6, unit: .month),
						DateWindow(count: 1, unit: .year),
						DateWindow(count: 2, unit: .year),
						DateWindow(count: 5, unit: .year)
					]
				)

				Divider().background(theme.fgColour.opacity(0.2))

				InputFieldCurrency(
					field: "Starting cash",
					amount: Binding(
						get: { Decimal(openingCash) },
						set: { openingCash = $0.doubleValue }
					)
				)

				Text("Roughly what's in the bank today. The curve starts here, so \"lowest point\" means something.")
					.font(.caption2)
					.foregroundStyle(theme.fgColour.opacity(0.55))
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}

	private var emptyState: some View {
		Card(title: "Nothing to play with yet") {
			Text("Add some expected income and expenses, or invent something below, and this becomes a picture of what would happen.")
				.font(.callout)
				.foregroundStyle(theme.fgColour.opacity(0.7))
		}
	}

	/* the four numbers that answer "how would i fare", each against what it is
	 * now. a projection you can't compare to anything is just a shape.
	 */
	@ViewBuilder
	private var outcomeCard: some View {
		if let altered, let baseline {
			Card(title: "How you'd fare", subtitle: "Over \(horizon.label), against your plan as it stands") {
				VStack(spacing: 12) {
					HStack(alignment: .top, spacing: 12) {
						StatTile(
							label: "Ends at",
							value: altered.endingValue.money,
							accent: altered.endingValue >= 0 ? palette.good : palette.critical,
							caption: comparisonCaption(altered.endingValue, was: baseline.endingValue),
							systemImage: altered.endingValue >= baseline.endingValue
								? "arrow.up.right"
								: "arrow.down.right"
						)
						StatTile(
							label: "Lowest point",
							value: (altered.trough?.cumulative ?? altered.startingValue).money,
							accent: (altered.trough?.cumulative ?? 0) < 0 ? palette.critical : theme.fgColour,
							caption: altered.trough.map {
								$0.start.formatted(.dateTime.month(.abbreviated).year())
							} ?? "—"
						)
					}

					HStack(alignment: .top, spacing: 12) {
						StatTile(
							label: "Coming in",
							value: altered.totalInflow.moneyCompact,
							accent: palette.inflow,
							caption: comparisonCaption(altered.totalInflow, was: baseline.totalInflow)
						)
						StatTile(
							label: "Going out",
							value: altered.totalOutflow.moneyCompact,
							accent: palette.outflow,
							caption: comparisonCaption(altered.totalOutflow, was: baseline.totalOutflow)
						)
					}
				}
			}
		}
	}

	@ViewBuilder
	private var comparisonCard: some View {
		Card(
			title: "Running balance",
			subtitle: hasChanges
				? "Your plan, and the same plan with your changes"
				: "Change something below and the second line appears"
		) {
			if let baseline, !baseline.buckets.isEmpty {
				ProjectionChart(
					projection: baseline,
					comparison: hasChanges ? altered : nil,
					comparisonLabel: "What if",
					baselineLabel: "As things stand"
				)
			} else {
				HStack {
					Spacer()
					if isComputing {
						ProgressView().tint(theme.fgColour)
					} else {
						Text("No data in this range.")
							.font(.caption)
							.foregroundStyle(theme.fgColour.opacity(0.5))
					}
					Spacer()
				}
				.frame(height: 220)
			}
		}
	}

	private var planList: some View {
		Card(
			title: "Your plan",
			subtitle: "Retype any amount, or switch something off entirely"
		) {
			VStack(spacing: 0) {
				ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
					if index > 0 {
						Divider().background(theme.fgColour.opacity(0.12))
					}
					planRow(row)
				}
			}
		}
	}

	private func planRow(_ row: Row) -> some View {
		let tweak = tweaks[row.id]
		let isOff = tweak?.isOff ?? false
		let isEdited = isChanged(row)

		return HStack(spacing: 10) {
			Button {
				withAnimation(.easeInOut(duration: 0.18)) { toggleOff(row) }
			} label: {
				Image(systemName: isOff ? "arrow.uturn.backward.circle" : "minus.circle")
					.font(.system(size: 17))
					.foregroundStyle(theme.fgColour.opacity(isOff ? 0.8 : 0.4))
			}
			.buttonStyle(.plain)

			Text(row.emoji)

			VStack(alignment: .leading, spacing: 2) {
				Text(row.name)
					.font(.subheadline)
					.lineLimit(1)
					.strikethrough(isOff, color: theme.fgColour.opacity(0.6))

				Text(isOff
					 ? "Dropped · saves \(row.projected.moneyCompact) over \(horizon.label)"
					 : "\(row.projected.moneyCompact) over \(horizon.label) · \(row.occurrences)×")
					.font(.caption2)
					.foregroundStyle(theme.fgColour.opacity(0.5))
					.lineLimit(1)
			}

			Spacer(minLength: 4)

			if !isOff {
				InlineAmountField(
					amount: Binding(
						get: { tweaks[row.id]?.amount ?? row.currentAmount },
						set: { tweaks[row.id] = Tweak(amount: $0) }
					),
					isEdited: isEdited,
					accent: row.isInflow ? palette.inflow : theme.fgColour
				)
			}
		}
		.padding(.vertical, 10)
		.opacity(isOff ? 0.55 : 1)
	}

	private var additionsCard: some View {
		Card(
			title: "What if you also…",
			subtitle: "Invent income or a cost that doesn't exist yet"
		) {
			VStack(spacing: 0) {
				ForEach(additions) { addition in
					additionRow(addition)
					Divider().background(theme.fgColour.opacity(0.12))
				}

				Button {
					composing = Addition()
				} label: {
					HStack(spacing: 8) {
						Image(systemName: "plus.circle")
							.font(.system(size: 17))
						Text("Add something")
							.font(.subheadline)
						Spacer()
					}
					.padding(.vertical, 10)
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.foregroundStyle(theme.fgColour.opacity(0.75))
			}
		}
	}

	private func additionRow(_ addition: Addition) -> some View {
		HStack(spacing: 10) {
			Button {
				withAnimation(.easeInOut(duration: 0.18)) {
					additions.removeAll { $0.id == addition.id }
				}
			} label: {
				Image(systemName: "xmark.circle")
					.font(.system(size: 17))
					.foregroundStyle(theme.fgColour.opacity(0.4))
			}
			.buttonStyle(.plain)

			Button {
				composing = addition
			} label: {
				HStack(spacing: 8) {
					Text(addition.emoji)
					VStack(alignment: .leading, spacing: 2) {
						Text(addition.name.isEmpty ? "Something new" : addition.name)
							.font(.subheadline)
							.lineLimit(1)
						Text(addition.rule == nil
							 ? "Once, \(addition.start.formatted(.dateTime.month(.abbreviated).day().year()))"
							 : "Repeating from \(addition.start.formatted(.dateTime.month(.abbreviated).day()))")
							.font(.caption2)
							.foregroundStyle(theme.fgColour.opacity(0.5))
							.lineLimit(1)
					}
					Spacer(minLength: 4)
					Text(addition.amount.money)
						.font(.subheadline)
						.monospacedDigit()
						.foregroundStyle(addition.kind.sign == .inflow ? palette.inflow : theme.fgColour)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
		}
		.padding(.vertical, 10)
	}

	/* the bar only exists while you've changed something, and it says the one
	 * thing the rest of the screen can't: how much better or worse off this
	 * version of you is by the end.
	 */
	@ViewBuilder
	private var changeBar: some View {
		if hasChanges {
			HStack(spacing: 12) {
				VStack(alignment: .leading, spacing: 2) {
					Text("\(changeCount) change\(changeCount == 1 ? "" : "s") · not saved")
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.6))
					Text(endingDelta.moneySigned + " by \(horizon.label) from now")
						.font(.callout.weight(.semibold))
						.monospacedDigit()
						.foregroundStyle(endingDelta >= 0 ? palette.good : palette.critical)
				}

				Spacer()

				Button("Reset") {
					withAnimation(.easeInOut(duration: 0.18)) {
						tweaks.removeAll()
						additions.removeAll()
					}
				}
				.font(.caption)
				.foregroundStyle(theme.fgColour.opacity(0.7))
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
			.background(theme.bgColour)
			.overlay(alignment: .top) {
				Rectangle()
					.fill(theme.fgColour.opacity(0.15))
					.frame(height: 1)
			}
		}
	}

	// MARK: - Changes

	private func isChanged(_ row: Row) -> Bool {
		guard let tweak = tweaks[row.id] else { return false }
		return tweak.isOff || tweak.amount != row.currentAmount
	}

	private var changeCount: Int {
		rows.filter(isChanged).count + additions.count
	}

	private var hasChanges: Bool { changeCount > 0 }

	private var endingDelta: Decimal {
		guard let altered, let baseline else { return 0 }
		return altered.endingValue - baseline.endingValue
	}

	private func toggleOff(_ row: Row) {
		var tweak = tweaks[row.id] ?? Tweak(amount: row.currentAmount)
		tweak.isOff.toggle()
		// switching it back on with the original amount is no change at all, and
		// shouldn't leave a phantom entry keeping the change bar alive
		if !tweak.isOff && tweak.amount == row.currentAmount {
			tweaks[row.id] = nil
		} else {
			tweaks[row.id] = tweak
		}
	}

	private func comparisonCaption(_ now: Decimal, was: Decimal) -> String {
		now == was ? "Unchanged" : "was \(was.moneyCompact)"
	}

	// MARK: - Scenario

	private var baseSnapshots: [ScheduleSnapshot] {
		BudgetService.snapshots(
			incomes: expectedIncomes,
			expenses: expectedExpenses,
			envelopes: envelopes,
			goals: goals,
			amendments: amendments,
			suspensions: suspensions
		)
	}

	/// the same plan, with every mock edit folded in
	private func alteredSnapshots() -> [ScheduleSnapshot] {
		let today = Calendar.current.startOfDay(for: .now)

		var out: [ScheduleSnapshot] = baseSnapshots.map { snapshot in
			guard let id = snapshot.sourceID, let tweak = tweaks[id] else { return snapshot }

			var altered = snapshot

			if tweak.isOff {
				/* "what if i just stopped paying this" is an open-ended
				 * suspension from today -- exactly what archiving it for real
				 * would produce, so the simulation and the button agree
				 */
				altered.suspensions.append(SuspensionSpan(from: today, until: nil))
				return altered
			}

			/* an amendment from today rather than a new base amount, so the
			 * occurrences you've already reconciled keep the number they
			 * actually had. any amendment dated today or later is dropped: a
			 * raise you'd scheduled for march must not silently overrule the
			 * figure you just typed in here.
			 */
			var points = altered.amendments.filter { $0.effectiveFrom < today }
			points.append(AmendmentPoint(effectiveFrom: today, amount: tweak.amount))
			altered.amendments = points
			return altered
		}

		out += additions.map { $0.snapshot() }
		return out
	}

	// MARK: - Compute

	/// changes only when the *shape* of the plan does -- the row list is priced
	/// at real amounts, so retyping one doesn't need it rebuilt
	private var structureSignature: String {
		"\(horizon.count)\(horizon.unit.rawValue)|\(expectedIncomes.count)|\(expectedExpenses.count)"
			+ "|\(envelopes.count)|\(goals.count)|\(amendments.count)|\(suspensions.count)"
	}

	private var scenarioSignature: String {
		let edits = tweaks
			.map { "\($0.key.hashValue):\($0.value.amount):\($0.value.isOff)" }
			.sorted()
			.joined(separator: ",")
		let invented = additions.map(\.signature).joined(separator: ",")
		return "\(structureSignature)|\(overrides.count)|\(openingCash)|\(edits)|\(invented)"
	}

	private func rebuildRows() {
		let range = horizon.range()
		let snapshots = baseSnapshots

		// project once and bucket by source, rather than re-projecting per row
		let events = CashflowProjector.events(
			for: snapshots,
			overrides: OverrideIndex(overrides),
			in: range
		)
		let bySource = Dictionary(
			grouping: events.compactMap { event -> (PersistentIdentifier, ScheduledEvent)? in
				guard let id = event.sourceID else { return nil }
				return (id, event)
			},
			by: \.0
		).mapValues { $0.map(\.1) }

		let today = Date.now

		rows = snapshots.compactMap { snapshot in
			guard let id = snapshot.sourceID else { return nil }
			let mine = bySource[id] ?? []
			return Row(
				id: id,
				name: snapshot.name,
				emoji: snapshot.emoji,
				kind: snapshot.kind,
				currentAmount: snapshot.amount(effectiveOn: today),
				occurrences: mine.count,
				projected: mine.reduce(Decimal(0)) { $0 + $1.amount }
			)
		}
		.sorted { $0.projected > $1.projected }

		// a row that vanished (archived elsewhere, deleted) must not keep
		// steering the simulation from a dictionary nobody can see any more
		let live = Set(rows.map(\.id))
		tweaks = tweaks.filter { live.contains($0.key) }
	}

	/// both curves, off the main actor -- snapshots are Sendable precisely so
	/// this hop is legal, and a five-year horizon is real work
	private func recompute() async {
		let base = baseSnapshots
		let scenario = alteredSnapshots()

		guard !base.isEmpty || !scenario.isEmpty else {
			baseline = nil
			altered = nil
			return
		}

		let index = OverrideIndex(overrides)
		let range = horizon.range()
		let opening = Decimal(openingCash)

		isComputing = true
		async let before = CashflowProjector.projectConcurrently(
			for: base, overrides: index, in: range, openingBalance: opening
		)
		async let after = CashflowProjector.projectConcurrently(
			for: scenario, overrides: index, in: range, openingBalance: opening
		)

		baseline = await before
		altered = await after
		isComputing = false
	}
}

/* --- Addition editor ---
 * the sheet for inventing something
 *
 * deliberately the same shape as the affordability input, down to
 * `persists: false` on the recurrence picker: a thing you only ever asked "what
 * if" about must not leave a RecurrenceRule row behind in the database.
 */
@available(iOS 26, *)
private struct AdditionEditor: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.dismiss) private var dismiss

	@State var draft: PlaygroundView.Addition
	@State private var isRecurring: Bool
	var onSave: (PlaygroundView.Addition) -> Void

	init(draft: PlaygroundView.Addition, onSave: @escaping (PlaygroundView.Addition) -> Void) {
		_draft = State(initialValue: draft)
		_isRecurring = State(initialValue: draft.rule != nil)
		self.onSave = onSave
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				Card {
					VStack(spacing: 14) {
						InputField(field: "Name", placeholder: "A raise", text: $draft.name)
						InputFieldCurrency(field: "Amount", amount: $draft.amount)

						Picker("Direction", selection: $draft.kind) {
							Text("Money out").tag(EventKind.expense)
							Text("Money in").tag(EventKind.income)
						}
						.pickerStyle(.segmented)
					}
				}

				Card(title: "When") {
					VStack(alignment: .leading, spacing: 14) {
						Picker("How often", selection: $isRecurring) {
							Text("One time").tag(false)
							Text("Recurring").tag(true)
						}
						.pickerStyle(.segmented)

						if isRecurring {
							// persists: false -- this is hypothetical, and must
							// not leave anything behind when you close the sheet
							RecurrenceRulePicker(
								rule: $draft.rule,
								startDate: $draft.start,
								persists: false
							)
						} else {
							DatePill(label: "When", date: $draft.start)
						}
					}
				}
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.dismissableKeyboard()
		.navigationTitle("What if…")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button("Cancel") { dismiss() }
			}
			ToolbarItem(placement: .confirmationAction) {
				Button("Add") {
					var saved = draft
					// switching back to "one time" has to actually drop the rule,
					// or the sheet saves a schedule you can no longer see
					if !isRecurring { saved.rule = nil }
					onSave(saved)
					dismiss()
				}
				.disabled(draft.amount <= 0)
			}
		}
	}
}
