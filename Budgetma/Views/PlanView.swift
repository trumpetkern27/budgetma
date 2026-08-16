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
	@Query private var amendments: [ScheduleAmendment]
	@Query private var suspensions: [ScheduleSuspension]
	@Query private var transactions: [Transaction]

	@AppStorage("planHorizonCount") private var horizonCount: Int = 1
	@AppStorage("planHorizonUnit") private var horizonUnitRaw: String = DateWindow.Unit.year.rawValue

	@State private var projection: Projection?
	@State private var isComputing = false
	@State private var cachedRecommendations: [RecommendationEngine.Recommendation] = []
	/// observed so silencing a recommendation elsewhere updates this card
	@AppStorage(DismissedRecommendations.key) private var dismissedRaw: String = "[]"

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
			goals: goals,
			amendments: amendments,
			suspensions: suspensions
		)
	}

	/// changes whenever anything the projection depends on changes, so the
	/// async recompute refires on edits as well as on horizon changes

	/// recommendations depend on logged actuals, which the projection signature
	/// deliberately ignores
	private var recommendationSignature: String {
		"\(transactions.count)|\(transactions.reduce(Decimal(0)) { $0 + $1.amount })|\(amendmentSignature)"
	}

	/// amendments change what an occurrence is worth without changing the item's
	/// own fields, so the snapshot signature alone can't see them
	private var amendmentSignature: String {
		let changes = amendments
			.map { "\($0.effectiveFrom.timeIntervalSince1970)|\($0.amount)" }
			.joined(separator: ",")
		let paused = suspensions
			.map { "\($0.from.timeIntervalSince1970)|\($0.until?.timeIntervalSince1970 ?? 0)" }
			.joined(separator: ",")
		return changes + "/" + paused
	}

	private var inputSignature: String {
		let items = snapshots
			.map { "\($0.name)|\($0.amount)|\($0.start.timeIntervalSince1970)|\($0.kind.rawValue)|\($0.rule == nil ? 0 : 1)" }
			.joined(separator: ";")
		return "\(horizonCount)\(horizonUnitRaw)|\(overrides.count)|\(amendmentSignature)|\(items)"
	}

	/// a cheap look-ahead so the card can say something specific without running
	/// the whole engine on every Plan render
	private var summaryRecommendations: [RecommendationEngine.Recommendation] {
		let end = Date.now
		let start = Calendar.current.date(byAdding: .month, value: -12, to: end) ?? end
		let events = CashflowProjector.events(
			for: snapshots,
			overrides: OverrideIndex(overrides),
			in: start..<end
		)
		return RecommendationEngine.recommendations(events: events, transactions: transactions)
	}

	/// silenced ones must not be counted here either, or the card keeps nagging
	/// about something you've explicitly dismissed
	private var visibleRecommendations: [RecommendationEngine.Recommendation] {
		let dismissed = DismissedRecommendations.all
		return cachedRecommendations.filter { !dismissed.contains($0.id) }
	}

	private var recommendationCount: Int { visibleRecommendations.count }
	private var topRecommendationTitle: String? { visibleRecommendations.first?.title }

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				planSetup
				recommendationsEntry
				header

				if snapshots.isEmpty {
					emptyState
				} else {
					summaryTiles
					curveCard
					adjustEntry
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
		.task(id: recommendationSignature) { cachedRecommendations = summaryRecommendations }
	}

	// MARK: - Sections

	/* --- what you're planning ---
	 * these used to sit at the bottom of Home, which put "edit the plan" on the
	 * screen whose job is "what's happening this period". the plan and the
	 * projection it produces belong together: this is the tab where you decide
	 * what the future looks like.
	 */
	private var planSetup: some View {
		Card(title: "What you're planning", subtitle: "The inputs behind every projection below") {
			VStack(spacing: 0) {
				setupRow(
					emoji: "💰",
					label: "Expected income",
					count: expectedIncomes.count
				) { IncomeView() }

				Divider().background(theme.fgColour.opacity(0.15))

				setupRow(
					emoji: "💸",
					label: "Expected expenses",
					count: expectedExpenses.count
				) { ExpenseView(focus: .transactions) }

				Divider().background(theme.fgColour.opacity(0.15))

				setupRow(
					emoji: "✉️",
					label: "Envelopes",
					count: envelopes.count
				) { ExpenseView(focus: .envelopes) }
			}
		}
	}

	/* --- worth a look ---
	 * a summary that opens the full list. it lives here because Plan is where
	 * you decide what the future looks like, and every recommendation is
	 * literally "your plan disagrees with your life".
	 */
	@ViewBuilder
	private var recommendationsEntry: some View {
		let count = recommendationCount

		NavigationLink {
			RecommendationsView()
		} label: {
			Card {
				HStack(spacing: 12) {
					Text("💡")
						.font(.title3)

					VStack(alignment: .leading, spacing: 3) {
						Text(count == 0 ? "Nothing to flag" : "\(count) worth a look")
							.font(.headline)
						Text(
							count == 0
								? "Your plan matches what's happening"
								: topRecommendationTitle ?? "Where your plan and reality disagree"
						)
						.font(.caption)
						.foregroundStyle(theme.fgColour.opacity(0.6))
						.lineLimit(1)
					}

					Spacer()

					Image(systemName: "chevron.right")
						.font(.caption)
						.foregroundStyle(theme.fgColour.opacity(0.4))
				}
			}
		}
		.buttonStyle(.plain)
	}

	private func setupRow<Destination: View>(
		emoji: String,
		label: String,
		count: Int,
		@ViewBuilder destination: @escaping () -> Destination
	) -> some View {
		NavigationLink(destination: destination) {
			HStack(spacing: 12) {
				Text(emoji)
				Text(label)
					.font(.subheadline)
				Spacer()
				Text("\(count)")
					.font(.subheadline)
					.monospacedDigit()
					.foregroundStyle(theme.fgColour.opacity(0.5))
				Image(systemName: "chevron.right")
					.font(.caption)
					.foregroundStyle(theme.fgColour.opacity(0.4))
			}
			.padding(.vertical, 11)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}

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


	/* the trade-off screen. it sits under the curve on purpose: you look at the
	 * projection, don't like it, and the next thing you want is the ability to
	 * change several things at once until you do.
	 */
	private var adjustEntry: some View {
		NavigationLink {
			PlanAdjustView(horizon: horizon)
		} label: {
			Card {
				HStack(spacing: 12) {
					Text("⚖️")
						.font(.title2)
					VStack(alignment: .leading, spacing: 3) {
						Text("Adjust the plan")
							.font(.headline)
						Text("Everything you're committed to, priced and editable in one list")
							.font(.caption)
							.foregroundStyle(theme.fgColour.opacity(0.6))
							.lineLimit(2)
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
