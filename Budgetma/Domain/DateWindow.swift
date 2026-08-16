import Foundation

/* --- DateWindow ---
 * "some particular window" -- expressed as a count and a unit, never as a
 * hardcoded month
 *
 * this one type backs both the budget window (2 weeks) and the projection
 * horizon (1 year, or 1 day, or 1000 years). the app has no privileged period:
 * a month is just `.init(3, .month)`'s smaller sibling, not the unit everything
 * else is defined against.
 */
nonisolated struct DateWindow: Equatable, Hashable, Sendable {
	enum Unit: String, CaseIterable, Identifiable, Sendable {
		case day, week, month, year

		var id: String { rawValue }

		var component: Calendar.Component {
			switch self {
			case .day: return .day
			case .week: return .weekOfYear
			case .month: return .month
			case .year: return .year
			}
		}

		func label(count: Int) -> String {
			let base: String
			switch self {
			case .day: base = "day"
			case .week: base = "week"
			case .month: base = "month"
			case .year: base = "year"
			}
			return count == 1 ? base : base + "s"
		}
	}

	var count: Int
	var unit: Unit
	/// where the window starts; defaults to today
	var anchor: Date

	init(count: Int = 1, unit: Unit = .month, anchor: Date = .now) {
		self.count = Swift.max(count, 1)
		self.unit = unit
		self.anchor = anchor
	}

	var label: String { "\(count) \(unit.label(count: count))" }

	/// the half-open range this window covers, from the start of the anchor day
	func range(calendar: Calendar = .current) -> Range<Date> {
		let start = calendar.startOfDay(for: anchor)
		let end = calendar.date(byAdding: unit.component, value: count, to: start)
			?? start.addingTimeInterval(86_400)
		// a degenerate window would break bucketing downstream
		return start ..< Swift.max(end, start.addingTimeInterval(86_400))
	}

	/// snap the anchor back to the start of its own unit
	///
	/// matters for the budget window: anchored at "now", a window you're
	/// standing in starts today and hides everything you've already spent this
	/// period, which makes expected-vs-actual useless exactly when you'd look
	/// at it. aligned, the window covers the elapsed part too.
	func aligned(calendar: Calendar = .current) -> DateWindow {
		var snapped = self
		let component: Calendar.Component
		switch unit {
		case .day: component = .day
		case .week: component = .weekOfYear
		case .month: component = .month
		case .year: component = .year
		}
		snapped.anchor = calendar.dateInterval(of: component, for: anchor)?.start
			?? calendar.startOfDay(for: anchor)
		return snapped
	}

	/// shift the window forward or back by whole windows -- for paging
	func offset(by steps: Int, calendar: Calendar = .current) -> DateWindow {
		var moved = self
		moved.anchor = calendar.date(
			byAdding: unit.component,
			value: count * steps,
			to: anchor
		) ?? anchor
		return moved
	}

	// handy presets for the pickers
	static let twoWeeks = DateWindow(count: 2, unit: .week)
	static let oneMonth = DateWindow(count: 1, unit: .month)
	static let oneYear = DateWindow(count: 1, unit: .year)
}
