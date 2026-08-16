import SwiftUI
import SwiftData

/* --- Archiving ---
 * cancelling something without pretending it never happened
 *
 * the whole mechanism is ScheduleSuspension; this is the UI onto it. see that
 * file for why archiving isn't deletion. the short version: you really did pay
 * for Hulu for eight months, those occurrences have been reconciled against real
 * transactions, and deleting the expected item would orphan that history.
 */

/// the archive / restore button that lives at the bottom of each item editor
@available(iOS 26, *)
struct ArchiveButton: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context

	let expected: ExpectedTransaction
	@Query private var suspensions: [ScheduleSuspension]

	private var open: ScheduleSuspension? { expected.openSuspension(in: suspensions) }
	private var isArchived: Bool { open != nil }

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Button {
				if let open {
					// resuming closes the span rather than deleting it, so the gap
					// stays a fact and the months you weren't paying stay empty
					open.until = Calendar.current.startOfDay(for: .now)
				} else {
					context.insert(
						ScheduleSuspension(
							expected: expected,
							from: Calendar.current.startOfDay(for: .now)
						)
					)
				}
				try? context.save()
			} label: {
				Label(
					isArchived ? "Restore" : "Archive",
					systemImage: isArchived ? "arrow.uturn.backward" : "archivebox"
				)
				.font(.caption)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 9)
				.overlay {
					RoundedRectangle(cornerRadius: 10)
						.stroke(theme.fgColour.opacity(0.35), lineWidth: 1)
				}
			}
			.buttonStyle(.plain)

			Text(
				isArchived
					? "Restoring starts it again from today. The months it was archived stay empty."
					: "Stops it from today forward. Everything you've already logged against it stays."
			)
			.font(.caption2)
			.foregroundStyle(theme.fgColour.opacity(0.5))
			.fixedSize(horizontal: false, vertical: true)
		}
	}
}

/* --- the archived list ---
 * shown collapsed at the bottom of the income and expense screens
 */
@available(iOS 26, *)
struct ArchivedSection<Destination: View>: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context

	let title: String
	let items: [ExpectedTransaction]
	@Query private var suspensions: [ScheduleSuspension]
	@ViewBuilder let destination: (ExpectedTransaction) -> Destination

	@State private var isExpanded = false

	private var archived: [ExpectedTransaction] {
		items.filter { $0.isArchived(in: suspensions) }
	}

	var body: some View {
		if !archived.isEmpty {
			VStack(alignment: .leading, spacing: 0) {
				Button {
					withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
				} label: {
					HStack(spacing: 8) {
						Image(systemName: "archivebox")
							.font(.caption)
						Text("\(title) (\(archived.count))")
							.font(.subheadline.weight(.semibold))
						Spacer()
						Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
							.font(.caption2)
					}
					.foregroundStyle(theme.fgColour.opacity(0.65))
					.padding()
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)

				if isExpanded {
					ForEach(archived) { item in
						HStack(spacing: 10) {
							NavigationLink {
								destination(item)
							} label: {
								VStack(alignment: .leading, spacing: 2) {
									Text("\(item.category?.emoji ?? "📦")  \(item.name)")
										.font(.subheadline)
									if let since = item.openSuspension(in: suspensions)?.from {
										Text("archived \(since.formatted(.dateTime.month(.abbreviated).day().year()))")
											.font(.caption2)
											.foregroundStyle(theme.fgColour.opacity(0.5))
									}
								}
								.frame(maxWidth: .infinity, alignment: .leading)
								.contentShape(Rectangle())
							}
							.buttonStyle(.plain)

							Text(item.amount.money)
								.font(.caption)
								.monospacedDigit()
								.foregroundStyle(theme.fgColour.opacity(0.5))

							Button {
								if let open = item.openSuspension(in: suspensions) {
									open.until = Calendar.current.startOfDay(for: .now)
									try? context.save()
								}
							} label: {
								Image(systemName: "arrow.uturn.backward")
									.font(.caption)
									.padding(6)
									.contentShape(Rectangle())
							}
							.buttonStyle(.plain)
							.foregroundStyle(theme.fgColour.opacity(0.7))
						}
						.padding(.horizontal)
						.padding(.vertical, 8)
					}

					Text("Restoring picks it up from today — open it afterwards to change the price if it's gone up.")
						.font(.caption2)
						.foregroundStyle(theme.fgColour.opacity(0.45))
						.padding(.horizontal)
						.padding(.bottom, 10)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			.overlay {
				RoundedRectangle(cornerRadius: 14)
					.stroke(theme.fgColour.opacity(0.2), lineWidth: 1)
			}
			.padding()
		}
	}
}
