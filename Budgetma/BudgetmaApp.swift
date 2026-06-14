//
//  BudgetmaApp.swift
//  Budgetma
//
//  Created by big z on 5/30/26.
//

import SwiftUI
import SwiftData

@main
struct BudgetmaApp: App {
	@StateObject private var theme = ThemeManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
				.environmentObject(theme)
				.foregroundStyle(theme.fgColour)
				.background(theme.bgColour)
				.tint(theme.fgColour)
        }
		.modelContainer(for: [
			// transactions
			Transaction.self,
			Expense.self,
			Income.self,
			// expected transactions
			ExpectedTransaction.self,
			ExpectedIncome.self,
			ExpectedExpense.self,
			Envelope.self,
			// category
			Category.self
		])
    }
}
