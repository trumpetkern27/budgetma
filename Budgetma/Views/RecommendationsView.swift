import SwiftUI
import SwiftData

/* --- Recommendations ---
 * where your plan and your actual life have drifted apart
 *
 * every other screen answers "how am I doing against the plan". this one asks
 * whether the plan is right, which is a question you can only answer by looking
 * across many windows at once. see RecommendationEngine for why nothing is ever
 * flagged from a single occurrence.
 */
@available(iOS 26, *)
struct RecommendationsView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context

	@Query private var expectedIncomes: [ExpectedIncome]
	@Query private var expectedExpenses: [ExpectedExpense]
	@Query private var envelopes: [Envelope]
	@Query private var goals: [Goal]
	@Query private var overrides: [OccurrenceOverride]
	@Query private var amendments: [ScheduleAmendment]
	@Query private var transactions: [Transaction]

	/// how far back to look for patterns
	@AppStorage("recommendationLookbackMonths") private var lookbackMonths: Int = 12

	@State private var recommendations: [RecommendationEngine.Recommendation] = []
	/// mirrored into @AppStorage so dismissing one redraws the list immediately
	@AppStorage(DismissedRecommendations.key) private var dismissedRaw: String = "[]"
	@State private var showingDismissed = false

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	private var range: Range<Date> {
		let end = Date.now
		let start = Calendar.current.date(byAdding: .month, value: -lookbackMonths, to: end) ?? end
		return start..<end
	}

	private var dismissed: Set<String> { DismissedRecommendations.all }

	private var active: [RecommendationEngine.Recommendation] {
		recommendations.filter { !dismissed.contains($0.id) }
	}

	private var silenced: [RecommendationEngine.Recommendation] {
		recommendations.filter { dismissed.contains($0.id) }
	}

	private var signature: String {
		"\(lookbackMonths)|\(transactions.count)|\(expectedIncomes.count)|\(expectedExpenses.count)"
			+ "|\(envelopes.count)|\(overrides.count)|\(amendments.count)"
			+ "|\(transactions.reduce(Decimal(0)) { $0 + $1.amount })"
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				lookbackPicker

				if active.isEmpty {
					emptyState
				} else {
					ForEach(active) { recommendation in
						card(recommendation)
					}
				}

				if !silenced.isEmpty {
					silencedSection
				}

				footnote
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.chartPalette(for: theme.bgColour)
		.navigationTitle("Worth a look")
		.navigationBarTitleDisplayMode(.inline)
		.task(id: signature) { recompute() }
	}

	// MARK: - Compute

	private func recompute() {
		let events = CashflowProjector.events(
			for: BudgetService.snapshots(
				incomes: expectedIncomes,
				expenses: expectedExpenses,
				envelopes: envelopes,
				goals: goals,
				amendments: amendments
			),
			overrides: OverrideIndex(overrides),
			in: range
		)

		recommendations = RecommendationEngine.recommendations(
			events: events,
			transactions: transactions
		)
	}

	// MARK: - Pieces

	private var lookbackPicker: some View {
		HStack {
			Text("Looking back")
				.font(.caption)
				.foregroundStyle(theme.fgColour.opacity(0.6))
			Spacer()
			Picker("Lookback", selection: $lookbackMonths) {
				Text("3m").tag(3)
				Text("6m").tag(6)
				Text("1y").tag(12)
				Text("2y").tag(24)
			}
			.pickerStyle(.segmented)
			.frame(width: 200)
		}
	}

	private var emptyState: some View {
		Card(title: silenced.isEmpty ? "Nothing to flag" : "Nothing new to flag") {
			VStack(alignment: .leading, spacing: 8) {
				Text(
					silenced.isEmpty
						? "Your plan matches what's actually happening, as far as the last \(lookbackMonths) months can tell."
						: "Everything currently detected has been silenced."
				)
				.font(.callout)
				.foregroundStyle(theme.fgColour.opacity(0.7))

				Text("Log a few more months and this gets sharper — nothing is flagged from a single occurrence.")
					.font(.caption2)
					.foregroundStyle(theme.fgColour.opacity(0.5))
			}
		}
	}

	/* silenced ones stay visible but folded away. hiding them completely would
	 * make a dismissal irreversible in practice -- you'd have to remember what
	 * you'd silenced in order to go looking for it.
	 */
	private var silencedSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			Button {
				withAnimation(.easeInOut(duration: 0.18)) { showingDismissed.toggle() }
			} label: {
				HStack(spacing: 6) {
					Image(systemName: showingDismissed ? "chevron.down" : "chevron.right")
						.font(.caption2)
					Text("Silenced (\(silenced.count))")
						.font(.caption.weight(.semibold))
					Spacer()
					if showingDismissed {
						Button("Restore all") {
							DismissedRecommendations.restoreAll()
						}
						.font(.caption2)
					}
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.foregroundStyle(theme.fgColour.opacity(0.6))

			if showingDismissed {
				ForEach(silenced) { recommendation in
					HStack(spacing: 10) {
						Text(recommendation.title)
							.font(.caption)
							.foregroundStyle(theme.fgColour.opacity(0.55))
							.lineLimit(2)
						Spacer()
						Button {
							DismissedRecommendations.restore(recommendation.id)
						} label: {
							Image(systemName: "arrow.uturn.backward")
								.font(.caption2)
						}
						.buttonStyle(.plain)
						.foregroundStyle(theme.fgColour.opacity(0.6))
					}
					.padding(.vertical, 6)
				}
			}
		}
	}

	private func card(_ recommendation: RecommendationEngine.Recommendation) -> some View {
		Card {
			VStack(alignment: .leading, spacing: 10) {
				HStack(alignment: .top, spacing: 8) {
					Image(systemName: icon(for: recommendation))
						.font(.caption)
						.foregroundStyle(colour(for: recommendation.severity))

					VStack(alignment: .leading, spacing: 4) {
						Text(recommendation.title)
							.font(.subheadline.weight(.semibold))

						Text(recommendation.detail)
							.font(.caption)
							.foregroundStyle(theme.fgColour.opacity(0.7))
							.fixedSize(horizontal: false, vertical: true)
					}
				}

				HStack(spacing: 10) {
					// the number that decides whether this is worth acting on
					Text("≈\(recommendation.yearlyImpact.moneyCompact)/yr")
						.font(.caption2.weight(.semibold))
						.padding(.horizontal, 7)
						.padding(.vertical, 3)
						.overlay {
							Capsule().stroke(colour(for: recommendation.severity).opacity(0.6), lineWidth: 1)
						}
						.foregroundStyle(colour(for: recommendation.severity))

					Text("\(recommendation.sampleSize) observations")
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.5))

					Spacer()

					Button {
						withAnimation(.easeInOut(duration: 0.2)) {
							DismissedRecommendations.dismiss(recommendation.id)
						}
					} label: {
						Label("Silence", systemImage: "bell.slash")
							.font(.caption2)
							.labelStyle(.iconOnly)
							.padding(6)
							.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.foregroundStyle(theme.fgColour.opacity(0.5))
				}

				if let suggestion = recommendation.suggestion {
					Divider().background(theme.fgColour.opacity(0.15))

					if recommendation.kind == .amountDrift, canApply(recommendation) {
						Button {
							apply(recommendation)
						} label: {
							HStack(spacing: 6) {
								Image(systemName: "wand.and.stars")
									.font(.caption2)
								Text(suggestion)
									.font(.caption.weight(.semibold))
								Spacer()
							}
							.padding(.vertical, 8)
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					} else {
						HStack(spacing: 6) {
							Image(systemName: "lightbulb")
								.font(.caption2)
							Text(suggestion)
								.font(.caption)
							Spacer()
						}
						.foregroundStyle(theme.fgColour.opacity(0.75))
						.padding(.vertical, 4)
					}
				}
			}
		}
	}

	private var footnote: some View {
		Text("Only repeated differences are flagged. A single month over budget is noise; the same overspend six times is a number that needs changing.")
			.font(.caption2)
			.foregroundStyle(theme.fgColour.opacity(0.45))
			.fixedSize(horizontal: false, vertical: true)
	}

	// MARK: - Applying

	private func canApply(_ recommendation: RecommendationEngine.Recommendation) -> Bool {
		guard let sourceID = recommendation.sourceID else { return false }
		return context.model(for: sourceID) is ExpectedTransaction
	}

	/* applying a recommendation writes an *amendment*, never a base-amount edit.
	 * the whole point is that the old figure was right at the time and the new
	 * one is right from now on -- rewriting history here would destroy the very
	 * evidence the recommendation was derived from.
	 */
	private func apply(_ recommendation: RecommendationEngine.Recommendation) {
		guard
			let sourceID = recommendation.sourceID,
			let expected = context.model(for: sourceID) as? ExpectedTransaction,
			let amount = recommendation.suggestedAmount
		else { return }

		context.insert(
			ScheduleAmendment(
				expected: expected,
				effectiveFrom: .now,
				amount: amount,
				note: "Adjusted to match actuals"
			)
		)
		try? context.save()

		/* silence it too, or acting on the advice never makes it go away.
		 * the amendment applies from today forward, but the *past* occurrences
		 * keep their old planned figure by design -- which is exactly the
		 * evidence the recommendation was derived from, so it would be
		 * re-detected on every visit forever.
		 */
		DismissedRecommendations.dismiss(recommendation.id)
		recompute()
	}

	// MARK: - Presentation

	private func icon(for recommendation: RecommendationEngine.Recommendation) -> String {
		switch recommendation.kind {
		case .amountDrift: return "chart.line.uptrend.xyaxis"
		case .unplannedPattern: return "repeat"
		}
	}

	private func colour(for severity: RecommendationEngine.Severity) -> Color {
		switch severity {
		case .high: return palette.critical
		case .medium: return palette.warning
		case .low: return theme.fgColour.opacity(0.6)
		}
	}
}
