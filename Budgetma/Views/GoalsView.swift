import SwiftUI
import SwiftData

/* --- Goals ---
 * savings targets, and whether your contributions actually get you there
 *
 * a goal with a contribution schedule is a Schedulable like anything else, so
 * the money you're putting aside shows up as an outflow in the projection --
 * which is the honest way to do it. money earmarked for a couch isn't money you
 * can also spend on something else.
 */
@available(iOS 26, *)
struct GoalsView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context

	@Query(sort: \Goal.name) private var goals: [Goal]

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	private var active: [Goal] { goals.filter { $0.isActive && !$0.isComplete } }
	private var completed: [Goal] { goals.filter { $0.isComplete } }

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				if goals.isEmpty {
					Card(title: "No goals yet") {
						Text("Add something you're saving towards. If you give it a contribution schedule, it'll show up in your projection as money that's already spoken for.")
							.font(.callout)
							.foregroundStyle(theme.fgColour.opacity(0.7))
					}
				}

				ForEach(active) { goal in
					NavigationLink {
						GoalDetailView(goal: goal)
					} label: {
						GoalCard(goal: goal)
					}
					.buttonStyle(.plain)
				}

				if !completed.isEmpty {
					Text("Reached")
						.font(.headline)
						.padding(.top, 4)

					ForEach(completed) { goal in
						NavigationLink {
							GoalDetailView(goal: goal)
						} label: {
							GoalCard(goal: goal)
						}
						.buttonStyle(.plain)
					}
				}
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.navigationTitle("Goals")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				NavigationLink {
					GoalDetailView(goal: nil)
				} label: {
					Image(systemName: "plus.circle.fill")
				}
			}
		}
	}
}

/* --- Goal card --- */
@available(iOS 26, *)
struct GoalCard: View {
	@EnvironmentObject var theme: ThemeManager
	let goal: Goal

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	var body: some View {
		Card {
			VStack(alignment: .leading, spacing: 10) {
				HStack {
					Text("\(goal.emoji) \(goal.name)")
						.font(.headline)
					Spacer()
					if goal.isComplete {
						Image(systemName: "checkmark.seal.fill")
							.foregroundStyle(palette.good)
					}
				}

				ProgressView(value: goal.progress)
					.tint(goal.isComplete ? palette.good : palette.inflow)

				HStack {
					Text("\(goal.currentAmount.money) of \(goal.targetAmount.money)")
						.font(.caption)
						.monospacedDigit()
						.foregroundStyle(theme.fgColour.opacity(0.7))

					Spacer()

					Text("\(Int(goal.progress * 100))%")
						.font(.caption.weight(.semibold))
						.monospacedDigit()
				}

				if let contribution = goal.contributionAmount, contribution > 0 {
					Divider().background(theme.fgColour.opacity(0.15))
					HStack(spacing: 6) {
						Image(systemName: "calendar")
							.font(.caption2)
							.foregroundStyle(theme.fgColour.opacity(0.5))
						Text("\(contribution.money) scheduled")
							.font(.caption2)
							.foregroundStyle(theme.fgColour.opacity(0.6))

						Spacer()

						if let completion = goal.projectedCompletion() {
							Text("On track for \(completion.formatted(.dateTime.month(.abbreviated).year()))")
								.font(.caption2)
								.foregroundStyle(deadlineColor(completion))
						}
					}
				}
			}
		}
	}

	/// red when the schedule misses the target date -- with the date spelled
	/// out beside it, so colour isn't carrying the message alone
	private func deadlineColor(_ completion: Date) -> Color {
		guard let target = goal.targetDate else { return theme.fgColour.opacity(0.6) }
		return completion <= target ? palette.good : palette.critical
	}
}

/* --- Goal detail / create --- */
@available(iOS 26, *)
struct GoalDetailView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss

	let goal: Goal?

	@State private var name: String = ""
	@State private var emoji: String = "🎯"
	@State private var targetAmount: Decimal = 0
	@State private var hasTargetDate: Bool = false
	@State private var targetDate: Date = .now
	@State private var contributionAmount: Decimal = 0
	@State private var contributionStart: Date = .now
	@State private var contributionRule: RecurrenceRule?
	@State private var seedAmount: Decimal = 0
	@State private var interestRate: Decimal = 0

	@State private var newContribution: Decimal = 0

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				detailsCard
				scheduleCard

				if let goal {
					progressCard(goal)
					contributionsCard(goal)
					deleteButton(goal)
				}
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.dismissableKeyboard()
		.navigationTitle(goal == nil ? "New goal" : name)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button("Cancel") { dismiss() }
			}
			ToolbarItem(placement: .confirmationAction) {
				Button("Save") { save() }
					.disabled(targetAmount <= 0)
			}
		}
		.onAppear(perform: load)
	}

	private var detailsCard: some View {
		Card {
			VStack(spacing: 14) {
				InputField(field: "Name", placeholder: "New couch", text: $name)
				InputField(field: "Emoji", placeholder: "🎯", text: $emoji)
				InputFieldCurrency(field: "Target", amount: $targetAmount)
				// money already set aside before you started tracking this
				InputFieldCurrency(field: "Starting balance", amount: $seedAmount)

				Toggle("Target date", isOn: $hasTargetDate)
				if hasTargetDate {
					DatePill(label: "By", date: $targetDate)
				}
			}
		}
	}

	private var scheduleCard: some View {
		Card(
			title: "Contributions",
			subtitle: "Scheduled contributions count as outflows in your projection"
		) {
			VStack(spacing: 14) {
				InputFieldCurrency(field: "Amount each time", amount: $contributionAmount)
				if contributionAmount > 0 {
					RecurrenceRulePicker(rule: $contributionRule, startDate: $contributionStart)
				}

				// a savings pot usually earns something, and over the years a
				// goal takes that compounding is not a rounding error
				HStack {
					Text("Interest (APY)")
					Spacer()
					PercentField(rate: $interestRate)
				}
			}
		}
	}

	private func progressCard(_ goal: Goal) -> some View {
		Card(title: "Progress") {
			VStack(alignment: .leading, spacing: 10) {
				ProgressView(value: goal.progress)
					.tint(goal.isComplete ? palette.good : palette.inflow)

				HStack(alignment: .top, spacing: 12) {
					StatTile(
						label: "Saved",
						value: goal.currentAmount.money,
						accent: palette.good,
						caption: goal.seedAmount > 0
							? "\(goal.contributedAmount.moneyCompact) logged · \(goal.seedAmount.moneyCompact) starting"
							: nil
					)
					StatTile(label: "To go", value: goal.remaining.money)
				}

				if let completion = goal.projectedCompletion() {
					HStack(spacing: 6) {
						Image(systemName: "flag.checkered")
							.font(.caption)
						Text("At this rate you'll get there \(completion.formatted(.dateTime.month(.abbreviated).year()))")
							.font(.caption)
						if goal.annualInterestRate > 0 {
							Text("· \((goal.annualInterestRate * 100).formatted(.number.precision(.fractionLength(0...2))))% APY")
								.font(.caption2)
								.foregroundStyle(theme.fgColour.opacity(0.5))
						}
					}
					.foregroundStyle(theme.fgColour.opacity(0.7))
				}

				NavigationLink {
					GoalSimulatorView(goal: goal)
				} label: {
					HStack(spacing: 8) {
						Image(systemName: "slider.horizontal.3")
							.font(.caption)
						Text("What if I contributed more?")
							.font(.caption.weight(.semibold))
						Spacer()
						Image(systemName: "chevron.right")
							.font(.caption2)
							.foregroundStyle(theme.fgColour.opacity(0.4))
					}
					.padding(.vertical, 10)
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
			}
		}
	}

	/* --- putting money in ---
	 * two genuinely different things, so two buttons rather than one.
	 *
	 * "Log it" creates a Savings transaction: money left your account today, it
	 * belongs in the cashflow, and it can settle a scheduled contribution.
	 *
	 * "Just add it" moves the goal's balance without inventing a transaction --
	 * for money you already had, or a pot you're starting part-way full. logging
	 * that as a contribution would put an outflow in your budget that never
	 * happened, and make this window look worse than it was.
	 */
	private func contributionsCard(_ goal: Goal) -> some View {
		Card(title: "Add money") {
			VStack(spacing: 12) {
				InputFieldCurrency(field: "Amount", amount: $newContribution)

				HStack(spacing: 10) {
					Button {
						guard newContribution > 0 else { return }
						context.insert(
							Savings(
								name: "\(goal.name) contribution",
								date: .now,
								amount: newContribution,
								goal: goal
							)
						)
						newContribution = 0
						try? context.save()
					} label: {
						Label("Log it", systemImage: "arrow.down.circle")
							.font(.caption)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 8)
							.overlay {
								RoundedRectangle(cornerRadius: 10)
									.stroke(theme.fgColour.opacity(0.35), lineWidth: 1)
							}
					}
					.buttonStyle(.plain)
					.disabled(newContribution <= 0)
					.opacity(newContribution > 0 ? 1 : 0.4)

					Button {
						guard newContribution > 0 else { return }
						goal.seedAmount += newContribution
						newContribution = 0
						try? context.save()
					} label: {
						Label("Just add it", systemImage: "tray.and.arrow.down")
							.font(.caption)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 8)
							.overlay {
								RoundedRectangle(cornerRadius: 10)
									.stroke(theme.fgColour.opacity(0.35), lineWidth: 1)
							}
					}
					.buttonStyle(.plain)
					.disabled(newContribution <= 0)
					.opacity(newContribution > 0 ? 1 : 0.4)
				}

				Text("“Log it” records a transaction in your budget. “Just add it” only moves this goal's balance.")
					.font(.caption2)
					.foregroundStyle(theme.fgColour.opacity(0.5))
					.frame(maxWidth: .infinity, alignment: .leading)

				if goal.seedAmount > 0 || !goal.contributions.isEmpty {
					Divider().background(theme.fgColour.opacity(0.15))
				}

				if goal.seedAmount > 0 {
					HStack {
						Text("Starting balance")
							.font(.caption)
							.foregroundStyle(theme.fgColour.opacity(0.6))
						Spacer()
						Text(goal.seedAmount.money)
							.font(.caption)
							.monospacedDigit()
						Button {
							goal.seedAmount = 0
							try? context.save()
						} label: {
							Image(systemName: "xmark.circle")
								.font(.caption2)
								.foregroundStyle(theme.fgColour.opacity(0.5))
						}
						.buttonStyle(.plain)
					}
				}

				ForEach(goal.contributions.sorted { $0.date > $1.date }) { saving in
					HStack {
						Text(saving.date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)))
							.font(.caption)
							.foregroundStyle(theme.fgColour.opacity(0.6))
						if saving.occurrenceDate != nil {
							Image(systemName: "link")
								.font(.system(size: 8))
								.foregroundStyle(theme.fgColour.opacity(0.5))
						}
						Spacer()
						Text(saving.amount.money)
							.font(.caption)
							.monospacedDigit()
					}
				}
			}
		}
	}

	private func deleteButton(_ goal: Goal) -> some View {
		Button(role: .destructive) {
			context.delete(goal)
			try? context.save()
			dismiss()
		} label: {
			Label("Delete goal", systemImage: "trash")
				.frame(maxWidth: .infinity)
		}
	}

	// MARK: - Persistence

	private func load() {
		guard let goal else { return }
		name = goal.name
		emoji = goal.emoji
		targetAmount = goal.targetAmount
		hasTargetDate = goal.targetDate != nil
		targetDate = goal.targetDate ?? .now
		seedAmount = goal.seedAmount
		interestRate = goal.annualInterestRate
		contributionAmount = goal.contributionAmount ?? 0
		contributionStart = goal.contributionStart
		contributionRule = goal.contributionRule
	}

	private func save() {
		let finalName = name.isEmpty ? "Goal" : name
		let finalEmoji = emoji.isEmpty ? "🎯" : String(emoji.prefix(2))

		if let goal {
			goal.name = finalName
			goal.emoji = finalEmoji
			goal.targetAmount = targetAmount
			goal.targetDate = hasTargetDate ? targetDate : nil
			goal.seedAmount = seedAmount
			goal.annualInterestRate = interestRate
			goal.contributionAmount = contributionAmount > 0 ? contributionAmount : nil
			goal.contributionStart = contributionStart
			goal.contributionRule = contributionRule
		} else {
			context.insert(
				Goal(
					name: finalName,
					emoji: finalEmoji,
					targetAmount: targetAmount,
					targetDate: hasTargetDate ? targetDate : nil,
					seedAmount: seedAmount,
					annualInterestRate: interestRate,
					contributionAmount: contributionAmount > 0 ? contributionAmount : nil,
					contributionStart: contributionStart,
					contributionRule: contributionRule
				)
			)
		}

		try? context.save()
		dismiss()
	}
}
