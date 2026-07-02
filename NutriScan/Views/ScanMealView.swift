import PhotosUI
import SwiftData
import SwiftUI

struct ScanMealView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @StateObject private var viewModel = ScanViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedMealType = "Lunch"

    private let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Scan a meal")
                        .font(.system(size: 30, weight: .semibold, design: .serif))

                    scanCard
                    mealTypePicker
                    analysisCard
                }
                .padding(20)
            }
            .background(Color(hex: "#F5F5F1").ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            guard let data = try? await selectedPhoto.loadTransferable(type: Data.self) else { return }
            selectedImageData = UIImage(data: data)?.jpegData(compressionQuality: 0.86) ?? data
        }
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Take or choose a food photo to estimate calories and macros.")
                .foregroundStyle(.secondary)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            Button {
                Task {
                    await viewModel.analyzePhoto(
                        selectedImageData: selectedImageData,
                        service: flow.recognitionService
                    )
                }
            } label: {
                HStack {
                    if viewModel.isAnalyzing {
                        ProgressView()
                    }
                    Text(localized(viewModel.isAnalyzing ? "Analyzing..." : "Analyze Meal"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isAnalyzing || selectedImageData == nil)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var mealTypePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meal type")
                .font(.headline)

            Picker("Meal type", selection: $selectedMealType) {
                ForEach(mealTypes, id: \.self) { type in
                    Text(localizedMealType(type)).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Latest result")
                .font(.headline)

            if let analysis = viewModel.latestAnalysis {
                VStack(alignment: .leading, spacing: 10) {
                    Text(analysis.displayFoodName(locale: locale))
                        .font(.title3.weight(.semibold))
                    Text(localizedFormat("Confidence %lld%%", Int(analysis.confidence * 100)))
                        .foregroundStyle(.secondary)

                    if !analysis.portionDescription.isEmpty {
                        Label(analysis.displayPortionDescription(locale: locale), systemImage: "takeoutbag.and.cup.and.straw")
                            .font(.subheadline)
                    }

                    Text(localizedFormat("%lld kcal • %lldg protein • %lldg carbs • %lldg fat", analysis.calories, Int(analysis.protein.rounded()), Int(analysis.carbs.rounded()), Int(analysis.fat.rounded())))
                        .font(.subheadline.weight(.semibold))

                    if !analysis.identifiedItems.isEmpty {
                        Text(analysis.displayIdentifiedItems(locale: locale).joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(analysis.displayHighlights(locale: locale), id: \.self) { item in
                        Label(item, systemImage: "sparkles")
                            .font(.subheadline)
                    }

                    Button("Save to Log") {
                        let entry = FoodEntry(
                            mealType: selectedMealType,
                            foodName: analysis.displayFoodName(locale: locale),
                            calories: analysis.calories,
                            protein: analysis.protein,
                            carbs: analysis.carbs,
                            fat: analysis.fat
                        )
                        modelContext.insert(entry)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .foregroundStyle(.red)
            } else {
                Text("Your recognized meal will appear here.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func localizedMealType(_ mealType: String) -> String {
        switch mealType {
        case "Breakfast": return AppLocalization.localized("Breakfast", locale: locale)
        case "Lunch": return AppLocalization.localized("Lunch", locale: locale)
        case "Dinner": return AppLocalization.localized("Dinner", locale: locale)
        case "Snack": return AppLocalization.localized("Snack", locale: locale)
        default: return mealType
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: AppLocalization.localized(key, locale: locale), locale: locale, arguments: arguments)
    }
}
