import SwiftUI

struct ContentView: View {
    var body: some View {
        NutriScanRootView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: FoodEntry.self, inMemory: true)
}
