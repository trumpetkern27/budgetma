import SwiftUI
import Charts

/* --- Projection chart ---
 * the hero: cumulative net over an arbitrary horizon
 *
 * one series, so no legend -- the title names it. the zero line is the thing
 * that matters, so it's drawn explicitly, and the trough gets a marker because
 * "the worst it ever gets" is the number the whole affordability question turns
 * on.
 *
 * an optional second series overlays the same curve with a candidate purchase
 * folded in, which is what makes the before/after comparison legible.
 */
@available(iOS 26, *)
struct ProjectionChart: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.chartPalette) private var palette

	let projection: Projection
	/// when present, drawn alongside the baseline as the "with this purchase" line
	var comparison: Projection?
	var comparisonLabel: String = "With purchase"
	var baselineLabel: String = "As things stand"
	var height: CGFloat = 220

	@State private var scrubbed: ProjectionBucket?

	private var series: [ProjectionBucket] { projection.buckets }

	private var trough: ProjectionBucket? {
		(comparison ?? projection).trough
	}

	/// pin the y-range to the data
	///
	/// left to itself Charts rounds out to numbers like -$20k..$40k when the
	/// curve only spans -$113..$21k, which flattens the dip that matters most.
	private var yDomain: ClosedRange<Double> {
		var values = series.map(\.cumulative.doubleValue)
		values += comparison?.buckets.map(\.cumulative.doubleValue) ?? []
		values.append((projection.openingBalance ?? 0).doubleValue)

		guard let low = values.min(), let high = values.max() else { return -1...1 }
		let span = Swift.max(high - low, 1)
		let padding = span * 0.12
		return (low - padding)...(high + padding)
	}

	/// only worth marking the low point if the curve actually dips
	private var showsTrough: Bool {
		guard let trough else { return false }
		let opening = projection.openingBalance ?? 0
		return trough.cumulative < opening
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if comparison != nil {
				legend
			}

			chart
				.frame(height: height)

			if let scrubbed {
				scrubReadout(scrubbed)
			} else if showsTrough, let trough {
				troughReadout(trough)
			}
		}
	}

	// MARK: - Chart

	private var chart: some View {
		Chart {
			// baseline: filled area + line
			ForEach(series) { bucket in
				AreaMark(
					x: .value("Date", bucket.start),
					y: .value("Net", bucket.cumulative.doubleValue)
				)
				.foregroundStyle(
					LinearGradient(
						colors: [palette.baseline.opacity(0.28), palette.baseline.opacity(0.02)],
						startPoint: .top,
						endPoint: .bottom
					)
				)
				.interpolationMethod(.monotone)
			}

			ForEach(series) { bucket in
				LineMark(
					x: .value("Date", bucket.start),
					y: .value("Net", bucket.cumulative.doubleValue),
					series: .value("Series", baselineLabel)
				)
				.foregroundStyle(palette.baseline)
				.lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
				.interpolationMethod(.monotone)
			}

			// candidate overlay
			if let comparison {
				ForEach(comparison.buckets) { bucket in
					LineMark(
						x: .value("Date", bucket.start),
						y: .value("Net", bucket.cumulative.doubleValue),
						series: .value("Series", comparisonLabel)
					)
					.foregroundStyle(palette.candidate)
					.lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 3]))
					.interpolationMethod(.monotone)
				}
			}

			// the line that actually matters
			RuleMark(y: .value("Break even", (projection.openingBalance ?? 0).doubleValue))
				.foregroundStyle(palette.axis.opacity(0.6))
				.lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

			// worst point
			if showsTrough, let trough {
				PointMark(
					x: .value("Date", trough.start),
					y: .value("Net", trough.cumulative.doubleValue)
				)
				.symbolSize(90)
				.foregroundStyle(palette.critical)
			}

			// scrub indicator
			if let scrubbed {
				RuleMark(x: .value("Date", scrubbed.start))
					.foregroundStyle(theme.fgColour.opacity(0.35))
					.lineStyle(StrokeStyle(lineWidth: 1))

				PointMark(
					x: .value("Date", scrubbed.start),
					y: .value("Net", scrubbed.cumulative.doubleValue)
				)
				.symbolSize(80)
				.foregroundStyle(palette.baseline)
			}
		}
		.chartYScale(domain: yDomain)
		.chartXAxis {
			AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
				AxisGridLine().foregroundStyle(palette.grid)
				AxisValueLabel {
					if let date = value.as(Date.self) {
						Text(axisLabel(for: date))
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
		.chartOverlay { proxy in
			GeometryReader { geometry in
				Rectangle()
					.fill(.clear)
					.contentShape(Rectangle())
					.gesture(
						DragGesture(minimumDistance: 0)
							.onChanged { drag in
								scrubbed = bucket(at: drag.location, proxy: proxy, geometry: geometry)
							}
							.onEnded { _ in scrubbed = nil }
					)
			}
		}
	}

	// MARK: - Readouts

	private var legend: some View {
		HStack(spacing: 16) {
			legendSwatch(color: palette.baseline, label: baselineLabel, dashed: false)
			legendSwatch(color: palette.candidate, label: comparisonLabel, dashed: true)
			Spacer()
		}
		.font(.caption)
	}

	private func legendSwatch(color: Color, label: String, dashed: Bool) -> some View {
		HStack(spacing: 6) {
			// dash pattern doubles as a non-colour cue
			Capsule()
				.fill(color)
				.frame(width: dashed ? 8 : 18, height: 3)
				.overlay(alignment: .trailing) {
					if dashed {
						Capsule().fill(color).frame(width: 6, height: 3).offset(x: 10)
					}
				}
				.frame(width: 18, alignment: .leading)

			Text(label)
				.foregroundStyle(theme.fgColour.opacity(0.75))
		}
	}

	private func scrubReadout(_ bucket: ProjectionBucket) -> some View {
		HStack(spacing: 12) {
			Text(axisLabel(for: bucket.start))
				.font(.caption)
				.foregroundStyle(theme.fgColour.opacity(0.7))

			Text(bucket.cumulative.money)
				.font(.callout.weight(.semibold))
				.monospacedDigit()
				.foregroundStyle(bucket.cumulative < (projection.openingBalance ?? 0) ? palette.critical : theme.fgColour)

			Spacer()

			Text("\(bucket.inflow.moneyCompact) in · \(bucket.outflow.moneyCompact) out")
				.font(.caption2)
				.foregroundStyle(theme.fgColour.opacity(0.55))
		}
	}

	private func troughReadout(_ bucket: ProjectionBucket) -> some View {
		HStack(spacing: 8) {
			Image(systemName: "arrow.down.to.line")
				.font(.caption)
				.foregroundStyle(palette.critical)

			Text("Lowest point")
				.font(.caption)
				.foregroundStyle(theme.fgColour.opacity(0.7))

			Text(bucket.cumulative.money)
				.font(.caption.weight(.semibold))
				.monospacedDigit()
				.foregroundStyle(palette.critical)

			Text("· \(axisLabel(for: bucket.start))")
				.font(.caption)
				.foregroundStyle(theme.fgColour.opacity(0.55))

			Spacer()
		}
	}

	// MARK: - Helpers

	/// nearest bucket to a touch point
	private func bucket(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> ProjectionBucket? {
		guard let plotFrame = proxy.plotFrame else { return nil }
		let origin = geometry[plotFrame].origin
		let x = location.x - origin.x
		guard let date: Date = proxy.value(atX: x) else { return nil }

		return series.min {
			abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date))
		}
	}

	/// date labels get coarser as the horizon grows, so 1000 years doesn't
	/// print a thousand identical-looking day labels
	private func axisLabel(for date: Date) -> String {
		switch projection.granularity {
		case .day, .week:
			return date.formatted(.dateTime.month(.abbreviated).day())
		case .month, .quarter:
			return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
		case .year, .decade:
			return date.formatted(.dateTime.year())
		}
	}
}
