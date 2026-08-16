import SwiftUI
import SwiftData

/* --- Budget ---
 * the window view: what you planned, against what actually happened
 *
 * the window is arbitrary and pageable -- two weeks is the default because
 * that's how often a lot of people get paid, but nothing here knows or cares
 * what a month is.
 */
@available(iOS 26, *)
struct BudgetView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context

	@Query private var expectedIncomes: [ExpectedIncome]
	@Query private var expectedExpenses: [ExpectedExpense]
	@Query private var envelopes: [Envelope]
	@Query private var goals: [Goal]
	@Query private var overrides: [OccurrenceOverride]
	@Query private var transactions: [Transaction]

	@AppStorage("budgetWindowCount") private var windowCount: Int = 2
	@AppStorage("budgetWindowUnit") private var windowUnitRaw: String = DateWindow.Unit.week.rawValue
	@State private var page: Int = 0

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	private var window: DateWindow {
		DateWindow(
			count: windowCount,
			unit: DateWindow.Unit(rawValue: windowUnitRaw) ?? .week
		)
		.aligned()
		.offset(by: page)
	}

	private var windowBinding: Binding<DateWindow> {
		Binding(
			get: { window },
			set: { windowCount = $0.count; windowUnitRaw = $0.unit.rawValue }
		)
	}

	private var range: Range<Date> { window.range() }

	private var events: [ScheduledEvent] {
		CashflowProjector.events(
			for: BudgetService.snapshots(
				incomes: expectedIncomes,
				expenses: expectedExpenses,
				envelopes: envelopes,
				goals: goals
			),
			overrides: OverrideIndex(overrides),
			in: range
		)
	}

	private var summary: ReconciliationService.Summary {
		ReconciliationService.summary(
			events: events,
			actuals: transactions.filter { range.contains($0.date) || $0.occurrenceDate != nil },
			in: range
		)
	}

	/// expected vs actual, rolled up by category name
	private var categoryRows: [ExpectedVsActualChart.Row] {
		let outflows = summary.lines.filter { !$0.isInflow }
		let grouped = Dictionary(grouping: outflows) { $0.name }
		return grouped
			.map { name, lines in
				ExpectedVsActualChart.Row(
					label: name,
					emoji: lines.first?.emoji ?? "💸",
					expected: lines.reduce(0) { $0 + $1.expectedAmount },
					actual: lines.reduce(0) { $0 + $1.actualAmount }
				)
			}
			.sorted { $0.expected > $1.expected }
			.prefix(8)
			.map { $0 }
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				windowHeader
				summaryTiles

				if !categoryRows.isEmpty {
					Card(title: "Planned vs actual", subtitle: "By item, this window") {
						ExpectedVsActualChart(rows: categoryRows)
					}
				}

				scheduleCard

				if !summary.unplanned.isEmpty {
					unplannedCard
				}

				if !envelopes.isEmpty {
					envelopeCard
				}
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.chartPalette(for: theme.bgColour)
		.navigationTitle("Budget")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				NavigationLink {
					LogTransactionView()
				} label: {
					Image(systemName: "plus.circle.fill")
				}
			}
		}
	}

	// MARK: - Header

	private var windowHeader: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Button { page -= 1 } label: {
					Image(systemName: "chevron.left")
				}

				Spacer()

				VStack(spacing: 2) {
					Text(range.lowerBound.formatted(.dateTime.month(.abbreviated).day()) + " – "
						 + range.upperBound.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))
						.font(.headline)
					if page != 0 {
						Button("Back to today") { page = 0 }
							.font(.caption2)
					}
				}

				Spacer()

				Button { page += 1 } label: {
					Image(systemName: "chevron.right")
				}
			}
			.tint(theme.fgColour)

			WindowPicker(
				window: windowBinding,
				presets: [
					DateWindow(count: 1, unit: .week),
					DateWindow(count: 2, unit: .week),
					DateWindow(count: 1, unit: .month),
					DateWindow(count: 3, unit: .month)
				]
			)
		}
	}

	@ViewBuilder
	private var summaryTiles: some View {
		let expectedNet = summary.expectedNet
		let actualNet = summary.actualNet
		// drift is only honest against the part of the window that's happened
		let asOf = min(Date.now, range.upperBound)
		let expectedSoFar = summary.expectedNet(through: asOf)
		let drift = actualNet - expectedSoFar
		let isPast = range.upperBound <= Date.now

		VStack(spacing: 12) {
			HStack(alignment: .top, spacing: 12) {
				StatTile(
					label: "Planned net",
					value: expectedNet.moneySigned,
					accent: expectedNet >= 0 ? palette.good : palette.critical,
					caption: "\(summary.expectedInflow.moneyCompact) in · \(summary.expectedOutflow.moneyCompact) out"
				)
				StatTile(
					label: "Actual net",
					value: actualNet.moneySigned,
					accent: actualNet >= 0 ? palette.good : palette.critical,
					caption: "\(summary.actualInflow.moneyCompact) in · \(summary.actualOutflow.moneyCompact) out"
				)
			}

			HStack(alignment: .top, spacing: 12) {
				StatTile(
					label: isPast ? "Drift" : "Drift so far",
					value: drift.moneySigned,
					accent: drift >= 0 ? palette.good : palette.critical,
					caption: isPast
						? (drift >= 0 ? "Better than planned" : "Worse than planned")
						: "vs \(expectedSoFar.moneySigned) planned by now",
					systemImage: drift >= 0 ? "arrow.up.right" : "arrow.down.right"
				)
				StatTile(
					label: "Unplanned",
					value: summary.unplannedTotal.moneyCompact,
					accent: summary.unplanned.isEmpty ? theme.fgColour : palette.warning,
					caption: "\(summary.unplanned.count) transaction\(summary.unplanned.count == 1 ? "" : "s")"
				)
			}
		}
	}

	// MARK: - Schedule

	private var scheduleCard: some View {
		Card(title: "This window", subtitle: "Tap anything to log what really happened") {
			if summary.lines.isEmpty {
				Text("Nothing scheduled in this window.")
					.font(.callout)
					.foregroundStyle(theme.fgColour.opacity(0.6))
			} else {
				VStack(spacing: 0) {
					ForEach(summary.lines) { line in
						NavigationLink {
							if let existing = line.actuals.first {
								LogTransactionView(editing: existing)
							} else {
								LogTransactionView(prefill: line.event)
							}
						} label: {
							lineRow(line)
						}
						.buttonStyle(.plain)
						.contextMenu { overrideMenu(for: line) }

						if line.id != summary.lines.last?.id {
							Divider().background(theme.fgColour.opacity(0.15))
						}
					}
				}
			}
		}
	}

	private func lineRow(_ line: ReconciliationService.Line) -> some View {
		let status = line.status()
		let (color, icon) = style(for: status)

		return HStack(spacing: 10) {
			Text(line.emoji)
				.font(.body)

			VStack(alignment: .leading, spacing: 2) {
				Text(line.name)
					.font(.subheadline)
					.lineLimit(1)
				HStack(spacing: 5) {
					Image(systemName: icon)
						.font(.system(size: 9))
						.foregroundStyle(color)
					Text(statusLabel(status))
						.font(.caption2)
						.foregroundStyle(color)
					Text("· \(line.date.formatted(.dateTime.month(.abbreviated).day()))")
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.5))
				}
			}

			Spacer()

			VStack(alignment: .trailing, spacing: 2) {
				Text(line.expectedAmount.money)
					.font(.subheadline)
					.monospacedDigit()
					.foregroundStyle(line.isInflow ? palette.inflow : theme.fgColour)

				if line.hasActuals {
					Text(line.actualAmount.money)
						.font(.caption2)
						.monospacedDigit()
						.foregroundStyle(color)
				}
			}
		}
		.padding(.vertical, 10)
		.contentShape(Rectangle())
	}

	@ViewBuilder
	private func overrideMenu(for line: ReconciliationService.Line) -> some View {
		if let sourceID = line.sourceID,
		   let expected = context.model(for: sourceID) as? ExpectedTransaction {
			Button {
				BudgetService(context: context).setOverride(
					for: expected,
					on: line.occurrenceDate,
					isSkipped: true
				)
			} label: {
				Label("Skip this occurrence", systemImage: "calendar.badge.minus")
			}

			if overrideExists(for: expected, on: line.occurrenceDate) {
				Button {
					BudgetService(context: context).setOverride(
						for: expected,
						on: line.occurrenceDate
					)
				} label: {
					Label("Clear exception", systemImage: "arrow.uturn.backward")
				}
			}
		}
	}

	private func overrideExists(for expected: ExpectedTransaction, on date: Date) -> Bool {
		BudgetService(context: context).override(for: expected, on: date) != nil
	}

	// MARK: - Unplanned

	private var unplannedCard: some View {
		Card(
			title: "Unplanned",
			subtitle: "Real spending that didn't settle anything you'd planned"
		) {
			VStack(spacing: 0) {
				ForEach(summary.unplanned) { transaction in
					NavigationLink {
						LogTransactionView(editing: transaction)
					} label: {
						HStack {
							Text(transaction.category?.emoji ?? "❓")
							VStack(alignment: .leading, spacing: 2) {
								Text(transaction.name)
									.font(.subheadline)
									.lineLimit(1)
								Text(transaction.date.formatted(.dateTime.month(.abbreviated).day()))
									.font(.caption2)
									.foregroundStyle(theme.fgColour.opacity(0.5))
							}
							Spacer()
							Text(transaction.amount.money)
								.font(.subheadline)
								.monospacedDigit()
								.foregroundStyle(transaction is Income ? palette.inflow : palette.warning)
						}
						.padding(.vertical, 8)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
			}
		}
	}

	// MARK: - Envelopes

	private var envelopeCard: some View {
		Card(title: "Envelopes", subtitle: "What's left in each one right now") {
			VStack(spacing: 14) {
				ForEach(envelopes) { envelope in
					envelopeRow(envelope)
				}
			}
		}
	}

	private func envelopeRow(_ envelope: Envelope) -> some View {
		let expenses = transactions.compactMap { $0 as? Expense }
		let period = EnvelopeLedger.currentPeriod(for: envelope, expenses: expenses)

		return VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text("\(envelope.category?.emoji ?? "✉️") \(envelope.name)")
					.font(.subheadline)
				Spacer()
				if let period {
					Text("\(period.available.money) left")
						.font(.caption)
						.monospacedDigit()
						.foregroundStyle(period.isOverspent ? palette.critical : palette.good)
				} else {
					Text("Not funded yet")
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.5))
				}
			}

			if let period {
				ProgressView(value: period.utilisation)
					.tint(period.isOverspent ? palette.critical : palette.inflow)

				HStack {
					Text("\(period.spent.moneyCompact) of \(period.budget.moneyCompact)")
					if period.carriedIn > 0 {
						Text("· \(period.carriedIn.moneyCompact) carried over")
					}
					Spacer()
				}
				.font(.caption2)
				.foregroundStyle(theme.fgColour.opacity(0.5))
			}
		}
	}

	// MARK: - Status presentation

	private func style(for status: ReconciliationService.LineStatus) -> (Color, String) {
		switch status {
		case .upcoming: return (theme.fgColour.opacity(0.5), "clock")
		case .outstanding: return (palette.warning, "exclamationmark.circle")
		case .settled: return (palette.good, "checkmark.circle.fill")
		case .over: return (palette.critical, "arrow.up.circle.fill")
		case .under: return (palette.inflow, "arrow.down.circle.fill")
		}
	}

	private func statusLabel(_ status: ReconciliationService.LineStatus) -> String {
		switch status {
		case .upcoming: return "Upcoming"
		case .outstanding: return "Not logged"
		case .settled: return "Settled"
		case .over: return "Over"
		case .under: return "Under"
		}
	}
}
