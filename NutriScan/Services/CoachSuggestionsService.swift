import Foundation

struct CoachSuggestionsConfig {
    let endpoint: URL?
    let apiKey: String

    var isReady: Bool {
        endpoint != nil && !apiKey.isEmpty
    }
}

struct CoachSuggestionsRequest: Encodable {
    let locale: String
    let profile: CoachUserProfilePayload
    let recentMeals: [CoachMealPayload]
}

struct CoachUserProfilePayload: Encodable {
    let gender: String
    let height: Double
    let weight: Double
    let goalWeight: Double
    let activityLevel: String
    let weeklyLossRate: Double
    let unit: String
    let isPremium: Bool
}

struct CoachMealPayload: Encodable {
    let mealType: String
    let foodName: String
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let notes: String
    let createdAt: String
}

struct CoachSuggestionsResponse: Codable, Equatable {
    let summary: String
    let nextGoal: String
    let cards: [CoachSuggestionResponseCard]
}

struct CoachSuggestionResponseCard: Codable, Equatable, Identifiable {
    var id: String {
        [title, subtitle, targetFocus, priority].joined(separator: "|")
    }

    let title: String
    let subtitle: String
    let bullets: [String]
    let suggestedFoods: [String]
    let targetFocus: String
    let priority: String
}

enum CoachSuggestionsError: LocalizedError, Equatable {
    case notConfigured
    case premiumRequired
    case timeout
    case endpointNotDeployed
    case badServerResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Nutrition coaching is not configured."
        case .premiumRequired:
            return "Nutrition coaching suggestions require NutriScan Pro."
        case .timeout:
            return "Nutrition coaching model timed out."
        case .endpointNotDeployed:
            return "Nutrition coaching endpoint is not deployed yet."
        case .badServerResponse:
            return "Nutrition coaching suggestions are unavailable right now."
        }
    }
}

struct CoachSuggestionsService {
    private let config: CoachSuggestionsConfig
    private let session: URLSession

    init(
        config: CoachSuggestionsConfig = CoachSuggestionsConfig(
            endpoint: URL(string: NutriScanBackendConfig.coachSuggestionsEndpoint),
            apiKey: NutriScanBackendConfig.clientToken
        ),
        session: URLSession = .shared
    ) {
        self.config = config
        self.session = session
    }

    func fetchSuggestions(payload: CoachSuggestionsRequest) async throws -> CoachSuggestionsResponse {
        guard config.isReady else {
            throw CoachSuggestionsError.notConfigured
        }

        guard let endpoint = config.endpoint else {
            throw CoachSuggestionsError.notConfigured
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw CoachSuggestionsError.timeout
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoachSuggestionsError.badServerResponse
        }

        if httpResponse.statusCode == 500,
           let serverError = try? JSONDecoder().decode(CoachSuggestionsServerError.self, from: data),
           serverError.detail.error == "provider_not_configured" {
            throw CoachSuggestionsError.notConfigured
        }

        if httpResponse.statusCode == 403 {
            throw CoachSuggestionsError.premiumRequired
        }

        if httpResponse.statusCode == 404 {
            throw CoachSuggestionsError.endpointNotDeployed
        }

        if httpResponse.statusCode == 504 {
            throw CoachSuggestionsError.timeout
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CoachSuggestionsError.badServerResponse
        }

        return try JSONDecoder().decode(CoachSuggestionsResponse.self, from: data)
    }
}

private struct CoachSuggestionsServerError: Decodable {
    struct Detail: Decodable {
        let error: String
    }

    let detail: Detail
}
