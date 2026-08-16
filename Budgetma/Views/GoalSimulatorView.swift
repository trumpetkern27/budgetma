import SwiftUI
import SwiftData
import Charts

/* --- Goal simulator ---
 * "what if I put in more?"
 *
 * two scenarios on one pair of axes: what you're currently doing, and what
 * you're considering. the answer people actually want is a *date* — when do I
 * get there — so that's the headline, with the balance curves underneath
 * showing how much of the result is interest rather than contribution.
 */
@available(iOS 26, *)
struct GoalSimulatorView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.chartPalette) private var palette

	@Bindable var goal: Goal

	@State private var whatIfAmount: Decimal = 0
	@State private var whatIfRate: Decimal = 0
	@State private var horizonYears: Int = 10
	@State private var didLoad = false

	private var themePalette: ChartPalette { .forSurface(theme.bgColour) }

	private var horizon: Date {
		Calendar.current.date(byAdding: .year, value: horizonYears, to: .now) ?? .now
	}

	private var rule: Calendar.RecurrenceRule? {
		goal.contributionRule?.toRecurranceRule()
	}

	private var current: GoalSimulator.Result {
		GoalSimulator.simulate(
			.init(
				contribution: goal.contributionAmount ?? 0,
				rule: rule,
				start: goal.contributionStart,
				annualRate: goal.annualInterestRate,
				openingBalance: goal.currentAmount
			),
			target: goal.targetAmount,
			horizon: horizon
		)
	}

	private var whatIf: GoalSimulator.Result {
		GoalSimulator.simulate(
			.init(
				contribution: whatIfAmount,
				rule: rule,
				start: goal.contributionStart,
				annualRate: whatIfRate,
				openingBalance: goal.currentAmount
			),
			target: goal.targetAmount,
			horizon: horizon
		)
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				controls
				verdict
				chartCard
				breakdown
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.chartPalette(for: theme.bgColour)
		.dismissableKeyboard()
		.navigationTitle("What if…")
		.navigationBarTitleDisplayMode(.inline)
		.onAppear {
			guard !didLoad else { return }
			didLoad = true
			// open on the current plan, so the first thing you see is your own
			// situation and every change is measured against it
			whatIfAmount = goal.contributionAmount ?? 0
			whatIfRate = goal.annualInterestRate
		}
	}

	// MARK: - Controls

	private var controls: some View {
		Card(
			title: "Try something else",
			subtitle: "Same schedule, different numbers"
		) {
			VStack(spacing: 14) {
				InputFieldCurrency(field: "Contribute", amount: $whatIfAmount)

				HStack {
					Text("Interest (APY)")
					Spacer()
					PercentField(rate: $whatIfRate)
				}

				// quick nudges, because the question is usually "a bit more?"
				HStack(spacing: 8) {
					ForEach(nudges, id: \.self) { delta in
						Button {
							whatIfAmount = max(0, whatIfAmount + delta)
						} label: {
							Text(delta > 0 ? "+\(delta.moneyRounded)" : "−\(abs(delta).moneyRounded)")
								.font(.caption)
								.frame(maxWidth: .infinity)
								.padding(.vertical, 6)
								.overlay {
									RoundedRectangle(cornerRadius: 8)
										.stroke(theme.fgColour.opacity(0.35), lineWidth: 1)
								}
						}
						.buttonStyle(.plain)
					}
				}

				HStack {
					Text("Look ahead")
						.font(.caption)
					Spacer()
					Picker("Years", selection: $horizonYears) {
						ForEach([1, 2, 5, 10, 20, 30], id: \.self) { years in
							Text("\(years)y").tag(years)
						}
					}
					.pickerStyle(.segmented)
					.frame(width: 240)
				}
			}
		}
	}

	private var nudges: [Decimal] {
		let base = goal.contributionAmount ?? 100
		let step = max((base / 4).rounded(0), 10)
		return [-step, step, step * 2]
	}

	// MARK: - Verdict

	@ViewBuilder
	private var verdict: some View {
		let currentDate = current.completion
		let whatIfDate = whatIf.completion

		Card(title: "When you get there") {
			VStack(spacing: 12) {
				HStack(alignment: .top, spacing: 12) {
					StatTile(
						label: "Now",
						value: completionLabel(currentDate),
						accent: theme.fgColour,
						caption: (goal.contributionAmount ?? 0).money + " each time"
					)
					StatTile(
						label: "What if",
						value: completionLabel(whatIfDate),
						accent: verdictColour(currentDate, whatIfDate),
						caption: whatIfAmount.money + " each time"
					)
				}

				if let currentDate, let whatIfDate, currentDate != whatIfDate {
					let sooner = whatIfDate < currentDate
					HStack(spacing: 6) {
						Image(systemName: sooner ? "arrow.down.right" : "arrow.up.right")
							.font(.caption)
							.foregroundStyle(sooner ? themePalette.good : themePalette.critical)
						Text(
							sooner
								? "\(GoalSimulator.timeToTarget(from: whatIfDate, to: currentDate)) sooner"
								: "\(GoalSimulator.timeToTarget(from: currentDate, to: whatIfDate)) later"
						)
						.font(.caption.weight(.semibold))
						.foregroundStyle(sooner ? themePalette.good : themePalette.critical)
						Spacer()
					}
				} else if whatIfDate == nil {
					Text("Doesn't reach \(goal.targetAmount.money) within \(horizonYears) years.")
						.font(.caption)
						.foregroundStyle(theme.fgColour.opacity(0.6))
						.frame(maxWidth: .infinity, alignment: .leading)
				}
			}
		}
	}

	private func completionLabel(_ date: Date?) -> String {
		guard let date else { return "—" }
		return date.formatted(.dateTime.month(.abbreviated).year())
	}

	private func verdictColour(_ current: Date?, _ whatIf: Date?) -> Color {
		guard let current, let whatIf else { return theme.fgColour }
		if whatIf == current { return theme.fgColour }
		return whatIf < current ? themePalette.good : themePalette.critical
	}

	// MARK: - Chart

	private var chartCard: some View {
		Card(
			title: "Balance over time",
			subtitle: "Solid is what you're doing now · dashed is the what-if"
		) {
			Chart {
				ForEach(current.points) { point in
					LineMark(
						x: .value("Date", point.date),
						y: .value("Balance", point.balance.doubleValue),
						series: .value("Series", "Now")
					)
					.foregroundStyle(palette.baseline)
					.lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
					.interpolationMethod(.monotone)
				}

				ForEach(whatIf.points) { point in
					LineMark(
						x: .value("Date", point.date),
						y: .value("Balance", point.balance.doubleValue),
						series: .value("Series", "What if")
					)
					.foregroundStyle(palette.candidate)
					.lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 3]))
					.interpolationMethod(.monotone)
				}

				// the finish line
				if goal.targetAmount > 0 {
					RuleMark(y: .value("Target", goal.targetAmount.doubleValue))
						.foregroundStyle(palette.axis.opacity(0.7))
						.lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
						.annotation(position: .top, alignment: .leading) {
							Text("target \(goal.targetAmount.moneyCompact)")
								.font(.caption2)
								.foregroundStyle(theme.fgColour.opacity(0.6))
						}
				}

				if let completion = whatIf.completion {
					PointMark(
						x: .value("Date", completion),
						y: .value("Balance", goal.targetAmount.doubleValue)
					)
					.symbolSize(70)
					.foregroundStyle(palette.candidate)
				}
			}
			.frame(height: 220)
			.chartXAxis {
				AxisMarks(values: .automatic(desiredCount: 4)) { value in
					AxisGridLine().foregroundStyle(palette.grid)
					AxisValueLabel {
						if let date = value.as(Date.self) {
							Text(date.formatted(.dateTime.year()))
								.font(.caption2)
								.foregroundStyle(theme.fgColour.opacity(0.7))
						}
					}
				}
			}
			.chartYAxis {
				AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
					AxisGridLine().foregroundStyle(palette.grid)
					AxisValueLabel {
						if let amount = value.as(Double.self) {
							Text(Decimal(amount).moneyCompact)
								.font(.caption2)
								.foregroundStyle(theme.fgColour.opacity(0.7))
						}
					}
				}
			}
		}
	}

	// MARK: - Breakdown

	private var breakdown: some View {
		Card(
			title: "Where the money comes from",
			subtitle: "Over \(horizonYears) year\(horizonYears == 1 ? "" : "s")"
		) {
			VStack(spacing: 0) {
				breakdownRow(
					label: "What you put in",
					now: current.totalContributed,
					whatIf: whatIf.totalContributed
				)
				Divider().background(theme.fgColour.opacity(0.12))
				breakdownRow(
					label: "What the interest adds",
					now: current.totalInterest,
					whatIf: whatIf.totalInterest,
					accent: themePalette.good
				)
				Divider().background(theme.fgColour.opacity(0.12))
				breakdownRow(
					label: "Ending balance",
					now: current.finalBalance,
					whatIf: whatIf.finalBalance,
					emphasised: true
				)
			}
		}
	}

	private func breakdownRow(
		label: String,
		now: Decimal,
		whatIf: Decimal,
		accent: Color? = nil,
		emphasised: Bool = false
	) -> some View {
		HStack {
			Text(label)
				.font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
			Spacer()
			VStack(alignment: .trailing, spacing: 2) {
				Text(now.money)
					.font(.caption)
					.monospacedDigit()
					.foregroundStyle(accent ?? theme.fgColour.opacity(0.7))
				Text(whatIf.money)
					.font(.caption.weight(.semibold))
					.monospacedDigit()
					.foregroundStyle(palette.candidate)
			}
		}
		.padding(.vertical, 10)
	}
}

/* --- Percent field ---
 * APY is entered the way a bank quotes it (4.0), stored the way maths wants it
 * (0.04). doing that conversion at the boundary keeps every calculation honest.
 */
@available(iOS 26, *)
struct PercentField: View {
	@EnvironmentObject var theme: ThemeManager
	@Binding var rate: Decimal

	@State private var text: String = ""
	@FocusState private var focused: Bool

	var body: some View {
		HStack(spacing: 2) {
			ZStack(alignment: .trailing) {
				if text.isEmpty {
					Text("0.0")
						.foregroundStyle(theme.fgColour.opacity(0.4))
				}
				TextField("", text: $text)
					.keyboardType(.decimalPad)
					.multilineTextAlignment(.trailing)
					.tint(theme.fgColour)
					.focused($focused)
					.fixedSize()
			}
			Text("%")
				.foregroundStyle(text.isEmpty ? theme.fgColour.opacity(0.4) : theme.fgColour)
		}
		.contentShape(Rectangle())
		.onTapGesture { focused = true }
		.onAppear { text = display(rate) }
		.onChange(of: text) { _, new in
			let clean = sanitised(new)
			if clean != new { text = clean }
			let percent = Decimal(string: clean.replacingOccurrences(of: separator, with: ".")) ?? 0
			rate = percent / 100
		}
		.onChange(of: rate) { _, new in
			// only reformat when something else changed it
			let shown = Decimal(string: text.replacingOccurrences(of: separator, with: ".")) ?? 0
			if shown / 100 != new { text = display(new) }
		}
	}

	private var separator: String { Locale.current.decimalSeparator ?? "." }

	private func display(_ rate: Decimal) -> String {
		guard rate > 0 else { return "" }
		let percent = rate * 100
		return percent.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
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
		return out
	}
}
