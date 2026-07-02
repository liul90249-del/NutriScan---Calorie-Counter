import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    @AppStorage("nutriscan.notifications_enabled") private var notificationsEnabled = true
    @AppStorage("nutriscan.water_reminders_enabled") private var waterRemindersEnabled = false
    @AppStorage(AppLocalization.languageStorageKey) private var appLanguageRawValue = AppLanguage.system.rawValue
    @State private var showPaywall = false

    private var calorieTarget: Int {
        let base = flow.profile.gender == "Female" ? 1500 : 1800
        let activityBoost: Int
        switch flow.profile.activityLevel {
        case "Very active": activityBoost = 450
        case "Moderately active": activityBoost = 300
        case "Lightly active": activityBoost = 180
        default: activityBoost = 0
        }
        let maintenance = base + activityBoost
        let deficit = Int((flow.profile.weeklyLossRate * 7700 / 7).rounded())
        return max(1200, maintenance - deficit)
    }

    private var proteinTarget: Int {
        Int((flow.profile.weight * 1.6).rounded())
    }

    private var progressSummary: String {
        let delta = flow.profile.weight - flow.profile.goalWeight
        if delta <= 0 {
            return localized("You are at or below your target weight.")
        }
        return String(
            format: localized("%@ kg to goal"),
            locale: locale,
            delta.formatted(.number.precision(.fractionLength(1)))
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    summaryCard
                    goalsCard
                    preferencesCard
                    remindersCard
                    aiCard
                    privacyCard
                }
                .padding(20)
                .padding(.bottom, 120)
            }
            .background(Color(hex: "#FAFAF8").ignoresSafeArea())
            .navigationTitle(localized("Profile"))
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showPaywall) {
                PremiumPaywallSheet()
                    .environmentObject(flow)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("Your Plan"))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(progressSummary)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Color(hex: "#111827"))
            }

            HStack(spacing: 10) {
                statPill(title: "Daily kcal", value: "\(calorieTarget)")
                statPill(title: "Protein", value: "\(proteinTarget)g")
                statPill(title: "Goal", value: "\(flow.profile.goalWeight.formatted(.number.precision(.fractionLength(0))))kg")
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var goalsCard: some View {
        settingsCard(title: "Goals") {
            settingRow(title: "Current weight") {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("\(flow.profile.weight.formatted(.number.precision(.fractionLength(1)))) kg")
                        .foregroundStyle(.secondary)
                    Slider(value: $flow.profile.weight, in: 35...160, step: 0.5)
                        .frame(width: 150)
                        .tint(.black)
                }
            }

            settingRow(title: "Goal weight") {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("\(flow.profile.goalWeight.formatted(.number.precision(.fractionLength(1)))) kg")
                        .foregroundStyle(.secondary)
                    Slider(value: $flow.profile.goalWeight, in: 35...160, step: 0.5)
                        .frame(width: 150)
                        .tint(.black)
                }
            }

            settingRow(title: "Weekly pace") {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("\(flow.profile.weeklyLossRate.formatted(.number.precision(.fractionLength(1)))) kg/week")
                        .foregroundStyle(.secondary)
                    Slider(value: $flow.profile.weeklyLossRate, in: 0.1...1.0, step: 0.1)
                        .frame(width: 150)
                        .tint(.black)
                }
            }
        }
    }

    private var preferencesCard: some View {
        settingsCard(title: "Preferences") {
            settingRow(title: "Unit system") {
                Picker(localized("Unit system"), selection: $flow.profile.unit) {
                    ForEach(AppFlowViewModel.UnitSystem.allCases, id: \.self) { unit in
                        Text(localizedUnitTitle(for: unit)).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }

            settingRow(title: "Language") {
                Picker(localized("Language"), selection: $appLanguageRawValue) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            settingRow(title: "Activity level") {
                Picker(localized("Activity level"), selection: $flow.profile.activityLevel) {
                    Text(localized("Sedentary")).tag("Mostly sedentary")
                    Text(localized("Light")).tag("Lightly active")
                    Text(localized("Moderate")).tag("Moderately active")
                    Text(localized("High")).tag("Very active")
                }
                .pickerStyle(.menu)
            }

            settingRow(title: "Premium access") {
                Button {
                    showPaywall = true
                } label: {
                    Label(flow.profile.isPremium ? premiumStatusText : localized("Free plan"), systemImage: flow.profile.isPremium ? "crown.fill" : "lock.open")
                        .foregroundStyle(flow.profile.isPremium ? Color.orange : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var remindersCard: some View {
        settingsCard(title: "Reminders") {
            Toggle(localized("Meal logging reminders"), isOn: $notificationsEnabled)
            Toggle(localized("Water reminders"), isOn: $waterRemindersEnabled)
        }
    }

    private var aiCard: some View {
        settingsCard(title: "AI Tracking") {
            VStack(alignment: .leading, spacing: 12) {
                Text(localized("Recognition mode"))
                    .font(.subheadline.weight(.medium))

                Picker(localized("Recognition mode"), selection: $flow.recognitionMode) {
                    ForEach(RecognitionMode.allCases) { mode in
                        Text(localized(mode.localizationKey)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: flow.recognitionMode) { oldValue, newValue in
                    guard newValue == .cloudPreferred, !flow.profile.isPremium else { return }
                    flow.recognitionMode = oldValue
                    showPaywall = true
                }

                Text(localized(flow.recognitionMode.subtitleLocalizationKey))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            infoRow(title: "Recognition engine", value: localized(flow.recognitionMode.engineLocalizationKey))
            infoRow(title: "Camera status", value: localized("Gallery flow enabled"))
            infoRow(title: "Processing", value: localized(flow.recognitionMode.syncLocalizationKey))
            infoRow(title: "Cloud status", value: localized(flow.cloudRecognitionConfig.isReady ? "Connected" : "Not connected"))
        }
    }

    private var privacyCard: some View {
        settingsCard(title: "Data & Privacy") {
            VStack(alignment: .leading, spacing: 10) {
                Text(privacyDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(localized("Nutrition estimates may need manual correction."), systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized(title))
                .font(.headline)
            content()
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func settingRow<Content: View>(title: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack(alignment: .top) {
            Text(localized(title))
                .font(.subheadline)
            Spacer()
            trailing()
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(localized(title))
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized(title))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(hex: "#F4F4F5"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var privacyDescription: String {
        switch flow.recognitionMode {
        case .localOnly:
            return localized("Your meal log and photo analysis stay on-device. Health data sync and cloud backup are not enabled yet.")
        case .smartHybrid:
            return localized("Your meal log stays on-device. Photo analysis uses local recognition first and can fall back to cloud AI when that service is connected.")
        case .cloudPreferred:
            return localized("Your meal log stays on-device, but selected photos may be sent to a cloud AI service for recognition once that integration is connected.")
        }
    }

    private var premiumStatusText: String {
        guard let plan = flow.premiumPlan else { return localized("Active") }
        return String(format: localized("%@ active"), locale: locale, plan.title)
    }

    private func localizedUnitTitle(for unit: AppFlowViewModel.UnitSystem) -> String {
        switch unit {
        case .metric:
            return localized("Metric")
        case .imperial:
            return localized("Imperial")
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

struct PremiumPaywallSheet: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var selectedPlan: AppFlowViewModel.PremiumPlan = .annual

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(localized("Unlock NutriScan Pro"))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))

                    Text(localized("Get unlimited cloud recognition, smarter nutrition analysis, and premium coaching tools."))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        paywallLine("Unlimited cloud meal scans")
                        paywallLine("Premium AI analysis mode")
                        paywallLine("Advanced trends and coaching")
                        paywallLine("Priority access to new features")
                    }
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(spacing: 12) {
                        ForEach(AppFlowViewModel.PremiumPlan.allCases) { plan in
                            Button {
                                selectedPlan = plan
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 8) {
                                            Text(localized(plan.titleLocalizationKey))
                                                .font(.headline)
                                            Text(localized(plan.badgeLocalizationKey))
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.orange.opacity(0.12), in: Capsule())
                                        }
                                        Text(localizedPrice(for: plan))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: selectedPlan == plan ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedPlan == plan ? Color.black : .secondary)
                                }
                                .padding(18)
                                .background(selectedPlan == plan ? Color.black.opacity(0.08) : .white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if flow.storeConfigurationHint != nil {
                        Text(localized("StoreKit products are not available yet. Add the subscription product IDs in App Store Connect or a StoreKit config file."))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    if !flow.purchaseErrorMessage.isEmpty {
                        Text(flow.purchaseErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task {
                            let purchased = await flow.purchase(plan: selectedPlan)
                            if purchased {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if flow.purchaseInFlight {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(localized(flow.profile.isPremium ? "Update Plan" : "Unlock Pro"))
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .disabled(flow.purchaseInFlight)

                    HStack {
                        Button(localized("Restore Purchase")) {
                            Task {
                                await flow.restorePremium()
                                if flow.profile.isPremium {
                                    dismiss()
                                }
                            }
                        }
                        .foregroundStyle(.secondary)

                        Spacer()

                        if flow.profile.isPremium {
                            Link(localized("Manage Subscription"), destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                            .foregroundStyle(.red)
                        }
                    }
                    .font(.subheadline.weight(.medium))
                }
                .padding(20)
            }
            .background(Color(hex: "#FAFAF8").ignoresSafeArea())
            .navigationTitle(localized("NutriScan Pro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized("Done")) {
                        dismiss()
                    }
                }
            }
            .task {
                await flow.loadProductsIfNeeded()
            }
        }
    }

    private func paywallLine(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(localized(text))
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }

    private func localizedPrice(for plan: AppFlowViewModel.PremiumPlan) -> String {
        if let product = flow.availableProducts[plan] {
            return product.displayPrice
        }
        return localized(plan.priceLocalizationKey)
    }
}
