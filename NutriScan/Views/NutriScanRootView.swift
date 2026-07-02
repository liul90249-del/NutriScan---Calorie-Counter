import SwiftUI

struct NutriScanRootView: View {
    var body: some View {
        AppFlowRootView()
    }
}

#Preview {
    NutriScanRootView()
        .modelContainer(for: FoodEntry.self, inMemory: true)
}
