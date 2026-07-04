import SwiftUI
import StoreKit

struct ProfileView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    @Environment(\.requestReview) private var requestReview
    @AppStorage("nutriscan.notifications_enabled") private var notificationsEnabled = true
    @AppStorage("nutriscan.water_reminders_enabled") private var waterRemindersEnabled = false
    @AppStorage(AppLocalization.languageStorageKey) private var appLanguageRawValue = AppLanguage.system.rawValue
    @State private var showPaywall = false
    @State private var isRequestingHealthAccess = false
    private let waterReminderService = WaterReminderService()

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
        guard hasValidWeightLossGoal else {
            return maintenance
        }
        return max(1200, maintenance - deficit)
    }

    private var proteinTarget: Int {
        Int((flow.profile.weight * 1.6).rounded())
    }

    private var progressSummary: String {
        let delta = flow.profile.weight - flow.profile.goalWeight
        if !hasValidWeightLossGoal {
            return localized("Set a goal weight below your current weight for a weight loss plan.")
        }
        if delta <= 0.5 {
            return localized("You are at or below your target weight.")
        }
        return String(
            format: localized("%@ kg to goal"),
            locale: locale,
            delta.formatted(.number.precision(.fractionLength(1)))
        )
    }

    private var hasValidWeightLossGoal: Bool {
        flow.profile.goalWeight < flow.profile.weight
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
                    supportCard
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

            if !hasValidWeightLossGoal {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                    Text(localized("Goal weight must be lower than current weight for a weight loss plan."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                        Text(localizedLanguageTitle(for: language)).tag(language.rawValue)
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

            settingRow(title: "Apple Health") {
                Button {
                    Task {
                        isRequestingHealthAccess = true
                        try? await HealthKitService.requestAuthorization()
                        isRequestingHealthAccess = false
                    }
                } label: {
                    Text(localized(isRequestingHealthAccess ? "Connecting..." : "Connect"))
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(isRequestingHealthAccess)
            }

            settingRow(title: "Premium access") {
                Button {
                    AnalyticsService.logPaywallViewed(source: "profile")
                    showPaywall = true
                } label: {
                    VStack(alignment: .trailing, spacing: 4) {
                        Label(flow.hasActivePremium ? premiumStatusText : localized("Free plan"), systemImage: flow.hasActivePremium ? "crown.fill" : "lock.open")
                            .foregroundStyle(flow.hasActivePremium ? Color.orange : .secondary)
                        if let expirationText = premiumExpirationText {
                            Text(expirationText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var remindersCard: some View {
        settingsCard(title: "Reminders") {
            Toggle(localized("Meal logging reminders"), isOn: $notificationsEnabled)
            Toggle(localized("Water reminders"), isOn: $waterRemindersEnabled)
                .onChange(of: waterRemindersEnabled) { _, enabled in
                    Task {
                        if enabled {
                            let didEnable = (try? await waterReminderService.enableDailyWaterReminders(profile: flow.profile, locale: locale)) ?? false
                            if !didEnable {
                                waterRemindersEnabled = false
                            }
                        } else {
                            await waterReminderService.disableDailyWaterReminders()
                        }
                    }
                }
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
                    guard newValue == .cloudPreferred, !flow.hasActivePremium else { return }
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
                Link(localized("Privacy Policy"), destination: URL(string: NutriScanBackendConfig.legalPrivacyPolicyURL)!)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var supportCard: some View {
        settingsCard(title: "Support") {
            settingRow(title: "Contact Us") {
                Link(destination: URL(string: NutriScanBackendConfig.supportEmailURL)!) {
                    Label(NutriScanBackendConfig.supportEmail, systemImage: "envelope")
                        .font(.subheadline.weight(.semibold))
                }
                .simultaneousGesture(TapGesture().onEnded {
                    AnalyticsService.logSupportContactTapped()
                })
            }

            settingRow(title: "Rate Us") {
                Button {
                    AnalyticsService.logReviewPromptRequested(source: "profile")
                    requestReview()
                } label: {
                    Label(localized("Rate NutriScan"), systemImage: "star")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
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
        HStack(alignment: .center, spacing: 16) {
            Text(localized(title))
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
                .frame(width: 170, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 36)
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
            return localized("Your meal log and photo analysis stay on-device. Apple Health active energy is read only for your calorie budget.")
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

    private var premiumExpirationText: String? {
        guard flow.hasActivePremium, let expirationDate = flow.premiumExpirationDate else { return nil }
        let formattedDate = expirationDate.formatted(
            .dateTime
                .year()
                .month(.abbreviated)
                .day()
                .locale(locale)
        )
        return String(format: localized("Expires on %@"), locale: locale, formattedDate)
    }

    private func localizedUnitTitle(for unit: AppFlowViewModel.UnitSystem) -> String {
        switch unit {
        case .metric:
            return localized("Metric")
        case .imperial:
            return localized("Imperial")
        }
    }

    private func localizedLanguageTitle(for language: AppLanguage) -> String {
        switch language {
        case .system:
            return localized("System")
        default:
            return language.displayName
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
    @State private var showDiscountOffer = false

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
                                        if plan == .annual, let trial = flow.annualFreeTrialText {
                                            Text(trial)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(Color(hex: "#2E7D53"))
                                        }
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
                            } else if flow.consumePendingDiscountOffer() {
                                showDiscountOffer = true
                            }
                        }
                    } label: {
                        HStack {
                            if flow.purchaseInFlight {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(purchaseButtonTitle)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .disabled(flow.purchaseInFlight)

                    VStack(spacing: 12) {
                        Button(localized("Restore Purchase")) {
                            Task {
                                await flow.restorePremium()
                                if flow.hasActivePremium {
                                    dismiss()
                                }
                            }
                        }
                        .foregroundStyle(.secondary)

                        if flow.hasActivePremium {
                            Link(localized("Manage Subscription"), destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Link(localized("Privacy Policy"), destination: URL(string: NutriScanBackendConfig.legalPrivacyPolicyURL)!)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Link(localized("Terms of Use"), destination: URL(string: NutriScanBackendConfig.legalTermsOfUseURL)!)
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
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
            .sheet(isPresented: $showDiscountOffer) {
                DiscountOfferSheet(onPurchased: { dismiss() })
                    .environmentObject(flow)
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

    private var purchaseButtonTitle: String {
        if flow.hasActivePremium { return localized("Update Plan") }
        if selectedPlan == .annual, flow.annualFreeTrialText != nil { return localized("Start free trial") }
        return localized("Unlock Pro")
    }

    private func localizedPrice(for plan: AppFlowViewModel.PremiumPlan) -> String {
        if let product = flow.availableProducts[plan] {
            return product.displayPrice
        }
        return localized(plan.priceLocalizationKey)
    }
}

// MARK: - Win-back discount offer

/// One-time win-back offer shown after the user cancels the system payment
/// sheet. Display-only discount for now — the CTA purchases the existing annual
/// product. All copy is localized. The marketing prices are placeholder strings
/// to be replaced once a real discounted StoreKit product is wired up.
struct DiscountOfferSheet: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// Invoked after a successful purchase so the presenting paywall can close too.
    var onPurchased: () -> Void

    @State private var remaining: Double = 3 * 60
    @State private var wheelRotation: Double = 0
    @State private var trialEnabled = true

    private let countdown = Timer.publish(every: 0.031, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                countdownLine
                    .padding(.top, 8)

                Text(localized("Your exclusive limited-time offer"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PromoWheel(rotation: wheelRotation, saveLabel: localized("Save"), topDiscount: discountPercent)
                    .frame(width: 260, height: 260)
                    .padding(.vertical, 4)

                priceHeadline

                Text(localizedFormat("This is your one-time exclusive offer. Choose the annual plan and save %lld%%.", discountPercent))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                trialToggle
                planCard
                purchaseButton
                noPaymentFooter
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(Color(hex: "#FAFAF8").ignoresSafeArea())
        .overlay(alignment: .topLeading) { closeButton }
        .onReceive(countdown) { _ in
            if remaining > 0 { remaining = max(0, remaining - 0.031) }
        }
        .onAppear {
            AnalyticsService.logPaywallViewed(source: "discount_offer")
            withAnimation(.easeOut(duration: 2.6)) { wheelRotation = 360 * 3 }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.top, 8)
    }

    private var countdownLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundStyle(Color.orange)
            Text(localizedFormat("Limited-time offer ends in %@", countdownText))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: "#C2410C"))
                .monospacedDigit()
        }
    }

    private var countdownText: String {
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        let millis = Int((remaining - floor(remaining)) * 1000)
        return String(format: "%02d:%02d:%03d", minutes, seconds, millis)
    }

    private var priceHeadline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(originalWeeklyPrice)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .strikethrough(true, color: .secondary)
            Text(discountWeeklyPrice)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    /// Regular annual price expressed per week (struck through). Falls back to a
    /// placeholder until the annual product loads.
    private var originalWeeklyPrice: String {
        if let annual = flow.availableProducts[.annual] {
            return weeklyPrice(from: annual)
        }
        return localized("$1.73 / week")
    }

    /// Discounted annual price per week. Falls back to a placeholder until the
    /// promo product is configured/loaded.
    private var discountWeeklyPrice: String {
        if let promo = flow.discountedAnnualProduct {
            return weeklyPrice(from: promo)
        }
        return localized("$0.35 / week")
    }

    private func weeklyPrice(from product: Product) -> String {
        let perWeek = product.price / 52
        return localizedFormat("%@ / week", perWeek.formatted(product.priceFormatStyle))
    }

    private var trialToggle: some View {
        Toggle(isOn: $trialEnabled) {
            Text(localized(trialEnabled ? "Free trial enabled" : "Enable free trial"))
                .font(.headline)
        }
        .tint(Color(hex: "#34C759"))
        .padding(.horizontal, 4)
    }

    private var planCard: some View {
        VStack(spacing: 0) {
            Text(localized("3-day free trial"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: "#2E7D53"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(hex: "#D8EFDE"))

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("Annual plan"))
                        .font(.title3.weight(.bold))
                    Text(planDetailLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(discountWeeklyPrice)
                    .font(.title3.weight(.bold))
            }
            .padding(18)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(hex: "#34C759").opacity(0.5), lineWidth: 1.5)
        )
    }

    private var planDetailLine: String {
        if let promo = flow.discountedAnnualProduct {
            return localizedFormat("12 months · %@", promo.displayPrice)
        }
        return localized("12 months · US$17.99")
    }

    /// Real discount percentage computed from the live StoreKit prices
    /// (regular annual vs. promo annual). Falls back to 40 until both load.
    private var discountPercent: Int {
        guard let annual = flow.availableProducts[.annual],
              let promo = flow.discountedAnnualProduct,
              annual.price > 0 else { return 40 }
        let ratio = (annual.price - promo.price) / annual.price * 100
        let pct = Int(NSDecimalNumber(decimal: ratio).doubleValue.rounded())
        return min(max(pct, 1), 99)
    }

    private var purchaseButton: some View {
        Button {
            Task {
                let purchased = await flow.purchaseDiscountedAnnual()
                if purchased { onPurchased() }
            }
        } label: {
            HStack(spacing: 10) {
                if flow.purchaseInFlight {
                    ProgressView().tint(.white)
                }
                Text(localized("Start free trial"))
                    .font(.headline)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#43C06B"), Color(hex: "#2E9E56")],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: Capsule()
            )
            .shadow(color: Color(hex: "#2E9E56").opacity(0.35), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(flow.purchaseInFlight)
    }

    private var noPaymentFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.bold))
            Text(localized("No payment due now"))
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.secondary)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }
}

/// Decorative fortune wheel that spins once and settles on the 80% wedge (which
/// sits at the top under the fixed pointer). Purely visual — no gambling logic.
private struct PromoWheel: View {
    var rotation: Double
    var saveLabel: String
    /// The real discount shown on the winning (top) wedge under the pointer.
    var topDiscount: Int

    private var values: [Int] { [topDiscount, 10, 20, 30, 50] }
    private let shades = ["#4E9E6A", "#EAF4EC", "#C9E4CF", "#A7D4B2", "#82C398"]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2

            ZStack {
                // Rotating wheel: wedges + labels
                ZStack {
                    ForEach(values.indices, id: \.self) { index in
                        PieSlice(startAngle: startAngle(index), endAngle: endAngle(index))
                            .fill(Color(hex: shades[index]))
                    }

                    ForEach(values.indices, id: \.self) { index in
                        VStack(spacing: 2) {
                            Text(saveLabel)
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(values[index])%")
                                .font(.system(size: 20, weight: .heavy))
                        }
                        .foregroundStyle(index == 0 ? Color.white : Color(hex: "#1F3D2C"))
                        .rotationEffect(.degrees(labelRotation(index)))
                        .position(labelPosition(index, radius: radius, center: CGPoint(x: radius, y: radius)))
                    }
                }
                .rotationEffect(.degrees(rotation))
                .overlay(
                    Circle().strokeBorder(Color(hex: "#37764E"), lineWidth: 8)
                )

                // Fixed center hub
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "#F2C55A"), Color(hex: "#C8912A")],
                            center: .center,
                            startRadius: 2,
                            endRadius: radius * 0.16
                        )
                    )
                    .frame(width: radius * 0.3, height: radius * 0.3)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                // Fixed pointer + crown at top
                Image(systemName: "triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(hex: "#E7B54A"))
                    .rotationEffect(.degrees(180))
                    .position(x: radius, y: radius * 0.16)

                Image(systemName: "crown.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: "#E7B54A"))
                    .position(x: radius, y: -radius * 0.06)
            }
        }
    }

    private func startAngle(_ index: Int) -> Angle {
        .degrees(-90 - 36 + Double(index) * 72)
    }

    private func endAngle(_ index: Int) -> Angle {
        .degrees(-90 + 36 + Double(index) * 72)
    }

    private func centerAngleDegrees(_ index: Int) -> Double {
        -90 + Double(index) * 72
    }

    private func labelRotation(_ index: Int) -> Double {
        centerAngleDegrees(index) + 90
    }

    private func labelPosition(_ index: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let rad = centerAngleDegrees(index) * .pi / 180
        let labelRadius = radius * 0.6
        return CGPoint(
            x: center.x + cos(rad) * labelRadius,
            y: center.y + sin(rad) * labelRadius
        )
    }
}

private struct PieSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()
        return path
    }
}
