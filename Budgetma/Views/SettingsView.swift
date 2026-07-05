import SwiftUI
import SwiftData

// main view
struct SettingsView: View {
	@EnvironmentObject var theme: ThemeManager
	@AppStorage("calendarViewFrequency") private var frequency: Calendar.RecurrenceRule.Frequency = .monthly
	@AppStorage("calendarViewInterval") private var interval: Int = 1
	@AppStorage("calendarViewStartDate") private var startDate: Date = .now

	var body: some View {
		ScrollView {
			VStack(spacing: 5) {
				ColorPicker("Font colour", selection: Binding(
					get: { theme.fgColour },
					set: { theme.setForeground($0)}
				))
				.padding()

				Divider()
				.background(theme.fgColour)

				ColorPicker("Background colour", selection: Binding(
					get: { theme.bgColour },
					set: { theme.setBackground($0)}
				))
				.padding()

				Divider()
				.background(theme.fgColour)

				NavigationLink("Categories >") {
					CategoriesView()
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding()

				Divider()
				.background(theme.fgColour)

				HStack {
					Text("Calendar Frequency")

					Spacer()

					VStack {
						HStack {
							Picker("", selection: $interval) {
								ForEach(1...100, id: \.self) { i in
									Text("\(i)").tag(i)
								}
							}

							Picker("", selection: $frequency) {
								Text("Day\(interval == 1 ? "" : "s")").tag(Calendar.RecurrenceRule.Frequency.daily)
								Text("Week\(interval == 1 ? "" : "s")").tag(Calendar.RecurrenceRule.Frequency.weekly)
								Text("Month\(interval == 1 ? "" : "s")").tag(Calendar.RecurrenceRule.Frequency.monthly)
								Text("Year\(interval == 1 ? "" : "s")").tag(Calendar.RecurrenceRule.Frequency.yearly)
							}
						}
						.frame(maxWidth: .infinity, alignment: .trailing)

						if frequency == .weekly && interval == 1 {
							HStack {
								Text("Start")

								Spacer()

								HStack(spacing: 8) {
									ForEach(Locale.Weekday.allCases , id: \.self) {day in
										Button(day.shortName) {
											startDate = mostRecentDate(for: day)
										}
										.frame(maxWidth: .infinity)
										.padding(.vertical, 6)
										.background(day.calendarValue == Calendar.current.component(.weekday, from: startDate) ? theme.fgColour : theme.bgColour)
										.foregroundColor(day.calendarValue == Calendar.current.component(.weekday, from: startDate) ? theme.bgColour : theme.fgColour)
										.clipShape(RoundedRectangle(cornerRadius: 8))
										.overlay {
											RoundedRectangle(cornerRadius: 8)
												.stroke(theme.fgColour, lineWidth: 1)
										}
									}
								}
							}
						}
						if interval != 1 {
							DatePill(label: "Start Date", date: $startDate)
						}
					}
				}
				.padding()
			}
			.scrollContentBackground(.hidden)
		}
		.scrollContentBackground(.hidden)
		.themed()
	}

}

// view for categories
struct CategoriesView: View {
	@EnvironmentObject var theme: ThemeManager
	@Query(
		filter: #Predicate<Category> {
			$0.isActive
		},
		sort: \Category.name
	)
	private var categories: [Category]
	@Environment(\.modelContext)
	private var context
	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				ForEach(categories) {category in
					VStack(spacing: 0) {
						NavigationLink {
							CategoryView(category: category)
						} label: {
							HStack {
								Text("\(category.emoji) \(category.name)")

								Spacer()

								Button(role: .destructive) {
									delete(category)
								} label: {
									Label("", systemImage: "trash")
								}
							}
						}
						.padding()
						.frame(maxWidth: .infinity, alignment: .leading)
					}

				}
				NavigationLink {
					NewCategoryView()
				} label: {
					Label("New Category", systemImage: "plus")
				}
				.padding()
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.scrollContentBackground(.hidden)
		}
		.scrollContentBackground(.hidden)
		.themed()
	}

	private func delete(_ category: Category) {
		var active = try? context.fetch(
			FetchDescriptor<Category>(
				predicate: #Predicate {
					$0.isActive == true
				}
			)
		)

		if active?.count ?? 0 > 1 {
			category.isActive = false
			try? context.save()
		}
	}

}

// view for an individual category
struct CategoryView: View {
	@EnvironmentObject var theme: ThemeManager
	@Bindable var category: Category
	@Environment(\.modelContext)
	private var context

	var body: some View {
		ScrollView {
			VStack {
				InputField(field: "Name", placeholder: "Something", text: $category.name)
				.padding()

				InputField(field: "Emoji", placeholder: "😳", text: $category.emoji)
				.padding()
			}
			.scrollContentBackground(.hidden)
		}
		.scrollContentBackground(.hidden)
		.themed()
		.onDisappear {
			if category.name == "" && category.emoji == "" {
				return
			} else {
				try? context.save()
			}
		}
	}

	init(category: Category) {
		self.category = category
	}
}

// new category view
struct NewCategoryView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext)
	private var context

	@Environment(\.dismiss)
	private var dismiss

	@State private var name = ""
	@State private var emoji = ""

	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				InputField(field: "Name", placeholder: "Something", text: $name)
				.padding()

				InputField(field: "Emoji", placeholder: "😳", text: $emoji)
				.padding()
			}
			.scrollContentBackground(.hidden)
		}
		.scrollContentBackground(.hidden)
		.themed()
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button("Cancel") {
					dismiss()
				}
			}
			ToolbarItem(placement: .confirmationAction) {
				Button("Save") {
					let category = Category(
						name: name.isEmpty ? "Something" : name,
						emoji: emoji.isEmpty ? "😳" : emoji
					)

					let existing = try? context.fetch(
						FetchDescriptor<Category>(
							predicate: #Predicate<Category> {
								$0.name == name
							}
						)
					)

					if !(existing?.isEmpty ?? true) {
						existing?.first?.name = name
						existing?.first?.emoji = emoji
						existing?.first?.isActive = true
					} else {
						context.insert(category)
					}
					try? context.save()
					dismiss()
				}
			}
		}
	}
}

extension Locale.Weekday {
	var calendarValue: Int {
		switch self {
		case .sunday: return 1
		case .monday: return 2
		case .tuesday: return 3
		case .wednesday: return 4
		case .thursday: return 5
		case .friday: return 6
		case .saturday: return 7
		default: return 1
		}
	}
}

func mostRecentDate(for weekday: Locale.Weekday, onOrBefore reference: Date = .now) -> Date {
	let calendar = Calendar.current
	let today = calendar.startOfDay(for: reference)
	if calendar.component(.weekday, from: today) == weekday.calendarValue {
		return today
	}

	var comps = DateComponents()
	comps.weekday = weekday.calendarValue
	return calendar.nextDate(after: today, matching: comps, matchingPolicy: .nextTime, direction: .backward) ?? today
}
