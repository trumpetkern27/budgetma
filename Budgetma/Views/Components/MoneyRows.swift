import SwiftUI
import SwiftData

/* --- Money rows ---
 * the two row shapes every detail list in the app is built from
 *
 * a planned occurrence and a logged actual are different things and read
 * differently, but they turn up side by side all over: the day sheet, the stat
 * tile breakdowns, the envelope drill-down. defining them once means a settled
 * expense looks the same wherever you meet it.
 */

/// one projected occurrence — what the plan says should happen
@available(iOS 26, *)
struct ScheduledEventRow: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.chartPalette) private var palette

	let event: ScheduledEvent
	var isSettled: Bool = false
	/// what was actually logged against it, when that's known
	var actualAmount: Decimal?

	var body: some View {
		HStack(spacing: 10) {
			Text(event.emoji)

			VStack(alignment: .leading, spacing: 2) {
				Text(event.name)
					.font(.subheadline)
					.lineLimit(1)

				HStack(spacing: 4) {
					Image(systemName: isSettled ? "checkmark.circle.fill" : "clock")
						.font(.system(size: 9))
						.foregroundStyle(isSettled ? palette.good : theme.fgColour.opacity(0.45))
					Text(isSettled ? "Settled" : kindLabel)
						.font(.caption2)
						.foregroundStyle(isSettled ? palette.good : theme.fgColour.opacity(0.5))
				}
			}

			Spacer()

			VStack(alignment: .trailing, spacing: 2) {
				Text(event.amount.money)
					.font(.subheadline)
					.monospacedDigit()
					.foregroundStyle(event.isInflow ? palette.inflow : theme.fgColour)

				if let actualAmount, isSettled, actualAmount != event.amount {
					Text("logged \(actualAmount.money)")
						.font(.caption2)
						.monospacedDigit()
						.foregroundStyle(theme.fgColour.opacity(0.55))
				}
			}
		}
		.padding(.vertical, 9)
		.contentShape(Rectangle())
	}

	private var kindLabel: String {
		switch event.kind {
		case .income: return "Expected income"
		case .expense: return "Planned"
		case .envelopeFunding: return "Envelope funding"
		case .goalContribution: return "Goal contribution"
		}
	}
}

/// one logged actual — what really happened
@available(iOS 26, *)
struct TransactionRow: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.chartPalette) private var palette

	let transaction: Transaction
	var showsDate: Bool = false

	private var isIncome: Bool { transaction is Income }

	var body: some View {
		HStack(spacing: 10) {
			Text(transaction.category?.emoji ?? (isIncome ? "💰" : "💸"))

			VStack(alignment: .leading, spacing: 2) {
				Text(transaction.name)
					.font(.subheadline)
					.lineLimit(1)

				HStack(spacing: 4) {
					if transaction.expected != nil || (transaction as? Savings)?.goal != nil {
						Image(systemName: "link")
							.font(.system(size: 8))
					}
					Text(caption)
						.lineLimit(1)
				}
				.font(.caption2)
				.foregroundStyle(theme.fgColour.opacity(0.5))
			}

			Spacer()

			Text((isIncome ? transaction.amount : -transaction.amount).moneySigned)
				.font(.subheadline)
				.monospacedDigit()
				.foregroundStyle(isIncome ? palette.inflow : theme.fgColour)
		}
		.padding(.vertical, 9)
		.contentShape(Rectangle())
	}

	private var caption: String {
		var parts: [String] = []

		if let expected = transaction.expected {
			parts.append(expected.name)
		} else if let goal = (transaction as? Savings)?.goal {
			parts.append(goal.name)
		} else {
			parts.append("Unplanned")
		}

		if showsDate {
			parts.append(transaction.date.formatted(.dateTime.month(.abbreviated).day()))
		}
		if let note = transaction.note, !note.isEmpty {
			parts.append(note)
		}
		return parts.joined(separator: " · ")
	}
}

/* --- Detail sheet chrome ---
 * every drill-down in the app is "a title, a headline number, and some rows",
 * so the shell is written once
 */
@available(iOS 26, *)
struct DetailSheet<Content: View>: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.dismiss) private var dismiss

	let title: String
	var subtitle: String?
	@ViewBuilder var content: () -> Content

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				content()
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.chartPalette(for: theme.bgColour)
		.navigationTitle(title)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .confirmationAction) {
				Button("Done") { dismiss() }
			}
		}
		.safeAreaInset(edge: .top) {
			if let subtitle {
				Text(subtitle)
					.font(.caption)
					.foregroundStyle(theme.fgColour.opacity(0.6))
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal)
					.padding(.bottom, 4)
					.background(theme.bgColour)
			}
		}
	}
}
