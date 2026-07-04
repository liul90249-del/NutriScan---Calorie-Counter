import FirebaseAnalytics
import Foundation

enum AnalyticsService {
    static func logAppConfigured() {
        log("app_configured")
    }

    static func logOnboardingStep(_ step: String) {
        log("onboarding_step_completed", [
            "step": step
        ])
    }

    static func logGenderSelected(_ gender: String) {
        log("gender_selected", [
            "gender": normalized(gender)
        ])
    }

    static func logReviewPromptRequested(source: String) {
        log("review_prompt_requested", [
            "source": source
        ])
    }

    static func logSupportContactTapped() {
        log("support_contact_tapped")
    }

    static func logTabSelected(_ tab: AppFlowViewModel.MainTab) {
        log("tab_selected", [
            "tab": tab.rawValue
        ])
    }

    static func logCameraOpened() {
        log("camera_opened")
    }

    static func logScanModeSelected(_ mode: String) {
        log("scan_mode_selected", [
            "mode": normalized(mode)
        ])
    }

    static func logPhotoSelected(autoDetectedBarcode: Bool) {
        log("photo_selected", [
            "auto_detected_barcode": autoDetectedBarcode
        ])
    }

    static func logScanStarted(mode: String, recognitionMode: RecognitionMode) {
        log("scan_started", [
            "mode": normalized(mode),
            "recognition_mode": recognitionMode.rawValue
        ])
    }

    static func logScanCompleted(_ analysis: FoodAnalysis) {
        log("scan_completed", [
            "source": analysis.source.rawValue,
            "confidence_bucket": confidenceBucket(analysis.confidence),
            "needs_review": analysis.needsReview,
            "calorie_bucket": calorieBucket(analysis.calories)
        ])
    }

    static func logScanFailed(mode: String) {
        log("scan_failed", [
            "mode": normalized(mode)
        ])
    }

    static func logBarcodeDetected(source: String) {
        log("barcode_detected", [
            "source": source
        ])
    }

    static func logMealSaved(mealType: String, source: FoodAnalysisSource, calories: Int) {
        log("meal_saved", [
            "meal_type": normalized(mealType),
            "source": source.rawValue,
            "calorie_bucket": calorieBucket(calories)
        ])
    }

    static func logPaywallViewed(source: String) {
        log("paywall_viewed", [
            "source": source
        ])
    }

    static func logPurchaseStarted(plan: AppFlowViewModel.PremiumPlan) {
        log("purchase_started", [
            "plan": plan.rawValue
        ])
    }

    static func logPurchaseCompleted(plan: AppFlowViewModel.PremiumPlan) {
        log("purchase_completed", [
            "plan": plan.rawValue
        ])
    }

    static func logPurchaseFailed(plan: AppFlowViewModel.PremiumPlan, reason: String) {
        log("purchase_failed", [
            "plan": plan.rawValue,
            "reason": normalized(reason)
        ])
    }

    static func logRestorePurchaseTapped() {
        log("restore_purchase_tapped")
    }

    private static func log(_ name: String, _ parameters: [String: Any]? = nil) {
        Analytics.logEvent(name, parameters: parameters)
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func confidenceBucket(_ confidence: Double) -> String {
        switch confidence {
        case ..<0.5: return "low"
        case ..<0.8: return "medium"
        default: return "high"
        }
    }

    private static func calorieBucket(_ calories: Int) -> String {
        switch calories {
        case ..<250: return "under_250"
        case ..<500: return "250_499"
        case ..<800: return "500_799"
        default: return "800_plus"
        }
    }
}
