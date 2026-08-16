import SwiftUI
import SwiftData

/* --- Changing what something is worth ---
 * shared by expected income, expected expenses and envelopes
 *
 * there are two entirely different reasons to change an amount, and conflating
 * them is how budgeting apps quietly lie to you about your own history:
 *
 *   "it was always this, I typed it wrong"  -> edit the base amount
 *   "from March I'm paid more"              -> record an amendment
 *
 * the first rewrites every occurrence, past included. the second leaves settled
 * history exactly as it was and applies from a date forward. asking which one
 * you meant costs a single tap and is the only way to get this right.
 */
@available(iOS 26, *)
struct AmendmentsCard: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context

	/// nil while the item is still being created -- nothing to amend yet
	let expected: ExpectedTransaction?
	/// the item's original amount, for the "before" row
	let baseAmount: Decimal
	let startDate: Date

	@Query private var allAmendments: [ScheduleAmendment]

	@State private var isAdding = false
	@State private var newAmount: Decimal = 0
	@State private var newDate: Date = .now
	@State private var newNote: String = ""

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	private var mine: [ScheduleAmendment] {
		guard let id = expected?.persistentModelID else { return [] }
		return allAmendments
			.filter { $0.expected?.persistentModelID == id }
			.sorted { $0.effectiveFrom < $1.effectiveFrom }
	}

	var body: some View {
		Card(
			title: "Amount history",
			subtitle: "Change it from a date forward without touching what's already happened"
		) {
			VStack(spacing: 0) {
				// the original, always first
				row(
					label: "Originally",
					date: startDate,
					amount: baseAmount,
					note: nil,
					onDelete: nil
				)

				ForEach(mine) { amendment in
					Divider().background(theme.fgColour.opacity(0.12))
					row(
						label: "From",
						date: amendment.effectiveFrom,
						amount: amendment.amount,
						note: amendment.note
					) {
						context.delete(amendment)
						try? context.save()
					}
				}

				Divider().background(theme.fgColour.opacity(0.12))

				if isAdding {
					addForm
				} else {
					Button {
						newAmount = mine.last?.amount ?? baseAmount
						newDate = .now
						newNote = ""
						withAnimation(.easeInOut(duration: 0.18)) { isAdding = true }
					} label: {
						HStack(spacing: 8) {
							Image(systemName: "plus.circle")
								.font(.caption)
							Text("Change from a date")
								.font(.caption)
							Spacer()
						}
						.padding(.vertical, 10)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.disabled(expected == nil)
					.opacity(expected == nil ? 0.4 : 1)
				}

				if expected == nil {
					Text("Save this first, then you can change it from a date.")
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.5))
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.bottom, 6)
				}
			}
		}
	}

	private var addForm: some View {
		VStack(spacing: 12) {
			InputFieldCurrency(field: "New amount", amount: $newAmount)
			DatePill(label: "Effective from", date: $newDate)
			InputField(field: "Why", placeholder: "annual raise", text: $newNote)

			HStack(spacing: 10) {
				Button("Cancel") {
					withAnimation(.easeInOut(duration: 0.18)) { isAdding = false }
				}
				.font(.caption)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 8)
				.overlay {
					RoundedRectangle(cornerRadius: 10)
						.stroke(theme.fgColour.opacity(0.35), lineWidth: 1)
				}

				Button("Add change") { add() }
					.font(.caption.weight(.semibold))
					.frame(maxWidth: .infinity)
					.padding(.vertical, 8)
					.background(theme.fgColour)
					.foregroundStyle(theme.bgColour)
					.clipShape(RoundedRectangle(cornerRadius: 10))
					.disabled(newAmount <= 0)
					.opacity(newAmount > 0 ? 1 : 0.5)
			}
			.buttonStyle(.plain)
		}
		.padding(.vertical, 10)
	}

	private func row(
		label: String,
		date: Date,
		amount: Decimal,
		note: String?,
		onDelete: (() -> Void)?
	) -> some View {
		HStack(spacing: 10) {
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 5) {
					Text(label)
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.5))
					Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
						.font(.caption)
				}
				if let note, !note.isEmpty {
					Text(note)
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.5))
				}
			}

			Spacer()

			Text(amount.money)
				.font(.subheadline)
				.monospacedDigit()

			if let onDelete {
				Button(action: onDelete) {
					Image(systemName: "xmark.circle")
						.font(.caption)
						.foregroundStyle(theme.fgColour.opacity(0.45))
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.vertical, 9)
	}

	private func add() {
		guard let expected, newAmount > 0 else { return }
		context.insert(
			ScheduleAmendment(
				expected: expected,
				effectiveFrom: newDate,
				amount: newAmount,
				note: newNote.isEmpty ? nil : newNote
			)
		)
		try? context.save()
		withAnimation(.easeInOut(duration: 0.18)) { isAdding = false }
	}
}

/* --- the save-time question ---
 * shown when you edit the amount of something that already exists
 */
@available(iOS 26, *)
struct AmountChangeDialog: ViewModifier {
	@Binding var isPresented: Bool
	let oldAmount: Decimal
	let newAmount: Decimal
	/// rewrite history: the number was simply wrong
	let onCorrect: () -> Void
	/// leave history alone and apply from today
	let onAmend: () -> Void

	func body(content: Content) -> some View {
		content.confirmationDialog(
			"Amount changed",
			isPresented: $isPresented,
			titleVisibility: .visible
		) {
			Button("Change from today onwards") { onAmend() }
			Button("Correct it everywhere") { onCorrect() }
			Button("Cancel", role: .cancel) {}
		} message: {
			Text(
				"""
				\(oldAmount.money) → \(newAmount.money)

				"From today" keeps everything you've already logged as it was. \
				"Everywhere" rewrites past occurrences too, for when the old figure was just wrong.
				"""
			)
		}
	}
}

@available(iOS 26, *)
extension View {
	func amountChangeDialog(
		isPresented: Binding<Bool>,
		from oldAmount: Decimal,
		to newAmount: Decimal,
		onCorrect: @escaping () -> Void,
		onAmend: @escaping () -> Void
	) -> some View {
		modifier(
			AmountChangeDialog(
				isPresented: isPresented,
				oldAmount: oldAmount,
				newAmount: newAmount,
				onCorrect: onCorrect,
				onAmend: onAmend
			)
		)
	}
}
