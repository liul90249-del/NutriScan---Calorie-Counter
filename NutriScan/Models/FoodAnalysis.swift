import Foundation

enum FoodAnalysisSource: String, Hashable {
    case localEstimate
    case hybridFallback
    case cloudAI
    case barcode

    var resultLabel: String {
        localizedResultLabel(locale: AppLocalization.currentLocale)
    }

    func localizedResultLabel(locale: Locale) -> String {
        switch self {
        case .localEstimate:
            return AppLocalization.localized("Local estimate", locale: locale)
        case .hybridFallback:
            return AppLocalization.localized("Fallback estimate", locale: locale)
        case .cloudAI:
            return AppLocalization.localized("Cloud AI analysis", locale: locale)
        case .barcode:
            return AppLocalization.localized("Barcode nutrition", locale: locale)
        }
    }

    var confidenceLabel: String {
        localizedConfidenceLabel(locale: AppLocalization.currentLocale)
    }

    func localizedConfidenceLabel(locale: Locale) -> String {
        switch self {
        case .cloudAI:
            return AppLocalization.localized("AI confidence", locale: locale)
        case .barcode:
            return AppLocalization.localized("Database match", locale: locale)
        case .localEstimate, .hybridFallback:
            return AppLocalization.localized("Estimate confidence", locale: locale)
        }
    }

    var summaryText: String {
        localizedSummaryText(locale: AppLocalization.currentLocale)
    }

    func localizedSummaryText(locale: Locale) -> String {
        switch self {
        case .localEstimate:
            return AppLocalization.localized("This is a rough on-device estimate based on common meal patterns.", locale: locale)
        case .hybridFallback:
            return AppLocalization.localized("Cloud AI was unavailable, so this result falls back to a local estimate.", locale: locale)
        case .cloudAI:
            return AppLocalization.localized("This result was analyzed by cloud AI and may still need manual edits.", locale: locale)
        case .barcode:
            return AppLocalization.localized("This result uses packaged food nutrition data from a barcode database.", locale: locale)
        }
    }
}

struct FoodAnalysis: Identifiable, Hashable {
    let id = UUID()
    let foodName: String
    let confidence: Double
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let highlights: [String]
    let source: FoodAnalysisSource
    let needsReview: Bool
    let identifiedItems: [String]
    let portionDescription: String
    let localizedDisplayFields: Set<LocalizedDisplayField>

    enum LocalizedDisplayField: Hashable {
        case foodName
        case highlights
        case identifiedItems
        case portionDescription
    }

    init(
        foodName: String,
        confidence: Double,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        highlights: [String],
        source: FoodAnalysisSource,
        needsReview: Bool,
        identifiedItems: [String],
        portionDescription: String,
        localizedDisplayFields: Set<LocalizedDisplayField> = []
    ) {
        self.foodName = foodName
        self.confidence = confidence
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.highlights = highlights
        self.source = source
        self.needsReview = needsReview
        self.identifiedItems = identifiedItems
        self.portionDescription = portionDescription
        self.localizedDisplayFields = localizedDisplayFields
    }

    func displayFoodName(locale: Locale) -> String {
        localizedDisplayText(foodName, field: .foodName, locale: locale)
    }

    func displayHighlights(locale: Locale) -> [String] {
        highlights.map { localizedDisplayText($0, field: .highlights, locale: locale) }
    }

    func displayIdentifiedItems(locale: Locale) -> [String] {
        identifiedItems.map { localizedDisplayText($0, field: .identifiedItems, locale: locale) }
    }

    func displayPortionDescription(locale: Locale) -> String {
        localizedDisplayText(portionDescription, field: .portionDescription, locale: locale)
    }

    private func localizedDisplayText(_ text: String, field: LocalizedDisplayField, locale: Locale) -> String {
        guard localizedDisplayFields.contains(field) else { return text }
        return AppLocalization.localized(text, locale: locale)
    }
}

struct FoodRecognitionInput {
    let imageData: Data
}
