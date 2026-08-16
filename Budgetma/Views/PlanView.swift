import SwiftUI
import SwiftData

/* --- Plan ---
 * the long view: where the money goes over an arbitrary horizon
 *
 * this is the screen the app exists for. a monthly surplus figure is a lie when
 * rent is monthly and pay is biweekly -- they drift against each other all year.
 * so nothing here is monthly. you pick a horizon (a day, a decade), and the
 * curve tells you what actually happens.
 */
@available(iOS 26, *)
struct PlanView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context

	@Query private var expectedIncomes: [ExpectedIncome]
	@Query private var expectedExpenses: [ExpectedExpense]
	@Query private var envelopes: [Envelope]
	@Query private var goals: [Goal]
	@Query private var overrides: [OccurrenceOverride]

	@AppStorage("planHorizonCount") private var horizonCount: Int = 1
	@AppStorage("planHorizonUnit") private var horizonUnitRaw: String = DateWindow.Unit.year.rawValue

	@State private var projection: Projection?
	@State private var isComputing = false

	private var horizon: DateWindow {
		get {
			DateWindow(
				count: horizonCount,
				unit: DateWindow.Unit(rawValue: horizonUnitRaw) ?? .year
			)
		}
		nonmutating set {
			horizonCount = newValue.count
			horizonUnitRaw = newValue.unit.rawValue
		}
	}

	private var horizonBinding: Binding<DateWindow> {
		Binding(get: { horizon }, set: { horizon = $0 })
	}

	private var snapshots: [ScheduleSnapshot] {
		BudgetService.snapshots(
			incomes: expectedIncomes,
			expenses: expectedExpenses,
			envelopes: envelopes,
			goals: goals
		)
	}

	/// changes whenever anything the projection depends on changes, so the
	/// async recompute refires on edits as well as on horizon changes
	private var inputSignature: String {
		let items = snapshots
			.map { "\($0.name)|\($0.amount)|\($0.start.timeIntervalSince1970)|\($0.kind.rawValue)|\($0.rule == nil ? 0 : 1)" }
			.joined(separator: ";")
		return "\(horizonCount)\(horizonUnitRaw)|\(overrides.count)|\(items)"
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				header

				if snapshots.isEmpty {
					emptyState
				} else {
					summaryTiles
					curveCard
					flowCard
					affordabilityEntry
				}
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.chartPalette(for: theme.bgColour)
		.navigationTitle("Plan")
		.navigationBarTitleDisplayMode(.inline)
		.task(id: inputSignature) { await recompute() }
	}

	// MARK: - Sections

	private var header: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Projection horizon")
				.font(.headline)

			WindowPicker(
				window: horizonBinding,
				presets: [
					DateWindow(count: 1, unit: .month),
					DateWindow(count: 3, unit: .month),
					DateWindow(count: 6, unit: .month),
					DateWindow(count: 1, unit: .year),
					DateWindow(count: 5, unit: .year)
				]
			)
		}
	}

	private var emptyState: some View {
		Card(title: "Nothing to project yet") {
			Text("Add some expected income and expenses and this becomes a picture of the next \(horizon.label).")
				.font(.callout)
				.foregroundStyle(theme.fgColour.opacity(0.7))
		}
	}

	@ViewBuilder
	private var summaryTiles: some View {
		let palette = ChartPalette.forSurface(theme.bgColour)

		if let projection {
			HStack(alignment: .top, spacing: 12) {
				StatTile(
					label: "Net over \(horizon.label)",
					value: projection.net.moneySigned,
					accent: projection.net >= 0 ? palette.good : palette.critical,
					caption: projection.net >= 0 ? "You come out ahead" : "You fall behind",
					systemImage: projection.net >= 0 ? "arrow.up.right" : "arrow.down.right"
				)

				StatTile(
					label: "Lowest point",
					value: (projection.trough?.cumulative ?? 0).money,
					accent: (projection.trough?.cumulative ?? 0) < 0 ? palette.critical : theme.fgColour,
					caption: projection.trough.map {
						"Around \($0.start.formatted(.dateTime.month(.abbreviated).year()))"
					} ?? "—",
					systemImage: "arrow.down.to.line"
				)
			}

			HStack(alignment: .top, spacing: 12) {
				StatTile(
					label: "Coming in",
					value: projection.totalInflow.moneyCompact,
					accent: palette.inflow,
					caption: "Across \(projection.buckets.count) \(projection.granularity.periodNoun)\(projection.buckets.count == 1 ? "" : "s")"
				)
				StatTile(
					label: "Going out",
					value: projection.totalOutflow.moneyCompact,
					accent: palette.outflow,
					caption: "Includes envelopes & goals"
				)
			}
		}
	}

	@ViewBuilder
	private var curveCard: some View {
		Card(
			title: "Running balance",
			subtitle: "Cumulative net over \(horizon.label) · drag to inspect"
		) {
			if let projection, !projection.buckets.isEmpty {
				ProjectionChart(projection: projection)
			} else {
				computingPlaceholder(height: 220)
			}
		}
	}

	@ViewBuilder
	private var flowCard: some View {
		Card(
			title: "In vs out",
			subtitle: projection.map { "Totals per \($0.granularity.periodNoun)" } ?? "Per period"
		) {
			if let projection, !projection.buckets.isEmpty {
				FlowChart(projection: projection)
			} else {
				computingPlaceholder(height: 180)
			}
		}
	}

	private var affordabilityEntry: some View {
		NavigationLink {
			AffordabilityView(horizon: horizon)
		} label: {
			Card {
				HStack(spacing: 12) {
					Text("🛒")
						.font(.title2)
					VStack(alignment: .leading, spacing: 3) {
						Text("Can I afford it?")
							.font(.headline)
						Text("Test a purchase against this projection")
							.font(.caption)
							.foregroundStyle(theme.fgColour.opacity(0.6))
					}
					Spacer()
					Image(systemName: "chevron.right")
						.font(.caption)
						.foregroundStyle(theme.fgColour.opacity(0.5))
				}
			}
		}
		.buttonStyle(.plain)
	}

	private func computingPlaceholder(height: CGFloat) -> some View {
		HStack {
			Spacer()
			if isComputing {
				ProgressView()
					.tint(theme.fgColour)
			} else {
				Text("No data in this range.")
					.font(.caption)
					.foregroundStyle(theme.fgColour.opacity(0.5))
			}
			Spacer()
		}
		.frame(height: height)
	}

	// MARK: - Compute

	/// projections over long horizons can be genuinely expensive (a daily rule
	/// across a century is a lot of dates), so they run off the main actor.
	/// snapshots and the override index are Sendable value types precisely so
	/// this hop is legal.
	private func recompute() async {
		let schedules = snapshots
		guard !schedules.isEmpty else {
			projection = nil
			return
		}

		let index = OverrideIndex(overrides)
		let range = horizon.range()

		isComputing = true
		projection = await CashflowProjector.projectConcurrently(
			for: schedules,
			overrides: index,
			in: range
		)
		isComputing = false
	}
}
