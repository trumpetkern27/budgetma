import SwiftUI
import Charts

/* --- Expected vs actual bars ---
 * the reconciliation view, by category
 *
 * two series again (planned / actual). same validated pair as the projection
 * comparison, for the same reason: they're the two things being told apart.
 */
@available(iOS 26, *)
struct ExpectedVsActualChart: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.chartPalette) private var palette

	struct Row: Identifiable {
		let id: String
		let label: String
		let emoji: String
		let expected: Decimal
		let actual: Decimal

		init(label: String, emoji: String, expected: Decimal, actual: Decimal) {
			self.id = label
			self.label = label
			self.emoji = emoji
			self.expected = expected
			self.actual = actual
		}
	}

	let rows: [Row]
	var height: CGFloat = 200

	private struct Point: Identifiable {
		let id: String
		let label: String
		let series: String
		let amount: Double
	}

	private var points: [Point] {
		rows.flatMap { row in
			[
				Point(id: "e-\(row.id)", label: "\(row.emoji) \(row.label)", series: "Planned", amount: row.expected.doubleValue),
				Point(id: "a-\(row.id)", label: "\(row.emoji) \(row.label)", series: "Actual", amount: row.actual.doubleValue)
			]
		}
	}

	var body: some View {
		if rows.isEmpty {
			Text("Nothing to compare yet.")
				.font(.caption)
				.foregroundStyle(theme.fgColour.opacity(0.5))
				.frame(maxWidth: .infinity, minHeight: 80)
		} else {
			Chart(points) { point in
				BarMark(
					x: .value("Amount", point.amount),
					y: .value("Category", point.label)
				)
				.foregroundStyle(by: .value("Series", point.series))
				.position(by: .value("Series", point.series))
				.cornerRadius(4)
			}
			.chartForegroundStyleScale([
				"Planned": palette.baseline,
				"Actual": palette.candidate
			])
			.chartLegend(position: .top, alignment: .leading, spacing: 12)
			.chartXAxis {
				AxisMarks(values: .automatic(desiredCount: 3)) { value in
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
			.chartYAxis {
				AxisMarks(position: .leading) { _ in
					AxisValueLabel()
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.8))
				}
			}
			.frame(height: max(height, CGFloat(rows.count) * 44))
		}
	}
}
