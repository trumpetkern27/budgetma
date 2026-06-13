import SwiftUI
import SwiftData

struct RecurrenceRulePicker: View {
	@EnvironmentObject var theme: ThemeManager
	@Binding var rule: RecurrenceRule?
	@State private var enabled: Bool = false
	@State private var frequency: Calendar.RecurrenceRule.Frequency = .monthly
	@State private var interval: Int = 1
	@State private var selectedWeekdays: Set<Locale.Weekday> = []
	@State private var endMode: EndMode = .never
	@State private var endDate: Date = .now
	@State private var occurrenceCount: Int = 12

	enum EndMode { case never, onDate, afterCount }

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Toggle("Repeats", isOn: $enabled)
				.padding()

			if enabled {
				Divider()

				Picker("Frequency", selection: $frequency) {
					Text("Daily").tag(Calendar.RecurrenceRule.Frequency.daily)
					Text("Weekly").tag(Calendar.RecurrenceRule.Frequency.weekly)
					Text("Monthly").tag(Calendar.RecurrenceRule.Frequency.monthly)
					Text("Annually").tag(Calendar.RecurrenceRule.Frequency.yearly)
				}
				.pickerStyle(.segmented)
				.padding()

				Divider()

				HStack {
					Text("Every")
					Spacer()
					Stepper("\(interval) \(frequencyLabel)", value: $interval, in: 1...99)
				}
				.padding()

				if frequency == .weekly {
					Divider()

					HStack(spacing: 8) {
						ForEach(Locale.Weekday.allCases , id: \.self) {day in
							let onn = selectedWeekdays.contains(day)
							Button(day.shortName) {
								if onn { selectedWeekdays.remove(day) }
								else { selectedWeekdays.insert(day) }
							}
							.frame(maxWidth: .infinity)
							.padding(.vertical, 6)
							.clipShape(RoundedRectangle(cornerRadius: 8))
							.overlay {
								RoundedRectangle(cornerRadius: 8)
									.stroke(theme.fgColour, lineWidth: 1)
							}
						}
					}
					.padding()
				}

				Divider()

				Picker("Ends", selection: $endMode) {
					Text("Never").tag(EndMode.never)
					Text("On date").tag(EndMode.onDate)
					Text("After").tag(EndMode.afterCount)
				}
				.pickerStyle(.segmented)
				.padding()

				if endMode == .onDate {
					DatePicker("End Date", selection: $endDate, displayedComponents: .date)
						.padding(.horizontal)
						.padding(.bottom)
				}

				if endMode == .afterCount {
					HStack {
						Text("Occurrences")
						Spacer()
						Stepper("\(occurrenceCount)", value: $occurrenceCount, in: 1...99)
					}
						.padding(.horizontal)
						.padding(.bottom)
				}
			}
		}
		.themed()
		.onChange(of: enabled) { _, _ in commit() }
		.onChange(of: frequency) { _, _ in commit() }
		.onChange(of: interval) { _, _ in commit() }
		.onChange(of: selectedWeekdays) { _, _ in commit() }
		.onChange(of: endMode) { _, _ in commit() }
		.onChange(of: endDate) { _, _ in commit() }
		.onChange(of: occurrenceCount) { _, _ in commit() }
		.onAppear { load() }
		.overlay {
			RoundedRectangle(cornerRadius: 12) 
				.stroke(theme.fgColour, lineWidth: 1)
		}
	}

	private var frequencyLabel: String {
		let base: String
		switch frequency {
		case .daily: base = "day"
		case .weekly: base = "week"
		case .monthly: base = "month"
		case .yearly: base = "year"
		default: base = "period"
		}
		return interval == 1 ? base : "\(base)s"
	}

	private func commit() {
		guard enabled else { rule = nil; return}
		let weekdays: [(Locale.Weekday, Int?)] = selectedWeekdays.map { ($0, nil ) }

		switch endMode {
		case .never:
			rule = RecurrenceRule(
				frequency: frequency, interval: interval, daysOfWeek: weekdays
			)
		case .onDate:
			rule = RecurrenceRule(
				frequency: frequency, interval: interval, endDate: endDate, daysOfWeek: weekdays
			)
		case .afterCount:
			rule = RecurrenceRule(
				frequency: frequency, interval: interval, occuranceCount: occurrenceCount, daysOfWeek: weekdays
			)
		}

	}

	private func load() {
		guard let rule else { enabled = false; return }
		enabled = true
		frequency = Calendar.RecurrenceRule.Frequency(rawValue: rule.frequencyRaw) ?? .monthly
		interval = rule.interval
		selectedWeekdays = Set(rule.daysOfWeekEncoded.compactMap { encoded in
			let parts = encoded.split(separator: ",")
			guard let raw = parts.first.map(String.init) else { return nil }
			return Locale.Weekday(rawValue: raw)
		})
		if let date = rule.endDate { endMode = .onDate; endDate = date }
		else if let nth = rule.occuranceCount { endMode = .afterCount; occurrenceCount = nth }
		else { endMode = .never }
	}

}

extension Locale.Weekday: CaseIterable {
	public static var allCases: [Locale.Weekday] {
		[.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
	}

	var shortName: String {
		switch self {
		case .sunday: return "S"
		case .monday: return "M"
		case .tuesday: return "T"
		case .wednesday: return "W"
		case .thursday: return "T"
		case .friday: return "F"
		case .saturday: return "S"
		default: return "?"
		}
	}
}
