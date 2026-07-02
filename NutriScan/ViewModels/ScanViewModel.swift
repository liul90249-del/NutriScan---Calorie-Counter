import Foundation

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var isAnalyzing = false
    @Published var isLookingUpBarcode = false
    @Published var latestAnalysis: FoodAnalysis?
    @Published var errorMessage = ""

    func analyzePhoto(
        selectedImageData: Data?,
        service: FoodRecognitionServicing
    ) async {
        isAnalyzing = true
        errorMessage = ""

        do {
            guard let selectedImageData else {
                throw FoodRecognitionError.noPhotoSelected
            }
            latestAnalysis = try await service.analyze(
                input: FoodRecognitionInput(imageData: selectedImageData)
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false
    }

    func lookupBarcode(
        code: String,
        service: BarcodeFoodLookupServicing = OpenFoodFactsLookupService()
    ) async {
        isLookingUpBarcode = true
        errorMessage = ""

        do {
            latestAnalysis = try await service.lookup(barcode: code)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLookingUpBarcode = false
    }
}
