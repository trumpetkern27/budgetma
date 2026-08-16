import SwiftUI
import Charts

/* --- Window tracking chart ---
 * planned vs actual as a running total across the window
 *
 * the bar chart this replaces answered one question -- "which items came in over
 * or under" -- and answered it without any sense of *when*. that matters here
 * more than almost anywhere else in the app: the whole premise is that a
 * fortnightly paycheck and a monthly rent don't line up, so "am I behind?" has a
 * different answer on day 3 than on day 20 of the same window.
 *
 * so: the plan is the filled area, drawn across the whole window, and the actual
 * is a line that stops at today. the gap between them at the right-hand end of
 * the actual line *is* your drift, drawn rather than stated.
 */
@available(iOS 26, *)
struct WindowTrackingChart: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.chartPalette) private var palette

	/// one point on either curve
	struct Point: Identifiable, Hashable {
		let date: Date
		let planned: Decimal
		/// nil once the window runs past today -- the future has no actuals
		let actual: Decimal?

		var id: Date { date }
	}

	let points: [Point]
	var height: CGFloat = 200

	@State private var scrubbed: Point?

	private var lastActual: Point? {
		points.last { $0.actual != nil }
	}

	private var yDomain: ClosedRange<Double> {
		var values = points.map(\.planned.doubleValue)
		values += points.compactMap { $0.actual?.doubleValue }
		values.append(0)

		guard let low = values.min(), let high = values.max() else { return -1...1 }
		let span = Swift.max(high - low, 1)
		let padding = span * 0.12
		return (low - padding)...(high + padding)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			legend

			if points.count < 2 {
				Text("Not enough of this window has happened yet.")
					.font(.caption)
					.foregroundStyle(theme.fgColour.opacity(0.5))
					.frame(maxWidth: .infinity, minHeight: height / 2)
			} else {
				chart.frame(height: height)
				readout
			}
		}
	}

	// MARK: - Chart

	private var chart: some View {
		Chart {
			ForEach(points) { point in
				AreaMark(
					x: .value("Date", point.date),
					y: .value("Planned", point.planned.doubleValue)
				)
				.foregroundStyle(
					LinearGradient(
						colors: [palette.baseline.opacity(0.24), palette.baseline.opacity(0.02)],
						startPoint: .top,
						endPoint: .bottom
					)
				)
				.interpolationMethod(.monotone)
			}

			ForEach(points) { point in
				LineMark(
					x: .value("Date", point.date),
					y: .value("Planned", point.planned.doubleValue),
					series: .value("Series", "Planned")
				)
				.foregroundStyle(palette.baseline)
				.lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
				.interpolationMethod(.monotone)
			}

			// actual stops where the logging does
			ForEach(points.filter { $0.actual != nil }) { point in
				LineMark(
					x: .value("Date", point.date),
					y: .value("Actual", point.actual?.doubleValue ?? 0),
					series: .value("Series", "Actual")
				)
				.foregroundStyle(palette.candidate)
				.lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 3]))
				.interpolationMethod(.monotone)
			}

			// where you've actually got to, and how far that is from the plan
			if let lastActual, let actual = lastActual.actual {
				PointMark(
					x: .value("Date", lastActual.date),
					y: .value("Actual", actual.doubleValue)
				)
				.symbolSize(70)
				.foregroundStyle(palette.candidate)

				RuleMark(
					x: .value("Date", lastActual.date),
					yStart: .value("Actual", actual.doubleValue),
					yEnd: .value("Planned", lastActual.planned.doubleValue)
				)
				.foregroundStyle(driftColour(actual - lastActual.planned).opacity(0.65))
				.lineStyle(StrokeStyle(lineWidth: 2, dash: [2, 2]))
			}

			RuleMark(y: .value("Break even", 0))
				.foregroundStyle(palette.axis.opacity(0.6))
				.lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

			if let scrubbed {
				RuleMark(x: .value("Date", scrubbed.date))
					.foregroundStyle(theme.fgColour.opacity(0.35))
					.lineStyle(StrokeStyle(lineWidth: 1))
			}
		}
		.chartYScale(domain: yDomain)
		.chartXAxis {
			AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
				AxisGridLine().foregroundStyle(palette.grid)
				AxisValueLabel {
					if let date = value.as(Date.self) {
						Text(date.formatted(.dateTime.month(.abbreviated).day()))
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
								scrubbed = point(at: drag.location, proxy: proxy, geometry: geometry)
							}
							.onEnded { _ in scrubbed = nil }
					)
			}
		}
	}

	// MARK: - Furniture

	private var legend: some View {
		HStack(spacing: 16) {
			swatch(colour: palette.baseline, label: "Planned", dashed: false)
			swatch(colour: palette.candidate, label: "Actual so far", dashed: true)
			Spacer()
		}
		.font(.caption)
	}

	private func swatch(colour: Color, label: String, dashed: Bool) -> some View {
		HStack(spacing: 6) {
			// the dash doubles as a non-colour cue
			Capsule()
				.fill(colour)
				.frame(width: dashed ? 8 : 18, height: 3)
				.overlay(alignment: .trailing) {
					if dashed {
						Capsule().fill(colour).frame(width: 6, height: 3).offset(x: 10)
					}
				}
				.frame(width: 18, alignment: .leading)

			Text(label)
				.foregroundStyle(theme.fgColour.opacity(0.75))
		}
	}

	@ViewBuilder
	private var readout: some View {
		if let scrubbed {
			HStack(spacing: 12) {
				Text(scrubbed.date.formatted(.dateTime.month(.abbreviated).day()))
					.font(.caption)
					.foregroundStyle(theme.fgColour.opacity(0.7))

				Text("plan \(scrubbed.planned.moneySigned)")
					.font(.caption.weight(.semibold))
					.monospacedDigit()
					.foregroundStyle(palette.baseline)

				if let actual = scrubbed.actual {
					Text("actual \(actual.moneySigned)")
						.font(.caption.weight(.semibold))
						.monospacedDigit()
						.foregroundStyle(palette.candidate)
				}

				Spacer()
			}
		} else if let lastActual, let actual = lastActual.actual {
			let drift = actual - lastActual.planned
			HStack(spacing: 6) {
				Image(systemName: drift >= 0 ? "arrow.up.right" : "arrow.down.right")
					.font(.caption)
					.foregroundStyle(driftColour(drift))
				Text(drift >= 0 ? "Ahead of plan by" : "Behind plan by")
					.font(.caption)
					.foregroundStyle(theme.fgColour.opacity(0.7))
				Text(abs(drift).money)
					.font(.caption.weight(.semibold))
					.monospacedDigit()
					.foregroundStyle(driftColour(drift))
				Text("as of \(lastActual.date.formatted(.dateTime.month(.abbreviated).day()))")
					.font(.caption2)
					.foregroundStyle(theme.fgColour.opacity(0.5))
				Spacer()
			}
		}
	}

	private func driftColour(_ drift: Decimal) -> Color {
		drift >= 0 ? palette.good : palette.critical
	}

	private func point(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Point? {
		guard let plotFrame = proxy.plotFrame else { return nil }
		let origin = geometry[plotFrame].origin
		guard let date: Date = proxy.value(atX: location.x - origin.x) else { return nil }

		return points.min {
			abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
		}
	}
}
