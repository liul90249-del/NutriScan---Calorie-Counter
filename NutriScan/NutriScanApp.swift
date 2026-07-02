//
//  NutriScanApp.swift
//  NutriScan
//
//  Created by liufeng(2018) on 2026/4/28.
//

import SwiftUI
import SwiftData

@main
struct NutriScanApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            FoodEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
