//
//  BudgetmaApp.swift
//  Budgetma
//
//  Created by big z on 5/30/26.
//

import SwiftUI

@main
struct BudgetmaApp: App {
	@StateObject private var theme = ThemeManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
				.environmentObject(theme)
				.foregroundStyle(theme.fgColour)
				.background(theme.bgColour)
				.tint(theme.bgColour)
        }
    }
}
