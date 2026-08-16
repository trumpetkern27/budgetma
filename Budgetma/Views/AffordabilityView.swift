import SwiftUI
import SwiftData

/* --- Can I afford it? ---
 * the differentiator, on one screen
 *
 * the answer isn't "is it less than my monthly surplus" -- it's what happens to
 * the *curve* when this is folded in. two things can go wrong and they're
 * different problems:
 *
 *   structural  -- you'd be spending more than you bring in. no cushion saves you.
 *   liquidity   -- the long run is fine, but you'd dip below what you can absorb
 *                  somewhere in the middle. that's a timing problem, and timing
 *                  problems are exactly what a monthly budget hides.
 */
@available(iOS 26, *)
struct AffordabilityView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context

	@Query private var expectedIncomes: [ExpectedIncome]
	@Query private var expectedExpenses: [ExpectedExpense]
	@Query private var envelopes: [Envelope]
	@Query private var goals: [Goal]
	@Query private var overrides: [OccurrenceOverride]
	@Query private var amendments: [ScheduleAmendment]

	@State var horizon: DateWindow

	@State private var name: String = ""
	@State private var amount: Decimal = 0
	@State private var isRecurring: Bool = false
	@State private var startDate: Date = .now
	@State private var rule: RecurrenceRule?
	@AppStorage("affordabilityBuffer") private var bufferValue: Double = 0

	@State private var result: AffordabilityEngine.Result?
	@State private var isComputing = false

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	private var snapshots: [ScheduleSnapshot] {
		BudgetService.snapshots(
			incomes: expectedIncomes,
			expenses: expectedExpenses,
			envelopes: envelopes,
			goals: goals,
			amendments: amendments
		)
	}

	private var candidate: CandidateSchedule {
		CandidateSchedule(
			name: name.isEmpty ? "This purchase" : name,
			amount: amount,
			startDate: startDate,
			rule: isRecurring ? rule : nil,
			kind: .expense
		)
	}

	private var signature: String {
		"\(name)|\(amount)|\(isRecurring)|\(rule?.frequencyRaw ?? -1)|\(rule?.interval ?? 0)|"
			+ "\(startDate.timeIntervalSince1970)|\(bufferValue)|\(horizon.count)\(horizon.unit.rawValue)|"
			+ "\(snapshots.count)|\(overrides.count)"
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				inputCard
				horizonCard

				if amount > 0 {
					if let result {
						verdictCard(result)
						comparisonCard(result)
						detailCard(result)
					} else if isComputing {
						ProgressView()
							.tint(theme.fgColour)
							.frame(maxWidth: .infinity)
							.padding()
					}
				} else {
					Card {
						Text("Enter an amount to test it against your projection.")
							.font(.callout)
							.foregroundStyle(theme.fgColour.opacity(0.65))
					}
				}
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.dismissableKeyboard()
		.chartPalette(for: theme.bgColour)
		.navigationTitle("Can I afford it?")
		.navigationBarTitleDisplayMode(.inline)
		.task(id: signature) { await recompute() }
	}

	// MARK: - Inputs

	private var inputCard: some View {
		Card(title: "What are you thinking about?") {
			VStack(spacing: 14) {
				InputField(field: "Name", placeholder: "New couch", text: $name)
				InputFieldCurrency(field: "Amount", amount: $amount)

				Picker("Kind", selection: $isRecurring) {
					Text("One time").tag(false)
					Text("Recurring").tag(true)
				}
				.pickerStyle(.segmented)

				if isRecurring {
					// persists: false -- this is hypothetical, it must not
					// leave a RecurrenceRule row behind
					RecurrenceRulePicker(rule: $rule, startDate: $startDate, persists: false)
				} else {
					DatePill(label: "When", date: $startDate)
				}
			}
		}
	}

	private var horizonCard: some View {
		Card(
			title: "Judge it over",
			subtitle: "A purchase that fits this year might not fit over five"
		) {
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

				VStack(alignment: .leading, spacing: 4) {
					HStack {
						Text("Cash cushion")
							.font(.subheadline)
						Spacer()
						Text(Decimal(bufferValue).money)
							.font(.subheadline)
							.monospacedDigit()
					}
					Text("How far below zero you can ride out before it's a problem.")
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.55))

					Slider(value: $bufferValue, in: 0...10_000, step: 100)
						.tint(theme.fgColour)
				}
			}
		}
	}

	// MARK: - Verdict

	private func verdictCard(_ result: AffordabilityEngine.Result) -> some View {
		let (color, icon) = style(for: result.verdict)

		return Card {
			VStack(alignment: .leading, spacing: 12) {
				// icon + label + colour -- never colour on its own
				HStack(spacing: 10) {
					Image(systemName: icon)
						.font(.title2)
						.foregroundStyle(color)

					VStack(alignment: .leading, spacing: 2) {
						Text(result.verdict.label)
							.font(.title3.weight(.semibold))
							.foregroundStyle(color)
						Text(explanation(for: result))
							.font(.caption)
							.foregroundStyle(theme.fgColour.opacity(0.7))
							.fixedSize(horizontal: false, vertical: true)
					}
					Spacer()
				}

				// shown even at zero -- "no" without a number is useless advice
				if let maxAffordable = result.maxAffordable {
					Divider().background(theme.fgColour.opacity(0.2))
					HStack(alignment: .top) {
						Text(maxAffordable <= 0
							 ? "Room for this right now"
							 : (result.verdict == .unaffordable ? "You could manage" : "You could go up to"))
							.font(.caption)
							.foregroundStyle(theme.fgColour.opacity(0.65))
						Spacer()
						Text(maxAffordable <= 0
							 ? "None"
							 : maxAffordable.money + (isRecurring ? " each time" : ""))
							.font(.callout.weight(.semibold))
							.monospacedDigit()
							.foregroundStyle(maxAffordable <= 0 ? palette.critical : palette.good)
					}

					// with no cushion declared the curve starts at zero, so any
					// outflow before the first payday reads as a breach. say so
					// rather than leaving them staring at a flat "no".
					if maxAffordable <= 0 && bufferValue == 0 {
						Text("You haven't set a cash cushion, so anything that dips below zero counts as unaffordable. Set it to roughly what's in the bank.")
							.font(.caption2)
							.foregroundStyle(theme.fgColour.opacity(0.55))
							.fixedSize(horizontal: false, vertical: true)
					}
				}
			}
		}
	}

	private func comparisonCard(_ result: AffordabilityEngine.Result) -> some View {
		Card(
			title: "Before and after",
			subtitle: "Your running balance over \(horizon.label)"
		) {
			ProjectionChart(
				projection: result.baseline,
				comparison: result.projected,
				comparisonLabel: "With \(name.isEmpty ? "it" : name)",
				baselineLabel: "As things stand"
			)
		}
	}

	private func detailCard(_ result: AffordabilityEngine.Result) -> some View {
		Card(title: "The numbers") {
			VStack(spacing: 12) {
				HStack(alignment: .top, spacing: 12) {
					StatTile(
						label: "Total cost",
						value: result.totalCost.money,
						caption: isRecurring ? "Over \(horizon.label)" : "One time"
					)
					StatTile(
						label: "Lowest point",
						value: result.troughAfter.money,
						accent: result.troughAfter < -Decimal(bufferValue) ? palette.critical : theme.fgColour,
						caption: result.troughDate.map {
							"was \(result.troughBefore.moneyCompact) · \($0.formatted(.dateTime.month(.abbreviated).year()))"
						} ?? "was \(result.troughBefore.moneyCompact)"
					)
				}

				HStack(alignment: .top, spacing: 12) {
					StatTile(
						label: "Ends at",
						value: result.endAfter.money,
						accent: result.endAfter >= 0 ? palette.good : palette.critical,
						caption: "was \(result.endBefore.moneyCompact)"
					)
					StatTile(
						label: "Costs you",
						value: result.troughImpact.moneyCompact,
						caption: "Depth added to your worst point"
					)
				}
			}
		}
	}

	// MARK: - Presentation

	private func style(for verdict: AffordabilityEngine.Verdict) -> (Color, String) {
		switch verdict {
		case .comfortable: return (palette.good, "checkmark.circle.fill")
		case .tight: return (palette.warning, "exclamationmark.triangle.fill")
		case .unaffordable: return (palette.critical, "xmark.octagon.fill")
		}
	}

	private func explanation(for result: AffordabilityEngine.Result) -> String {
		switch result.failureReason {
		case .structural:
			return "Over \(horizon.label) you'd be spending more than you bring in — this doesn't balance out, no matter how much cash you're sitting on."
		case .liquidity:
			let date = result.troughDate.map { " around \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? ""
			return "You earn enough overall, but you'd dip to \(result.troughAfter.money)\(date) — past your \(Decimal(bufferValue).money) cushion. A timing problem, not an income one."
		case nil:
			switch result.verdict {
			case .comfortable:
				return "This fits. Your lowest point stays at \(result.troughAfter.money) and you still end \(horizon.label) up \(result.endAfter.moneyCompact)."
			case .tight:
				return "It fits, but not by much — your margin over \(horizon.label) drops to \(result.endAfter.moneyCompact). Worth a second thought."
			case .unaffordable:
				return "This doesn't fit over \(horizon.label)."
			}
		}
	}

	// MARK: - Compute

	private func recompute() async {
		guard amount > 0 else {
			result = nil
			return
		}

		let schedules = snapshots
		let candidateSnapshot = candidate.snapshot()
		let index = OverrideIndex(overrides)
		let range = horizon.range()
		let buffer = Decimal(bufferValue)

		isComputing = true
		let outcome = await Task.detached(priority: .userInitiated) {
			AffordabilityEngine.evaluate(
				candidate: candidateSnapshot,
				against: schedules,
				overrides: index,
				in: range,
				buffer: buffer
			)
		}.value

		result = outcome
		isComputing = false
	}
}
