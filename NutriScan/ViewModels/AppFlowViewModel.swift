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
    private static let premiumKey = "nutriscan.profile.is_premium"
    private static let premiumPlanKey = "nutriscan.profile.premium_plan"
    private static let freeAIScansRemainingKey = "nutriscan.free_ai_scans_remaining"
    private static let defaultFreeAIScans = 2
    #if DEBUG
    private static let testAccountUnlimitedAIScans = true
    #else
    private static let testAccountUnlimitedAIScans = false
    #endif
    private static let annualProductID = "com.liuzhigang.nutriscan.pro.annual"
    private static let monthlyProductID = "com.liuzhigang.nutriscan.pro.monthly"

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

    struct UserProfile {
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

    enum UnitSystem: String, CaseIterable {
        case metric
        case imperial
    }

    @Published var currentScreen: Screen = .welcome
    @Published var profile = UserProfile() {
        didSet {
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
    @Published var availableProducts: [PremiumPlan: Product] = [:]
    @Published var purchaseInFlight = false
    @Published var purchaseErrorMessage = ""
    @Published var productsLoaded = false
    @Published private(set) var freeAIScansRemaining = defaultFreeAIScans

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

    init() {
        profile.isPremium = UserDefaults.standard.bool(forKey: Self.premiumKey)
        if let rawPlan = UserDefaults.standard.string(forKey: Self.premiumPlanKey) {
            premiumPlan = PremiumPlan(rawValue: rawPlan)
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
        case .welcome: currentScreen = .painPoints
        case .painPoints: currentScreen = .gender
        case .gender: currentScreen = .heightWeight
        case .heightWeight: currentScreen = .activity
        case .activity: currentScreen = .goal
        case .goal: currentScreen = .speed
        case .speed: currentScreen = .healthConnect
        case .healthConnect: currentScreen = .loading
        case .loading: currentScreen = .socialProof
        case .socialProof: currentScreen = .paywall
        default:
            break
        }
    }

    func skipPaywall() {
        currentScreen = .dashboard
    }

    func openCamera() {
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

    func activatePremium(plan: PremiumPlan) {
        profile.isPremium = true
        premiumPlan = plan
        UserDefaults.standard.set(plan.rawValue, forKey: Self.premiumPlanKey)
    }

    func restorePremium() async {
        purchaseErrorMessage = ""

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
        UserDefaults.standard.removeObject(forKey: Self.premiumPlanKey)
        if recognitionMode == .cloudPreferred {
            recognitionMode = .smartHybrid
        }
    }

    var hasPremiumAnalytics: Bool {
        profile.isPremium
    }

    var hasPremiumSuggestions: Bool {
        profile.isPremium
    }

    var hasPremiumCloudRecognition: Bool {
        profile.isPremium
    }

    var canUseAIScan: Bool {
        Self.testAccountUnlimitedAIScans || profile.isPremium || freeAIScansRemaining > 0
    }

    var aiScanAccessText: String {
        guard !Self.testAccountUnlimitedAIScans else {
            return AppLocalization.current("Unlimited AI scans included with Pro")
        }
        guard !profile.isPremium else {
            return AppLocalization.current("Unlimited AI scans included with Pro")
        }
        return AppLocalization.currentFormat("%d free AI scans left", freeAIScansRemaining)
    }

    func consumeFreeAIScanIfNeeded(for analysis: FoodAnalysis) {
        guard !Self.testAccountUnlimitedAIScans else { return }
        guard !profile.isPremium, analysis.source == .cloudAI, freeAIScansRemaining > 0 else { return }
        freeAIScansRemaining -= 1
        UserDefaults.standard.set(freeAIScansRemaining, forKey: Self.freeAIScansRemainingKey)
    }

    var annualDisplayPrice: String {
        availableProducts[.annual]?.displayPrice ?? PremiumPlan.annual.price
    }

    var monthlyDisplayPrice: String {
        availableProducts[.monthly]?.displayPrice ?? PremiumPlan.monthly.price
    }

    var storeConfigurationHint: String? {
        guard !productsLoaded else { return nil }
        return AppLocalization.current("StoreKit products are not available yet. Add the subscription product IDs in App Store Connect or a StoreKit config file.")
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
        purchaseErrorMessage = ""

        if !productsLoaded {
            await refreshStoreKitState()
        }

        guard let product = availableProducts[plan] else {
            purchaseErrorMessage = AppLocalization.current("Subscription product not found. Check your product IDs in App Store Connect.")
            return false
        }

        purchaseInFlight = true
        defer { purchaseInFlight = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                applyEntitlement(for: transaction.productID)
                await transaction.finish()
                return true
            case .userCancelled:
                return false
            case .pending:
                purchaseErrorMessage = AppLocalization.current("Purchase is pending approval.")
                return false
            @unknown default:
                purchaseErrorMessage = AppLocalization.current("Unknown purchase result.")
                return false
            }
        } catch {
            purchaseErrorMessage = error.localizedDescription
            return false
        }
    }

    private func refreshStoreKitState() async {
        await loadProducts()
        await refreshEntitlements()
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.annualProductID, Self.monthlyProductID])
            var mapped: [PremiumPlan: Product] = [:]

            for product in products {
                switch product.id {
                case Self.annualProductID:
                    mapped[.annual] = product
                case Self.monthlyProductID:
                    mapped[.monthly] = product
                default:
                    break
                }
            }

            availableProducts = mapped
            productsLoaded = !mapped.isEmpty
        } catch {
            availableProducts = [:]
            productsLoaded = false
            purchaseErrorMessage = error.localizedDescription
        }
    }

    private func refreshEntitlements() async {
        var resolvedPlan: PremiumPlan?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if let plan = plan(for: transaction.productID) {
                resolvedPlan = plan
            }
        }

        if let resolvedPlan {
            activatePremium(plan: resolvedPlan)
        } else {
            downgradeToFree()
        }
    }

    private func observeTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            applyEntitlement(for: transaction.productID)
            await transaction.finish()
        }
    }

    private func applyEntitlement(for productID: String) {
        guard let plan = plan(for: productID) else { return }
        activatePremium(plan: plan)
    }

    private func plan(for productID: String) -> PremiumPlan? {
        switch productID {
        case Self.annualProductID:
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
