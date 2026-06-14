import SwiftUI

/*
struct CategoryListNav: View {
	@Binding var dict: [(key: String, category: Category?, type:)]

	var body: some View {
		VStack(spacing: 0) {
			ForEach(groupedTransactions, id: \.key) {group in
				VStack {
					CategoryHeader(
						name: group.category?.name ?? "Uncategorized",
						total: group.transactions.reduce(0) { $0 + $1.amount },
						isExpanded: expandedTransactionCategories.contains(group.key)
					) {
						toggleTransactionCategory(group.key)
					}
					if expandedTransactionCategories.contains(group.key) {
						ForEach(group.transactions) { transaction in 
							NavigationLink {
								SingleExpectedTransactionView(transaction: transaction)
							} label: {
								HStack {
									Text("\(transaction.category!.emoji)  \(transaction.name)")

									Spacer()

									Text(transaction.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
								}
							}
							.padding()
						}
					}
					Divider()
					.background(theme.fgColour)
				}
				.padding()
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			NavigationLink {
				NewTransactionView()
			} label: {
				Label("New Expected Transaction", systemImage: "plus")
			}
			.padding()
		}
	}
}
*/
