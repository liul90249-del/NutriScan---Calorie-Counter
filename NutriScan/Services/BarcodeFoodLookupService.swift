import Foundation

protocol BarcodeFoodLookupServicing {
    func lookup(barcode: String) async throws -> FoodAnalysis
}

enum BarcodeLookupError: LocalizedError {
    case productNotFound
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return AppLocalization.current("Product not found for this barcode.")
        case .invalidResponse:
            return AppLocalization.current("Barcode nutrition data was incomplete.")
        }
    }
}

private struct OpenFoodFactsResponse: Decodable {
    let status: Int
    let product: OpenFoodFactsProduct?
}

private struct OpenFoodFactsProduct: Decodable {
    let productName: String?
    let genericName: String?
    let brands: String?
    let servingSize: String?
    let quantity: String?
    let nutriments: OpenFoodFactsNutriments?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case genericName = "generic_name"
        case brands
        case servingSize = "serving_size"
        case quantity
        case nutriments
    }
}

private struct OpenFoodFactsNutriments: Decodable {
    let energyKcalServing: Double?
    let energyKcal100g: Double?
    let proteinsServing: Double?
    let proteins100g: Double?
    let carbohydratesServing: Double?
    let carbohydrates100g: Double?
    let fatServing: Double?
    let fat100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcalServing = "energy-kcal_serving"
        case energyKcal100g = "energy-kcal_100g"
        case proteinsServing = "proteins_serving"
        case proteins100g = "proteins_100g"
        case carbohydratesServing = "carbohydrates_serving"
        case carbohydrates100g = "carbohydrates_100g"
        case fatServing = "fat_serving"
        case fat100g = "fat_100g"
    }
}

struct OpenFoodFactsLookupService: BarcodeFoodLookupServicing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookup(barcode: String) async throws -> FoodAnalysis {
        let cleanBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(cleanBarcode).json?fields=product_name,generic_name,brands,serving_size,quantity,nutriments") else {
            throw BarcodeLookupError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("NutriScan/1.0 iOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BarcodeLookupError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
        guard decoded.status == 1, let product = decoded.product else {
            throw BarcodeLookupError.productNotFound
        }

        return try product.asAnalysis(barcode: cleanBarcode)
    }
}

private extension OpenFoodFactsProduct {
    func asAnalysis(barcode: String) throws -> FoodAnalysis {
        guard let nutriments else {
            throw BarcodeLookupError.invalidResponse
        }

        let calories = nutriments.energyKcalServing ?? nutriments.energyKcal100g
        let protein = nutriments.proteinsServing ?? nutriments.proteins100g
        let carbs = nutriments.carbohydratesServing ?? nutriments.carbohydrates100g
        let fat = nutriments.fatServing ?? nutriments.fat100g

        guard let calories, let protein, let carbs, let fat else {
            throw BarcodeLookupError.invalidResponse
        }

        let name = [brands, productName ?? genericName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let serving = servingSize?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasServing = serving?.isEmpty == false
        var localizedDisplayFields: Set<FoodAnalysis.LocalizedDisplayField> = [.highlights]
        if name.isEmpty {
            localizedDisplayFields.insert(.foodName)
        }
        if !hasServing {
            localizedDisplayFields.insert(.portionDescription)
        }

        return FoodAnalysis(
            foodName: name.isEmpty ? "Packaged food" : name,
            confidence: nutriments.energyKcalServing == nil ? 0.72 : 0.9,
            calories: Int(calories.rounded()),
            protein: protein,
            carbs: carbs,
            fat: fat,
            highlights: [
                "Nutrition loaded from barcode database",
                "Review serving size before saving",
                "Barcode: \(barcode)"
            ],
            source: .barcode,
            needsReview: true,
            identifiedItems: [productName, genericName, brands].compactMap { $0 }.filter { !$0.isEmpty },
            portionDescription: hasServing ? serving! : "1 package serving",
            localizedDisplayFields: localizedDisplayFields
        )
    }
}
