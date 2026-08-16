import SwiftUI
import SwiftData

/* --- Adjust the plan ---
 * every recurring commitment on one screen, priced by what it actually costs
 * you over the horizon, with the numbers editable in place
 *
 * the per-item editors are fine for "add a subscription". they're useless for
 * the thing people actually do when money is tight: sit down, look at
 * everything at once, and trade one thing off against another — drop a
 * subscription, add £10 to groceries, take £20 off dining out. that's a single
 * decision made across several items, and it needs a single screen.
 *
 * ordering is by projected cost over the horizon rather than by the headline
 * amount, because £15/week quietly outranks £40/month and the sticker price
 * hides that. the running total at the bottom is the whole point: it tells you
 * whether the trade-offs you just made actually add up to enough.
 *
 * nothing is written until you save, and everything written is an *amendment*
 * from today — see ScheduleAmendment for why the past must not move.
 */
@available(iOS 26, *)
struct PlanAdjustView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss

	@Query private var expectedIncomes: [ExpectedIncome]
	@Query private var expectedExpenses: [ExpectedExpense]
	@Query private var envelopes: [Envelope]
	@Query private var goals: [Goal]
	@Query private var overrides: [OccurrenceOverride]
	@Query private var amendments: [ScheduleAmendment]
	@Query private var suspensions: [ScheduleSuspension]

	let horizon: DateWindow

	@State private var rows: [Row] = []
	/// only the ones you've actually touched
	@State private var edits: [PersistentIdentifier: Decimal] = [:]
	@State private var sort: Sort = .projectedCost
	@State private var editing: EditTarget?

	/// a goal's contribution schedule lives on the Goal, not on an
	/// ExpectedTransaction, so the row can point at either
	struct EditTarget: Identifiable {
		let id: PersistentIdentifier
	}
	@State private var confirmingSave = false

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	enum Sort: String, CaseIterable, Identifiable {
		case projectedCost, amount, name, frequency
		var id: String { rawValue }
		var label: String {
			switch self {
			case .projectedCost: return "Cost"
			case .amount: return "Each"
			case .name: return "Name"
			case .frequency: return "Often"
			}
		}
	}

	struct Row: Identifiable {
		let id: PersistentIdentifier
		let name: String
		let emoji: String
		let kind: EventKind
		/// what it's worth per occurrence today
		let currentAmount: Decimal
		/// how many times it lands inside the horizon
		let occurrences: Int
		/// what it costs across the whole horizon at the current amount
		let projected: Decimal
		let isArchived: Bool

		var isInflow: Bool { kind.sign == .inflow }
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				intro
				sortPicker

				if rows.isEmpty {
					Card(title: "Nothing to adjust") {
						Text("Add some expected income or expenses first.")
							.font(.callout)
							.foregroundStyle(theme.fgColour.opacity(0.7))
					}
				} else {
					list
				}
			}
			.padding()
			.padding(.bottom, 80)
		}
		.scrollContentBackground(.hidden)
		.themed()
		.chartPalette(for: theme.bgColour)
		.dismissableKeyboard()
		.navigationTitle("Adjust plan")
		.navigationBarTitleDisplayMode(.inline)
		.safeAreaInset(edge: .bottom) { totalsBar }
		.toolbar {
			ToolbarItem(placement: .confirmationAction) {
				Button("Save") { confirmingSave = true }
					.disabled(changed.isEmpty)
					.fontWeight(.semibold)
			}
		}
		.confirmationDialog(
			"Apply \(changed.count) change\(changed.count == 1 ? "" : "s")?",
			isPresented: $confirmingSave,
			titleVisibility: .visible
		) {
			Button("Apply from today") { save() }
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("Everything you've already logged stays exactly as it is. The new amounts apply from today forward.")
		}
		.sheet(item: $editing) { target in
			NavigationStack { editor(for: target.id) }
		}
		.task(id: signature) { rebuild() }
	}

	// MARK: - Data

	private var signature: String {
		"\(horizon.count)\(horizon.unit.rawValue)|\(expectedIncomes.count)|\(expectedExpenses.count)"
			+ "|\(envelopes.count)|\(goals.count)|\(amendments.count)|\(suspensions.count)"
			+ "|\(sort.rawValue)"
	}

	private func rebuild() {
		let range = horizon.range()
		let snapshots = BudgetService.snapshots(
			incomes: expectedIncomes,
			expenses: expectedExpenses,
			envelopes: envelopes,
			goals: goals,
			amendments: amendments,
			suspensions: suspensions
		)

		// project once and bucket by source, rather than re-projecting per row
		let events = CashflowProjector.events(
			for: snapshots,
			overrides: OverrideIndex(overrides),
			in: range
		)
		let bySource = Dictionary(grouping: events.compactMap { event -> (PersistentIdentifier, ScheduledEvent)? in
			guard let id = event.sourceID else { return nil }
			return (id, event)
		}, by: \.0).mapValues { $0.map(\.1) }

		let today = Date.now
		var built: [Row] = []

		for snapshot in snapshots {
			guard let id = snapshot.sourceID else { continue }
			let mine = bySource[id] ?? []
			let archived = snapshot.isSuspended(on: today)

			built.append(
				Row(
					id: id,
					name: snapshot.name,
					emoji: snapshot.emoji,
					kind: snapshot.kind,
					currentAmount: snapshot.amount(effectiveOn: today),
					occurrences: mine.count,
					projected: mine.reduce(Decimal(0)) { $0 + $1.amount },
					isArchived: archived
				)
			)
		}

		rows = sorted(built)
	}

	private func sorted(_ rows: [Row]) -> [Row] {
		switch sort {
		case .projectedCost: return rows.sorted { $0.projected > $1.projected }
		case .amount: return rows.sorted { $0.currentAmount > $1.currentAmount }
		case .name: return rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
		case .frequency: return rows.sorted { $0.occurrences > $1.occurrences }
		}
	}

	// MARK: - Edits

	private var changed: [Row] {
		rows.filter { row in
			guard let draft = edits[row.id] else { return false }
			return draft != row.currentAmount
		}
	}

	private func draft(for row: Row) -> Decimal {
		edits[row.id] ?? row.currentAmount
	}

	/// what the whole horizon costs after your edits, minus what it costs now
	private var netChange: Decimal {
		changed.reduce(Decimal(0)) { total, row in
			let draft = edits[row.id] ?? row.currentAmount
			let delta = (draft - row.currentAmount) * Decimal(row.occurrences)
			// an inflow going up is money towards you; an outflow going up is away
			return total + (row.isInflow ? delta : -delta)
		}
	}

	private func save() {
		for row in changed {
			guard let amount = edits[row.id] else { continue }

			if let expected = context.model(for: row.id) as? ExpectedTransaction {
				context.insert(
					ScheduleAmendment(
						expected: expected,
						effectiveFrom: .now,
						amount: amount,
						note: "Adjusted in plan"
					)
				)
			} else if let goal = context.model(for: row.id) as? Goal {
				// a goal's schedule lives on the Goal itself and has no amendment
				// mechanism, so this is a straight edit -- the same thing the goal
				// editor does. without this branch the field would accept your
				// change and silently drop it.
				goal.contributionAmount = amount
			}
		}
		try? context.save()
		edits.removeAll()
		rebuild()
		dismiss()
	}

	// MARK: - Pieces

	private var intro: some View {
		Text("Change any amount below and the total at the bottom shows what it does to your \(horizon.label). Tap a name to open it properly.")
			.font(.caption)
			.foregroundStyle(theme.fgColour.opacity(0.6))
			.fixedSize(horizontal: false, vertical: true)
	}

	private var sortPicker: some View {
		HStack {
			Text("Sort by")
				.font(.caption)
				.foregroundStyle(theme.fgColour.opacity(0.6))
			Spacer()
			Picker("Sort", selection: $sort) {
				ForEach(Sort.allCases) { option in
					Text(option.label).tag(option)
				}
			}
			.pickerStyle(.segmented)
			.frame(width: 240)
		}
	}

	private var list: some View {
		Card {
			VStack(spacing: 0) {
				ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
					if index > 0 {
						Divider().background(theme.fgColour.opacity(0.12))
					}
					adjustRow(row)
				}
			}
		}
	}

	private func adjustRow(_ row: Row) -> some View {
		let isEdited = changed.contains { $0.id == row.id }

		return HStack(spacing: 10) {
			Button {
				editing = EditTarget(id: row.id)
			} label: {
				HStack(spacing: 8) {
					Text(row.emoji)

					VStack(alignment: .leading, spacing: 2) {
						HStack(spacing: 5) {
							Text(row.name)
								.font(.subheadline)
								.lineLimit(1)
							if row.isArchived {
								Text("archived")
									.font(.system(size: 8, weight: .semibold))
									.padding(.horizontal, 4)
									.padding(.vertical, 1)
									.overlay { Capsule().stroke(theme.fgColour.opacity(0.3), lineWidth: 1) }
									.foregroundStyle(theme.fgColour.opacity(0.5))
							}
						}

						// the number that decides the ordering, spelled out
						Text("\(row.projected.moneyCompact) over \(horizon.label) · \(row.occurrences)×"
							 + (row.kind == .goalContribution ? " · goal" : ""))
							.font(.caption2)
							.foregroundStyle(theme.fgColour.opacity(0.5))
					}

					Spacer(minLength: 4)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)

			// editable in place -- the entire point of this screen
			InlineAmountField(
				amount: Binding(
					get: { draft(for: row) },
					set: { edits[row.id] = $0 }
				),
				isEdited: isEdited,
				accent: row.isInflow ? palette.inflow : theme.fgColour
			)
		}
		.padding(.vertical, 10)
		.opacity(row.isArchived ? 0.5 : 1)
	}

	@ViewBuilder
	private var totalsBar: some View {
		if !changed.isEmpty {
			HStack(spacing: 12) {
				VStack(alignment: .leading, spacing: 2) {
					Text("\(changed.count) change\(changed.count == 1 ? "" : "s")")
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.6))
					Text(netChange.moneySigned + " over \(horizon.label)")
						.font(.callout.weight(.semibold))
						.monospacedDigit()
						.foregroundStyle(netChange >= 0 ? palette.good : palette.critical)
				}

				Spacer()

				Button("Reset") {
					withAnimation(.easeInOut(duration: 0.18)) { edits.removeAll() }
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

	/// reuse the existing per-item editors rather than growing a second one
	@ViewBuilder
	private func editor(for id: PersistentIdentifier) -> some View {
		if let income = context.model(for: id) as? ExpectedIncome {
			SingleIncomeView(income: income)
		} else if let envelope = context.model(for: id) as? Envelope {
			SingleEnvelopeView(envelope: envelope)
		} else if let expense = context.model(for: id) as? ExpectedExpense {
			SingleExpectedTransactionView(transaction: expense)
		} else if let goal = context.model(for: id) as? Goal {
			GoalDetailView(goal: goal)
		}
	}
}

/* --- Inline amount field ---
 * a compact money input for a dense list: same filtering rules as
 * InputFieldCurrency, but sized to sit at the end of a row
 */
@available(iOS 26, *)
struct InlineAmountField: View {
	@EnvironmentObject var theme: ThemeManager

	@Binding var amount: Decimal
	var isEdited: Bool
	var accent: Color

	@State private var text: String = ""
	@FocusState private var focused: Bool

	private var separator: String { Locale.current.decimalSeparator ?? "." }

	var body: some View {
		HStack(spacing: 1) {
			Text(CurrencySettings.symbol)
				.font(.subheadline)
				.foregroundStyle(accent.opacity(0.7))

			TextField("", text: $text)
				.font(.subheadline)
				.monospacedDigit()
				.keyboardType(.decimalPad)
				.multilineTextAlignment(.trailing)
				.tint(theme.fgColour)
				.focused($focused)
				.frame(width: 62)
				.foregroundStyle(accent)
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 6)
		.background {
			RoundedRectangle(cornerRadius: 8)
				.fill(isEdited ? theme.fgColour.opacity(0.12) : .clear)
		}
		.overlay {
			RoundedRectangle(cornerRadius: 8)
				.stroke(
					isEdited ? theme.fgColour.opacity(0.5) : theme.fgColour.opacity(0.2),
					lineWidth: 1
				)
		}
		.contentShape(Rectangle())
		.onTapGesture { focused = true }
		.onAppear { text = amount.plainDigits }
		.onChange(of: text) { _, new in
			let clean = sanitised(new)
			if clean != new { text = clean }
			amount = Decimal(string: clean.replacingOccurrences(of: separator, with: ".")) ?? 0
		}
		.onChange(of: amount) { _, new in
			let shown = Decimal(string: text.replacingOccurrences(of: separator, with: "."))
			if shown != new { text = new.plainDigits }
		}
	}

	private func sanitised(_ raw: String) -> String {
		var out = ""
		var seenSeparator = false
		var fractionDigits = 0
		for character in raw {
			if character.isNumber {
				if seenSeparator {
					guard fractionDigits < 2 else { continue }
					fractionDigits += 1
				}
				out.append(character)
			} else if String(character) == separator || character == "." || character == "," {
				guard !seenSeparator else { continue }
				seenSeparator = true
				out.append(separator)
			}
		}
		while out.count > 1, out.hasPrefix("0"), !out.hasPrefix("0" + separator) {
			out.removeFirst()
		}
		return out
	}
}
