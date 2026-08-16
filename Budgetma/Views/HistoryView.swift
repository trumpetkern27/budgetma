import SwiftUI
import SwiftData

/* --- History ---
 * every actual you've ever logged, newest first
 *
 * the rest of the app is organised around a window: Budget shows the window
 * you're in, Home shows the period. neither of them can answer "when did I last
 * pay for that" or "how much have I spent on coffee". this can.
 *
 * it reads the same Transaction rows everything else does -- there's no separate
 * history store -- so editing here settles and unsettles exactly like editing
 * from the Budget screen.
 */
@available(iOS 26, *)
struct HistoryView: View {
	@EnvironmentObject var theme: ThemeManager
	@Environment(\.modelContext) private var context

	@Query(sort: \Transaction.date, order: .reverse)
	private var transactions: [Transaction]

	@State private var search: String = ""
	@State private var filter: Filter = .all

	enum Filter: String, CaseIterable, Identifiable {
		case all, income, expense, savings
		var id: String { rawValue }
		var label: String {
			switch self {
			case .all: return "All"
			case .income: return "In"
			case .expense: return "Out"
			case .savings: return "Saved"
			}
		}

		func matches(_ transaction: Transaction) -> Bool {
			switch self {
			case .all: return true
			case .income: return transaction is Income
			case .expense: return transaction is Expense
			case .savings: return transaction is Savings
			}
		}
	}

	private var palette: ChartPalette { .forSurface(theme.bgColour) }

	private var filtered: [Transaction] {
		let term = search.trimmingCharacters(in: .whitespaces).lowercased()
		return transactions.filter { transaction in
			guard filter.matches(transaction) else { return false }
			guard !term.isEmpty else { return true }
			return transaction.name.lowercased().contains(term)
				|| (transaction.note?.lowercased().contains(term) ?? false)
				|| (transaction.category?.name.lowercased().contains(term) ?? false)
		}
	}

	/// newest day first, and newest within the day first
	private var grouped: [(day: Date, items: [Transaction])] {
		let dictionary = Dictionary(grouping: filtered) {
			Calendar.current.startOfDay(for: $0.date)
		}
		return dictionary.keys.sorted(by: >).map { day in
			(day, dictionary[day]!.sorted { $0.date > $1.date })
		}
	}

	private var total: Decimal {
		filtered.reduce(Decimal(0)) { sum, transaction in
			sum + (transaction is Income ? transaction.amount : -transaction.amount)
		}
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				filterBar

				if filtered.isEmpty {
					emptyState
				} else {
					totalsCard

					ForEach(grouped, id: \.day) { group in
						dayGroup(group.day, group.items)
					}
				}
			}
			.padding()
		}
		.scrollContentBackground(.hidden)
		.themed()
		.chartPalette(for: theme.bgColour)
		.navigationTitle("History")
		.navigationBarTitleDisplayMode(.inline)
		.searchable(text: $search, prompt: "Search name, note or category")
		.dismissableKeyboard()
	}

	// MARK: - Pieces

	private var filterBar: some View {
		Picker("Filter", selection: $filter) {
			ForEach(Filter.allCases) { option in
				Text(option.label).tag(option)
			}
		}
		.pickerStyle(.segmented)
	}

	private var totalsCard: some View {
		HStack(alignment: .top, spacing: 12) {
			StatTile(
				label: filter == .all ? "Net" : "Total",
				value: filter == .all ? total.moneySigned : filtered.reduce(Decimal(0)) { $0 + $1.amount }.money,
				accent: filter == .all ? (total >= 0 ? palette.good : palette.critical) : theme.fgColour
			)
			StatTile(
				label: "Logged",
				value: "\(filtered.count)",
				caption: search.isEmpty && filter == .all ? "All time" : "Matching"
			)
		}
	}

	private var emptyState: some View {
		Card(title: transactions.isEmpty ? "Nothing logged yet" : "No matches") {
			Text(
				transactions.isEmpty
					? "Actual transactions you log show up here, newest first."
					: "Nothing matches that search in this filter."
			)
			.font(.callout)
			.foregroundStyle(theme.fgColour.opacity(0.65))
		}
	}

	private func dayGroup(_ day: Date, _ items: [Transaction]) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack {
				Text(day, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
					.font(.caption.weight(.semibold))
					.foregroundStyle(theme.fgColour.opacity(0.65))
				Spacer()
				Text(dayNet(items).moneySigned)
					.font(.caption2)
					.monospacedDigit()
					.foregroundStyle(theme.fgColour.opacity(0.45))
			}
			.padding(.bottom, 6)

			VStack(spacing: 0) {
				ForEach(items) { transaction in
					NavigationLink {
						LogTransactionView(editing: transaction)
					} label: {
						row(transaction)
					}
					.buttonStyle(.plain)
					.contextMenu {
						Button(role: .destructive) {
							context.delete(transaction)
							try? context.save()
						} label: {
							Label("Delete", systemImage: "trash")
						}
					}

					if transaction.persistentModelID != items.last?.persistentModelID {
						Divider().background(theme.fgColour.opacity(0.12))
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 4)
			.overlay {
				RoundedRectangle(cornerRadius: 14)
					.stroke(theme.fgColour.opacity(0.25), lineWidth: 1)
			}
		}
	}

	private func row(_ transaction: Transaction) -> some View {
		let isIncome = transaction is Income

		return HStack(spacing: 10) {
			Text(transaction.category?.emoji ?? (isIncome ? "💰" : "💸"))

			VStack(alignment: .leading, spacing: 2) {
				Text(transaction.name)
					.font(.subheadline)
					.lineLimit(1)

				HStack(spacing: 4) {
					// what it settled, if anything -- the same distinction the
					// Budget screen draws between planned and unplanned
					if transaction.expected != nil {
						Image(systemName: "link")
							.font(.system(size: 8))
					}
					// one Text, so there's a single truncation point at the end --
					// two of them side by side ellipsed in the middle of both
					Text(caption(for: transaction))
						.lineLimit(1)
				}
				.font(.caption2)
				.foregroundStyle(theme.fgColour.opacity(0.5))
			}

			Spacer()

			Text((isIncome ? transaction.amount : -transaction.amount).moneySigned)
				.font(.subheadline)
				.monospacedDigit()
				.foregroundStyle(isIncome ? palette.inflow : theme.fgColour)
		}
		.padding(.vertical, 9)
		.contentShape(Rectangle())
	}

	private func caption(for transaction: Transaction) -> String {
		var parts = [transaction.expected?.name ?? "Unplanned"]
		if let note = transaction.note, !note.isEmpty { parts.append(note) }
		return parts.joined(separator: " · ")
	}

	private func dayNet(_ items: [Transaction]) -> Decimal {
		items.reduce(Decimal(0)) { sum, transaction in
			sum + (transaction is Income ? transaction.amount : -transaction.amount)
		}
	}
}
