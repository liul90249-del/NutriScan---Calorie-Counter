import Foundation

protocol FoodRecognitionServicing {
    func analyze(input: FoodRecognitionInput) async throws -> FoodAnalysis
}

enum RecognitionMode: String, CaseIterable, Identifiable, Codable {
    case localOnly
    case smartHybrid
    case cloudPreferred

    var id: String { rawValue }

    var title: String {
        AppLocalization.current(localizationKey)
    }

    var subtitle: String {
        AppLocalization.current(subtitleLocalizationKey)
    }

    var engineLabel: String {
        AppLocalization.current(engineLocalizationKey)
    }

    var syncLabel: String {
        AppLocalization.current(syncLocalizationKey)
    }

    var localizationKey: String {
        switch self {
        case .localOnly: return "On-Device"
        case .smartHybrid: return "Smart Hybrid"
        case .cloudPreferred: return "Cloud Boost"
        }
    }

    var subtitleLocalizationKey: String {
        switch self {
        case .localOnly: return "Private local analysis with basic estimation."
        case .smartHybrid: return "Prefer local first, upgrade to cloud when needed."
        case .cloudPreferred: return "Best recognition quality with cloud processing."
        }
    }

    var engineLocalizationKey: String {
        switch self {
        case .localOnly: return "Vision + local nutrition map"
        case .smartHybrid: return "Local first with optional cloud fallback"
        case .cloudPreferred: return "Cloud recognition with local save"
        }
    }

    var syncLocalizationKey: String {
        switch self {
        case .localOnly: return "Fully local"
        case .smartHybrid: return "Local by default"
        case .cloudPreferred: return "Photo sent only for AI analysis"
        }
    }
}

enum FoodRecognitionError: LocalizedError {
    case noPhotoSelected
    case cloudUnavailable
    case invalidServiceURL
    case badServerResponse

    var errorDescription: String? {
        switch self {
        case .noPhotoSelected:
            return AppLocalization.current("No photo was selected.")
        case .cloudUnavailable:
            return AppLocalization.current("Cloud AI is not connected yet. Use Smart Hybrid or On-Device for now.")
        case .invalidServiceURL:
            return AppLocalization.current("Cloud service URL is invalid.")
        case .badServerResponse:
            return AppLocalization.current("Cloud AI returned an invalid response.")
        }
    }
}

struct MockFoodRecognitionService: FoodRecognitionServicing {
    func analyze(input: FoodRecognitionInput) async throws -> FoodAnalysis {
        try await Task.sleep(for: .milliseconds(900))

        return FoodAnalysis(
            foodName: "Chicken Salad Bowl",
            confidence: 0.94,
            calories: 420,
            protein: 31,
            carbs: 22,
            fat: 18,
            highlights: [
                "High in protein",
                "Balanced lunch option",
                "Estimated from image recognition"
            ],
            source: .hybridFallback,
            needsReview: true,
            identifiedItems: ["chicken", "greens", "salad bowl"],
            portionDescription: "1 medium bowl",
            localizedDisplayFields: [.foodName, .highlights, .identifiedItems, .portionDescription]
        )
    }
}

struct LocalFoodRecognitionService: FoodRecognitionServicing {
    func analyze(input: FoodRecognitionInput) async throws -> FoodAnalysis {
        try await Task.sleep(for: .milliseconds(700))

        return FoodAnalysis(
            foodName: "Home Style Rice Bowl",
            confidence: 0.58,
            calories: 510,
            protein: 24,
            carbs: 58,
            fat: 17,
            highlights: [
                "Rough estimate generated on-device",
                "Best for common meal patterns, not exact dish recognition",
                "Adjust the meal name and macros before saving"
            ],
            source: .localEstimate,
            needsReview: true,
            identifiedItems: ["rice", "mixed toppings"],
            portionDescription: "1 medium bowl",
            localizedDisplayFields: [.foodName, .highlights, .identifiedItems, .portionDescription]
        )
    }
}

struct CloudRecognitionConfig {
    let endpoint: URL?
    let apiKey: String
    let isEnabled: Bool

    var isReady: Bool {
        isEnabled && endpoint != nil && !apiKey.isEmpty
    }
}

private struct CloudRecognitionRequest: Encodable {
    let imageBase64: String
    let locale: String
    let source: String
}

private struct CloudRecognitionResponse: Decodable {
    let foodName: String
    let confidence: Double
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let highlights: [String]
    let needsReview: Bool?
    let identifiedItems: [String]?
    let portionDescription: String?

    func asAnalysis() -> FoodAnalysis {
        FoodAnalysis(
            foodName: foodName,
            confidence: confidence,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            highlights: highlights,
            source: .cloudAI,
            needsReview: needsReview ?? (confidence < 0.8),
            identifiedItems: identifiedItems ?? [],
            portionDescription: portionDescription ?? ""
        )
    }
}

struct CloudFoodRecognitionService: FoodRecognitionServicing {
    private let config: CloudRecognitionConfig
    private let session: URLSession

    init(
        config: CloudRecognitionConfig,
        session: URLSession = .shared
    ) {
        self.config = config
        self.session = session
    }

    func analyze(input: FoodRecognitionInput) async throws -> FoodAnalysis {
        guard config.isReady else {
            throw FoodRecognitionError.cloudUnavailable
        }

        guard let endpoint = config.endpoint else {
            throw FoodRecognitionError.invalidServiceURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let payload = CloudRecognitionRequest(
            imageBase64: input.imageData.base64EncodedString(),
            locale: AppLocalization.currentLocale.identifier,
            source: "NutriScan-iOS"
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FoodRecognitionError.badServerResponse
        }

        let decoded = try JSONDecoder().decode(CloudRecognitionResponse.self, from: data)
        return decoded.asAnalysis()
    }
}

struct HybridFoodRecognitionService: FoodRecognitionServicing {
    private let localService: FoodRecognitionServicing
    private let cloudService: FoodRecognitionServicing

    init(
        localService: FoodRecognitionServicing = LocalFoodRecognitionService(),
        cloudService: FoodRecognitionServicing = CloudFoodRecognitionService(
            config: CloudRecognitionConfig(endpoint: nil, apiKey: "", isEnabled: false)
        )
    ) {
        self.localService = localService
        self.cloudService = cloudService
    }

    func analyze(input: FoodRecognitionInput) async throws -> FoodAnalysis {
        do {
            return try await cloudService.analyze(input: input)
        } catch FoodRecognitionError.cloudUnavailable {
            let localResult = try await localService.analyze(input: input)
            return FoodAnalysis(
                foodName: localResult.foodName,
                confidence: localResult.confidence,
                calories: localResult.calories,
                protein: localResult.protein,
                carbs: localResult.carbs,
                fat: localResult.fat,
                highlights: [
                    "Cloud AI was not connected",
                    "Using a local fallback estimate",
                    "Review and adjust before saving"
                ],
                source: .hybridFallback,
                needsReview: true,
                identifiedItems: localResult.identifiedItems,
                portionDescription: localResult.portionDescription,
                localizedDisplayFields: localResult.localizedDisplayFields.union([.highlights])
            )
        } catch {
            throw error
        }
    }
}

enum FoodRecognitionServiceFactory {
    static func makeService(
        for mode: RecognitionMode,
        cloudConfig: CloudRecognitionConfig
    ) -> FoodRecognitionServicing {
        switch mode {
        case .localOnly:
            return LocalFoodRecognitionService()
        case .smartHybrid:
            return HybridFoodRecognitionService(
                localService: LocalFoodRecognitionService(),
                cloudService: CloudFoodRecognitionService(config: cloudConfig)
            )
        case .cloudPreferred:
            return CloudFoodRecognitionService(config: cloudConfig)
        }
    }
}
