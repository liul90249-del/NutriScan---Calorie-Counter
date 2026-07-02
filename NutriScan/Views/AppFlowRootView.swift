import SwiftUI

struct AppFlowRootView: View {
    @StateObject private var flow = AppFlowViewModel()
    @AppStorage(AppLocalization.languageStorageKey) private var appLanguageRawValue = AppLanguage.system.rawValue

    private var selectedLocale: Locale? {
        let language = AppLanguage(rawValue: appLanguageRawValue) ?? .system
        return language.locale
    }

    var body: some View {
        Group {
            switch flow.currentScreen {
            case .welcome:
                WelcomeFlowView()
            case .painPoints:
                PainPointsFlowView()
            case .gender:
                GenderFlowView()
            case .heightWeight:
                HeightWeightFlowView()
            case .activity:
                ActivityLevelFlowView()
            case .goal:
                GoalWeightFlowView()
            case .speed:
                WeightSpeedFlowView()
            case .healthConnect:
                HealthConnectFlowView()
            case .loading:
                FakeLoadingFlowView()
            case .socialProof:
                SocialProofFlowView()
            case .paywall:
                PaywallFlowView()
            case .dashboard:
                MainDashboardShellView()
            case .camera:
                CameraCaptureView()
            case .foodConfirmation:
                FoodConfirmationFlowView()
            }
        }
        .environmentObject(flow)
        .modifier(AppLocaleModifier(locale: selectedLocale))
        .id(appLanguageRawValue)
        .onChange(of: appLanguageRawValue) { _, _ in
            flow.recognizedFood = nil
        }
    }
}

private struct AppLocaleModifier: ViewModifier {
    let locale: Locale?

    func body(content: Content) -> some View {
        if let locale {
            content.environment(\.locale, locale)
        } else {
            content
        }
    }
}

#Preview {
    AppFlowRootView()
        .modelContainer(for: FoodEntry.self, inMemory: true)
}
