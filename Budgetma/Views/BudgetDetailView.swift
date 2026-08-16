import SwiftUI
import SwiftData

/* --- Behind a headline number ---
 * every stat tile on the Budget screen is a sum, and a sum you can't open is a
 * number you have to take on faith. this is the rows each one was added up from.
 */
@available(iOS 26, *)
struct BudgetDetailView: View {
	@EnvironmentObject var theme: ThemeManager

	let detail: BudgetView.Detail
	let summary: ReconciliationService.Summary
	let range: Range<Date>

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	private var windowLabel: String {
		range.lowerBound.formatted(.dateTime.month(.abbreviated).day()) + " – "
			+ range.upperBound.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day())
	}

	var body: some View {
		DetailSheet(title: title, subtitle: windowLabel) {
			switch detail {
			case .planned: plannedContent
			case .actual: actualContent
			case .drift: driftContent
			case .unplanned: unplannedContent
			}
		}
	}

	private var title: String {
		switch detail {
		case .planned: return "Planned net"
		case .actual: return "Actual net"
		case .drift: return "Drift"
		case .unplanned: return "Unplanned"
		}
	}

	// MARK: - Planned

	@ViewBuilder
	private var plannedContent: some View {
		HStack(alignment: .top, spacing: 12) {
			StatTile(label: "In", value: summary.expectedInflow.money, accent: palette.inflow)
			StatTile(label: "Out", value: summary.expectedOutflow.money, accent: palette.outflow)
		}

		let inflows = summary.lines.filter(\.isInflow)
		let outflows = summary.lines.filter { !$0.isInflow }

		if !inflows.isEmpty {
			lineCard(title: "Coming in", lines: inflows)
		}
		if !outflows.isEmpty {
			lineCard(title: "Going out", lines: outflows)
		}
		if summary.lines.isEmpty {
			emptyCard("Nothing is scheduled in this window.")
		}
	}

	// MARK: - Actual

	@ViewBuilder
	private var actualContent: some View {
		HStack(alignment: .top, spacing: 12) {
			StatTile(label: "In", value: summary.actualInflow.money, accent: palette.inflow)
			StatTile(label: "Out", value: summary.actualOutflow.money, accent: palette.outflow)
		}

		// everything logged in this window: what settled a plan, and what didn't
		let settled = summary.lines.filter(\.hasActuals).flatMap(\.actuals)
		let all = (settled + summary.unplanned).sorted { $0.date > $1.date }

		if all.isEmpty {
			emptyCard("Nothing logged in this window yet.")
		} else {
			Card(title: "Logged", subtitle: "\(all.count) transaction\(all.count == 1 ? "" : "s") · tap to edit") {
				VStack(spacing: 0) {
					ForEach(all) { transaction in
						NavigationLink {
							LogTransactionView(editing: transaction)
						} label: {
							TransactionRow(transaction: transaction, showsDate: true)
						}
						.buttonStyle(.plain)

						if transaction.persistentModelID != all.last?.persistentModelID {
							Divider().background(theme.fgColour.opacity(0.12))
						}
					}
				}
			}
		}
	}

	// MARK: - Drift

	@ViewBuilder
	private var driftContent: some View {
		// only lines that have actually moved against plan explain the drift
		let moved = summary.lines
			.filter { $0.hasActuals && $0.variance != 0 }
			.sorted { abs($0.variance) > abs($1.variance) }
		let missing = summary.lines.filter { !$0.hasActuals && $0.date <= .now }

		if moved.isEmpty && missing.isEmpty {
			emptyCard("Everything so far has landed on plan.")
		}

		if !moved.isEmpty {
			Card(title: "Off plan", subtitle: "Logged, but not for what you expected") {
				VStack(spacing: 0) {
					ForEach(moved) { line in
						varianceRow(line)
						if line.id != moved.last?.id {
							Divider().background(theme.fgColour.opacity(0.12))
						}
					}
				}
			}
		}

		if !missing.isEmpty {
			Card(
				title: "Due but not logged",
				subtitle: "These are still counted in the plan, so they weigh on drift"
			) {
				VStack(spacing: 0) {
					ForEach(missing) { line in
						NavigationLink {
							LogTransactionView(prefill: line.event)
						} label: {
							ScheduledEventRow(event: line.event)
						}
						.buttonStyle(.plain)

						if line.id != missing.last?.id {
							Divider().background(theme.fgColour.opacity(0.12))
						}
					}
				}
			}
		}
	}

	private func varianceRow(_ line: ReconciliationService.Line) -> some View {
		// for an outflow, spending *more* than planned is the bad direction; for
		// an inflow it's the opposite. the sign alone can't say which.
		let isBad = line.isInflow ? line.variance < 0 : line.variance > 0

		return HStack(spacing: 10) {
			Text(line.emoji)

			VStack(alignment: .leading, spacing: 2) {
				Text(line.name)
					.font(.subheadline)
					.lineLimit(1)
				Text("planned \(line.expectedAmount.money) · logged \(line.actualAmount.money)")
					.font(.caption2)
					.foregroundStyle(theme.fgColour.opacity(0.5))
			}

			Spacer()

			Text(line.variance.moneySigned)
				.font(.subheadline)
				.monospacedDigit()
				.foregroundStyle(isBad ? palette.critical : palette.good)
		}
		.padding(.vertical, 9)
	}

	// MARK: - Unplanned

	@ViewBuilder
	private var unplannedContent: some View {
		if summary.unplanned.isEmpty {
			emptyCard("Everything you logged settled something you'd planned.")
		} else {
			StatTile(
				label: "Total",
				value: summary.unplannedTotal.money,
				accent: palette.warning,
				caption: "\(summary.unplanned.count) transaction\(summary.unplanned.count == 1 ? "" : "s")"
			)

			Card(subtitle: "Tap one to link it to something you planned") {
				VStack(spacing: 0) {
					ForEach(summary.unplanned) { transaction in
						NavigationLink {
							LogTransactionView(editing: transaction)
						} label: {
							TransactionRow(transaction: transaction, showsDate: true)
						}
						.buttonStyle(.plain)

						if transaction.persistentModelID != summary.unplanned.last?.persistentModelID {
							Divider().background(theme.fgColour.opacity(0.12))
						}
					}
				}
			}
		}
	}

	// MARK: - Shared

	private func lineCard(title: String, lines: [ReconciliationService.Line]) -> some View {
		Card(title: title) {
			VStack(spacing: 0) {
				ForEach(lines) { line in
					NavigationLink {
						if let existing = line.actuals.first {
							LogTransactionView(editing: existing)
						} else {
							LogTransactionView(prefill: line.event)
						}
					} label: {
						ScheduledEventRow(
							event: line.event,
							isSettled: line.hasActuals,
							actualAmount: line.hasActuals ? line.actualAmount : nil
						)
					}
					.buttonStyle(.plain)

					if line.id != lines.last?.id {
						Divider().background(theme.fgColour.opacity(0.12))
					}
				}
			}
		}
	}

	private func emptyCard(_ message: String) -> some View {
		Card {
			Text(message)
				.font(.callout)
				.foregroundStyle(theme.fgColour.opacity(0.65))
		}
	}
}
