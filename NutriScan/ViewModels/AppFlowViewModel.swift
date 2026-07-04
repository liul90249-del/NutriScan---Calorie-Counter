import Foundation
import StoreKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"
    case spanish = "es"
    case italian = "it"

    var id: String { rawValue }

    var localeIdentifier: String {
        locale?.identifier ?? Locale.autoupdatingCurrent.identifier
    }

    var locale: Locale? {
        switch self {
        case .system:
            return nil
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        case .japanese:
            return Locale(identifier: "ja")
        case .spanish:
            return Locale(identifier: "es")
        case .italian:
            return Locale(identifier: "it")
        }
    }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .japanese:
            return "日本語"
        case .spanish:
            return "Español"
        case .italian:
            return "Italiano"
        }
    }
}

@MainActor
final class AppFlowViewModel: ObservableObject {
    private static let completedOnboardingKey = "nutriscan.onboarding.completed"
    private static let profileStorageKey = "nutriscan.profile.payload"
    private static let premiumKey = "nutriscan.profile.is_premium"
    private static let premiumPlanKey = "nutriscan.profile.premium_plan"
    private static let premiumExpirationDateKey = "nutriscan.profile.premium_expiration_date"
    private static let freeAIScansRemainingKey = "nutriscan.free_ai_scans_remaining"
    private static let bodyDataReviewPromptedKey = "nutriscan.review.body_data_prompted"
    private static let defaultFreeAIScans = 2
    #if DEBUG
    private static let debugPremiumSimulationKey = "nutriscan.debug.premium_simulation"
    private static let testAccountUnlimitedAIScans = true
    #else
    private static let testAccountUnlimitedAIScans = false
    #endif
    private static let annualProductID = "com.liuzhigang.nutriscan.pro.annuala"
    private static let monthlyProductID = "com.liuzhigang.nutriscan.pro.monthlya"
    /// Discounted annual product surfaced only in the win-back offer. Entitles
    /// the same annual premium; create this ID in App Store Connect.
    private static let discountedAnnualProductID = "com.liuzhigang.nutriscan.pro.annualpromoa"

    enum Screen: Hashable {
        case welcome
        case painPoints
        case gender
        case heightWeight
        case activity
        case goal
        case speed
        case healthConnect
        case loading
        case socialProof
        case paywall
        case dashboard
        case camera
        case foodConfirmation
    }

    struct UserProfile: Codable {
        var painPoints: Set<String> = []
        var gender: String = ""
        var height: Double = 170
        var weight: Double = 75
        var activityLevel: String = ""
        var goalWeight: Double = 70
        var weeklyLossRate: Double = 0.5
        var unit: UnitSystem = .metric
        var isPremium: Bool = false
    }

    enum PremiumPlan: String, CaseIterable, Identifiable {
        case annual
        case monthly

        var id: String { rawValue }

        var title: String {
            AppLocalization.current(titleLocalizationKey)
        }

        var price: String {
            AppLocalization.current(priceLocalizationKey)
        }

        var badge: String {
            AppLocalization.current(badgeLocalizationKey)
        }

        var titleLocalizationKey: String {
            switch self {
            case .annual: return "Annual Pro"
            case .monthly: return "Monthly Pro"
            }
        }

        var priceLocalizationKey: String {
            switch self {
            case .annual: return "$29.99 / year"
            case .monthly: return "$5.99 / month"
            }
        }

        var badgeLocalizationKey: String {
            switch self {
            case .annual: return "Best value"
            case .monthly: return "Flexible"
            }
        }
    }

    enum UnitSystem: String, CaseIterable, Codable {
        case metric
        case imperial
    }

    @Published var currentScreen: Screen = UserDefaults.standard.bool(forKey: completedOnboardingKey) ? .dashboard : .welcome
    @Published var profile = UserProfile() {
        didSet {
            saveProfile()
            UserDefaults.standard.set(profile.isPremium, forKey: Self.premiumKey)
        }
    }
    @Published var recognizedFood: FoodAnalysis?
    @Published var selectedTab: MainTab = .today
    @Published var recognitionMode: RecognitionMode = .smartHybrid
    @Published private(set) var cloudEndpoint = NutriScanBackendConfig.foodAnalysisEndpoint
    @Published private(set) var cloudAPIKey = NutriScanBackendConfig.clientToken
    @Published private(set) var cloudRecognitionEnabled = true
    @Published var premiumPlan: PremiumPlan? = nil
    @Published private(set) var premiumExpirationDate: Date? = nil
    @Published var availableProducts: [PremiumPlan: Product] = [:]
    /// Discounted annual product for the win-back offer, if configured/loaded.
    @Published var discountedAnnualProduct: Product?
    @Published var purchaseInFlight = false
    @Published var purchaseErrorMessage = ""
    /// True when the most recent `purchase(_:)` ended because the user cancelled
    /// the system payment sheet — used to offer a one-time win-back discount.
    private var lastPurchaseWasUserCancel = false
    @Published var productsLoaded = false
    /// Whether the user can still redeem the annual product's introductory free
    /// trial (false once they've used it before). Refreshed when products load.
    @Published var isEligibleForAnnualIntroOffer = true
    @Published var shouldRequestBodyDataReview = false
    @Published private(set) var freeAIScansRemaining = defaultFreeAIScans
    #if DEBUG
    @Published private(set) var isDebugPremiumSimulationEnabled = UserDefaults.standard.bool(forKey: debugPremiumSimulationKey)
    #endif

    enum MainTab: String, CaseIterable {
        case today
        case analysis
        case suggestions
        case settings
    }

    var recognitionService: FoodRecognitionServicing {
        FoodRecognitionServiceFactory.makeService(
            for: recognitionMode,
            cloudConfig: cloudRecognitionConfig
        )
    }

    var cloudRecognitionConfig: CloudRecognitionConfig {
        CloudRecognitionConfig(
            endpoint: URL(string: cloudEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
            apiKey: cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: cloudRecognitionEnabled
        )
    }

    var cloudStatusText: String {
        cloudRecognitionConfig.isReady ? AppLocalization.current("Connected") : AppLocalization.current("Not connected")
    }

    var hasActivePremium: Bool {
        guard profile.isPremium else { return false }
        guard let premiumExpirationDate else { return true }
        return premiumExpirationDate > Date()
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.profileStorageKey),
           let savedProfile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = savedProfile
        }
        profile.isPremium = UserDefaults.standard.bool(forKey: Self.premiumKey)
        if let rawPlan = UserDefaults.standard.string(forKey: Self.premiumPlanKey) {
            premiumPlan = PremiumPlan(rawValue: rawPlan)
        }
        if let savedExpirationDate = UserDefaults.standard.object(forKey: Self.premiumExpirationDateKey) as? Date {
            premiumExpirationDate = savedExpirationDate
        }
        if UserDefaults.standard.object(forKey: Self.freeAIScansRemainingKey) == nil {
            UserDefaults.standard.set(Self.defaultFreeAIScans, forKey: Self.freeAIScansRemainingKey)
        }
        freeAIScansRemaining = UserDefaults.standard.integer(forKey: Self.freeAIScansRemainingKey)

        Task {
            await refreshStoreKitState()
            await observeTransactions()
        }
    }

    func goToNextOnboardingStep() {
        switch currentScreen {
        case .welcome:
            AnalyticsService.logOnboardingStep("welcome")
            currentScreen = .painPoints
        case .painPoints:
            AnalyticsService.logOnboardingStep("pain_points")
            currentScreen = .gender
        case .gender:
            AnalyticsService.logOnboardingStep("gender")
            currentScreen = .heightWeight
        case .heightWeight:
            AnalyticsService.logOnboardingStep("height_weight")
            currentScreen = .activity
            requestBodyDataReviewIfNeeded()
        case .activity:
            AnalyticsService.logOnboardingStep("activity")
            currentScreen = .goal
        case .goal:
            AnalyticsService.logOnboardingStep("goal")
            currentScreen = .speed
        case .speed:
            AnalyticsService.logOnboardingStep("speed")
            currentScreen = .healthConnect
        case .healthConnect:
            AnalyticsService.logOnboardingStep("health_connect")
            currentScreen = .loading
        case .loading:
            AnalyticsService.logOnboardingStep("loading")
            currentScreen = .socialProof
        case .socialProof:
            AnalyticsService.logOnboardingStep("social_proof")
            AnalyticsService.logPaywallViewed(source: "onboarding")
            currentScreen = .paywall
        default:
            break
        }
    }

    func skipPaywall() {
        UserDefaults.standard.set(true, forKey: Self.completedOnboardingKey)
        currentScreen = .dashboard
    }

    func openCamera() {
        AnalyticsService.logCameraOpened()
        currentScreen = .camera
    }

    func closeCamera() {
        currentScreen = .dashboard
    }

    func showFoodConfirmation(_ analysis: FoodAnalysis) {
        recognizedFood = analysis
        currentScreen = .foodConfirmation
    }

    func finishFoodConfirmation() {
        recognizedFood = nil
        currentScreen = .dashboard
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.completedOnboardingKey)
        currentScreen = .dashboard
    }

    func markBodyDataReviewRequestHandled() {
        AnalyticsService.logReviewPromptRequested(source: "body_data_completed")
        UserDefaults.standard.set(true, forKey: Self.bodyDataReviewPromptedKey)
        shouldRequestBodyDataReview = false
    }

    func activatePremium(plan: PremiumPlan, expirationDate: Date? = nil) {
        profile.isPremium = true
        premiumPlan = plan
        premiumExpirationDate = expirationDate
        UserDefaults.standard.set(plan.rawValue, forKey: Self.premiumPlanKey)
        if let expirationDate {
            UserDefaults.standard.set(expirationDate, forKey: Self.premiumExpirationDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.premiumExpirationDateKey)
        }
    }

    func restorePremium() async {
        purchaseErrorMessage = ""
        AnalyticsService.logRestorePurchaseTapped()

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func downgradeToFree() {
        profile.isPremium = false
        premiumPlan = nil
        premiumExpirationDate = nil
        UserDefaults.standard.removeObject(forKey: Self.premiumPlanKey)
        UserDefaults.standard.removeObject(forKey: Self.premiumExpirationDateKey)
        #if DEBUG
        isDebugPremiumSimulationEnabled = false
        UserDefaults.standard.set(false, forKey: Self.debugPremiumSimulationKey)
        #endif
        if recognitionMode == .cloudPreferred {
            recognitionMode = .smartHybrid
        }
    }

    #if DEBUG
    func enableDebugPremiumSimulation() {
        let expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        activatePremium(plan: .monthly, expirationDate: expirationDate)
        isDebugPremiumSimulationEnabled = true
        UserDefaults.standard.set(true, forKey: Self.debugPremiumSimulationKey)
    }
    #endif

    var hasPremiumAnalytics: Bool {
        hasActivePremium
    }

    var hasPremiumSuggestions: Bool {
        hasActivePremium
    }

    var hasPremiumCloudRecognition: Bool {
        hasActivePremium
    }

    var canUseAIScan: Bool {
        Self.testAccountUnlimitedAIScans || hasActivePremium || freeAIScansRemaining > 0
    }

    var aiScanAccessText: String {
        guard !Self.testAccountUnlimitedAIScans else {
            return AppLocalization.current("Unlimited AI scans included with Pro")
        }
        guard !hasActivePremium else {
            return AppLocalization.current("Unlimited AI scans included with Pro")
        }
        return AppLocalization.currentFormat("%d free AI scans left", freeAIScansRemaining)
    }

    func selectGender(_ gender: String) {
        profile.gender = gender
        AnalyticsService.logGenderSelected(gender)

        switch gender {
        case "Male":
            profile.height = 175
            profile.weight = 75
            profile.goalWeight = 70
        case "Female":
            profile.height = 162
            profile.weight = 58
            profile.goalWeight = 54
        default:
            profile.height = 170
            profile.weight = 65
            profile.goalWeight = 60
        }
    }

    func consumeFreeAIScanIfNeeded(for analysis: FoodAnalysis) {
        guard !Self.testAccountUnlimitedAIScans else { return }
        guard !hasActivePremium, analysis.source == .cloudAI, freeAIScansRemaining > 0 else { return }
        freeAIScansRemaining -= 1
        UserDefaults.standard.set(freeAIScansRemaining, forKey: Self.freeAIScansRemainingKey)
    }

    private func saveProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Self.profileStorageKey)
    }

    private func requestBodyDataReviewIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.bodyDataReviewPromptedKey) else { return }
        shouldRequestBodyDataReview = true
    }

    var annualDisplayPrice: String {
        availableProducts[.annual]?.displayPrice ?? PremiumPlan.annual.price
    }

    /// The annual product's introductory offer (free trial), if configured in
    /// App Store Connect / the StoreKit config file.
    var annualIntroductoryOffer: Product.SubscriptionOffer? {
        availableProducts[.annual]?.subscription?.introductoryOffer
    }

    /// True when the annual plan currently offers a redeemable free trial.
    var annualHasFreeTrial: Bool {
        guard let offer = annualIntroductoryOffer, offer.paymentMode == .freeTrial else { return false }
        return isEligibleForAnnualIntroOffer
    }

    /// Localized label for the annual free trial, e.g. "3-day free trial".
    /// Returns nil when no redeemable trial is available.
    var annualFreeTrialText: String? {
        guard annualHasFreeTrial, let offer = annualIntroductoryOffer else { return nil }
        return Self.freeTrialText(for: offer.period)
    }

    private static func freeTrialText(for period: Product.SubscriptionPeriod) -> String {
        let count = period.value
        let key: String
        switch period.unit {
        case .day: key = "%lld-day free trial"
        case .week: key = "%lld-week free trial"
        case .month: key = "%lld-month free trial"
        case .year: key = "%lld-year free trial"
        @unknown default: key = "%lld-day free trial"
        }
        return AppLocalization.currentFormat(key, count)
    }

    var monthlyDisplayPrice: String {
        availableProducts[.monthly]?.displayPrice ?? PremiumPlan.monthly.price
    }

    var storeConfigurationHint: String? {
        #if DEBUG
        guard !productsLoaded else { return nil }
        return AppLocalization.current("StoreKit products are not available yet. Add the subscription product IDs in App Store Connect or a StoreKit config file.")
        #else
        return nil
        #endif
    }

    func priceText(for plan: PremiumPlan) -> String {
        switch plan {
        case .annual:
            return annualDisplayPrice
        case .monthly:
            return monthlyDisplayPrice
        }
    }

    func loadProductsIfNeeded() async {
        guard !productsLoaded else { return }
        await refreshStoreKitState()
    }

    func purchase(plan: PremiumPlan) async -> Bool {
        if !productsLoaded {
            await refreshStoreKitState()
        }

        guard let product = availableProducts[plan] else {
            purchaseErrorMessage = AppLocalization.current("Subscription product not found. Check your product IDs in App Store Connect.")
            AnalyticsService.logPurchaseFailed(plan: plan, reason: "product_not_found")
            return false
        }

        return await purchase(product: product, plan: plan)
    }

    /// Purchases the discounted annual product used by the win-back offer.
    /// Falls back to the regular annual product if the promo isn't configured,
    /// so the offer's CTA always does something.
    func purchaseDiscountedAnnual() async -> Bool {
        if !productsLoaded {
            await refreshStoreKitState()
        }

        guard let product = discountedAnnualProduct else {
            return await purchase(plan: .annual)
        }

        return await purchase(product: product, plan: .annual)
    }

    private func purchase(product: Product, plan: PremiumPlan) async -> Bool {
        purchaseErrorMessage = ""
        lastPurchaseWasUserCancel = false
        AnalyticsService.logPurchaseStarted(plan: plan)

        purchaseInFlight = true
        defer { purchaseInFlight = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                applyEntitlement(for: transaction)
                await transaction.finish()
                AnalyticsService.logPurchaseCompleted(plan: plan)
                return true
            case .userCancelled:
                lastPurchaseWasUserCancel = true
                AnalyticsService.logPurchaseFailed(plan: plan, reason: "user_cancelled")
                return false
            case .pending:
                purchaseErrorMessage = AppLocalization.current("Purchase is pending approval.")
                AnalyticsService.logPurchaseFailed(plan: plan, reason: "pending")
                return false
            @unknown default:
                purchaseErrorMessage = AppLocalization.current("Unknown purchase result.")
                AnalyticsService.logPurchaseFailed(plan: plan, reason: "unknown")
                return false
            }
        } catch {
            purchaseErrorMessage = error.localizedDescription
            AnalyticsService.logPurchaseFailed(plan: plan, reason: String(describing: type(of: error)))
            return false
        }
    }

    /// Returns `true` whenever the user just cancelled the system payment sheet,
    /// signalling that the win-back discount offer should be shown. Re-triggers
    /// on every cancellation (the offer may appear multiple times).
    func consumePendingDiscountOffer() -> Bool {
        guard lastPurchaseWasUserCancel else { return false }
        lastPurchaseWasUserCancel = false
        return true
    }

    private func refreshStoreKitState() async {
        await loadProducts()
        await refreshEntitlements()
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.annualProductID, Self.monthlyProductID, Self.discountedAnnualProductID])
            var mapped: [PremiumPlan: Product] = [:]
            var promo: Product?

            for product in products {
                switch product.id {
                case Self.annualProductID:
                    mapped[.annual] = product
                case Self.monthlyProductID:
                    mapped[.monthly] = product
                case Self.discountedAnnualProductID:
                    promo = product
                default:
                    break
                }
            }

            availableProducts = mapped
            discountedAnnualProduct = promo
            productsLoaded = !mapped.isEmpty

            if let subscription = mapped[.annual]?.subscription {
                isEligibleForAnnualIntroOffer = await subscription.isEligibleForIntroOffer
            } else {
                isEligibleForAnnualIntroOffer = false
            }
        } catch {
            availableProducts = [:]
            productsLoaded = false
            purchaseErrorMessage = error.localizedDescription
        }
    }

    private func refreshEntitlements() async {
        var resolvedPlan: PremiumPlan?
        var resolvedExpirationDate: Date?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard let plan = plan(for: transaction.productID),
                  isActiveEntitlement(transaction) else {
                continue
            }

            if shouldPrefer(transactionExpirationDate: transaction.expirationDate, over: resolvedExpirationDate) {
                resolvedPlan = plan
                resolvedExpirationDate = transaction.expirationDate
            }
        }

        if let resolvedPlan {
            activatePremium(plan: resolvedPlan, expirationDate: resolvedExpirationDate)
        } else {
            downgradeToFree()
        }
    }

    private func observeTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            if isActiveEntitlement(transaction) {
                applyEntitlement(for: transaction)
            } else {
                await refreshEntitlements()
            }
            await transaction.finish()
        }
    }

    private func applyEntitlement(for transaction: Transaction) {
        guard let plan = plan(for: transaction.productID),
              isActiveEntitlement(transaction) else {
            return
        }
        activatePremium(plan: plan, expirationDate: transaction.expirationDate)
    }

    private func isActiveEntitlement(_ transaction: Transaction) -> Bool {
        guard transaction.revocationDate == nil else { return false }
        guard let expirationDate = transaction.expirationDate else { return true }
        return expirationDate > Date()
    }

    private func shouldPrefer(transactionExpirationDate: Date?, over currentExpirationDate: Date?) -> Bool {
        switch (transactionExpirationDate, currentExpirationDate) {
        case let (new?, current?):
            return new > current
        case (_?, nil):
            return true
        case (nil, nil):
            return true
        case (nil, _?):
            return false
        }
    }

    private func plan(for productID: String) -> PremiumPlan? {
        switch productID {
        case Self.annualProductID, Self.discountedAnnualProductID:
            return .annual
        case Self.monthlyProductID:
            return .monthly
        default:
            return nil
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }
}

private extension AppFlowViewModel {
    enum StoreError: LocalizedError {
        case failedVerification

        var errorDescription: String? {
            switch self {
            case .failedVerification:
                return AppLocalization.current("StoreKit transaction verification failed.")
            }
        }
    }
}
