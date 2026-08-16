import SwiftUI
import SwiftData

/* --- A day, opened up ---
 * what was planned for this day, and what actually happened on it
 *
 * the calendar cell can only ever show one number. this is the rest of it: both
 * sides of the same day, each row a way into logging or editing, so the grid
 * stops being a read-only picture.
 */
@available(iOS 26, *)
struct DayDetailView: View {
	@EnvironmentObject var theme: ThemeManager

	let day: Date
	let expected: [ScheduledEvent]
	let actuals: [Transaction]
	let settledIDs: Set<String>

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	private var plannedNet: Decimal {
		expected.reduce(0) { $0 + $1.signedAmount }
	}

	private var actualNet: Decimal {
		actuals.reduce(Decimal(0)) { sum, transaction in
			sum + (transaction is Income ? transaction.amount : -transaction.amount)
		}
	}

	/// green means "ahead", red means "behind" -- an empty day is neither
	private func accent(for value: Decimal) -> Color {
		guard value != 0 else { return theme.fgColour }
		return value > 0 ? palette.good : palette.critical
	}

	private var outstanding: [ScheduledEvent] {
		expected.filter { !settledIDs.contains($0.id) }
	}

	var body: some View {
		DetailSheet(title: day.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
			HStack(alignment: .top, spacing: 12) {
				StatTile(
					label: "Planned",
					value: plannedNet.moneySigned,
					// zero is not good news, it's no news -- only colour a real figure
					accent: accent(for: plannedNet),
					caption: "\(expected.count) item\(expected.count == 1 ? "" : "s")"
				)
				StatTile(
					label: "Logged",
					value: actualNet.moneySigned,
					accent: accent(for: actualNet),
					caption: "\(actuals.count) transaction\(actuals.count == 1 ? "" : "s")"
				)
			}

			if !expected.isEmpty {
				Card(
					title: "Planned",
					subtitle: outstanding.isEmpty
						? "All settled"
						: "Tap anything to log what really happened"
				) {
					VStack(spacing: 0) {
						ForEach(expected) { event in
							NavigationLink {
								LogTransactionView(prefill: event)
							} label: {
								ScheduledEventRow(
									event: event,
									isSettled: settledIDs.contains(event.id)
								)
							}
							.buttonStyle(.plain)

							if event.id != expected.last?.id {
								Divider().background(theme.fgColour.opacity(0.12))
							}
						}
					}
				}
			}

			if !actuals.isEmpty {
				Card(title: "Logged", subtitle: "What actually moved on this day") {
					VStack(spacing: 0) {
						ForEach(actuals) { transaction in
							NavigationLink {
								LogTransactionView(editing: transaction)
							} label: {
								TransactionRow(transaction: transaction)
							}
							.buttonStyle(.plain)

							if transaction.persistentModelID != actuals.last?.persistentModelID {
								Divider().background(theme.fgColour.opacity(0.12))
							}
						}
					}
				}
			}

			if expected.isEmpty && actuals.isEmpty {
				Card(title: "Nothing on this day") {
					Text("No planned items and nothing logged.")
						.font(.callout)
						.foregroundStyle(theme.fgColour.opacity(0.65))
				}
			}

			NavigationLink {
				LogTransactionView(prefillDate: day)
			} label: {
				Card {
					HStack(spacing: 10) {
						Image(systemName: "plus.circle.fill")
						Text("Log something on this day")
							.font(.subheadline)
						Spacer()
					}
				}
			}
			.buttonStyle(.plain)
		}
	}
}
