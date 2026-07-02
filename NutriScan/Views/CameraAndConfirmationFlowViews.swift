import PhotosUI
import SwiftData
import SwiftUI

struct CameraCaptureView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    @StateObject private var scanViewModel = ScanViewModel()
    @State private var activeMode: CaptureMode = .gallery
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var showPaywall = false
    @State private var scannedBarcode = ""

    enum CaptureMode: String, CaseIterable {
        case barcode = "Barcode"
        case ai = "AI Scan"
        case gallery = "Gallery"
    }

    private var hasSelectedImage: Bool {
        selectedImageData != nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        flow.closeCamera()
                    } label: {
                        Circle()
                            .fill(.black.opacity(0.65))
                            .frame(width: 42, height: 42)
                            .overlay(Image(systemName: "xmark").foregroundStyle(.white))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                if scanViewModel.isAnalyzing || scanViewModel.isLookingUpBarcode {
                    analyzingState
                } else if activeMode == .barcode {
                    barcodeScannerFrame
                } else {
                    cameraFrame
                }

                Spacer()

                if !scanViewModel.isAnalyzing && !scanViewModel.isLookingUpBarcode {
                    bottomCaptureControls
                }
            }
        }
        .task(id: selectedPhoto) {
            await loadSelectedPhoto()
        }
        .onChange(of: scanViewModel.latestAnalysis) { _, analysis in
            if let analysis {
                flow.consumeFreeAIScanIfNeeded(for: analysis)
                flow.showFoodConfirmation(analysis)
            }
        }
        .alert("Scan failed", isPresented: .constant(!scanViewModel.errorMessage.isEmpty), actions: {
            Button("OK") {
                scanViewModel.errorMessage = ""
            }
        }, message: {
            Text(scanViewModel.errorMessage)
        })
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallSheet()
                .environmentObject(flow)
        }
    }

    private var analyzingState: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(.white)
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(.black))
            Text(localized(scanViewModel.isLookingUpBarcode ? "Looking up barcode..." : "AI is analyzing your meal..."))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(scanViewModel.isLookingUpBarcode ? localized("Matching packaged food nutrition data.") : analyzingDescription)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private var barcodeScannerFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.32), lineWidth: 4)
                .frame(width: 310, height: 356)

            BarcodeScannerView { code in
                scannedBarcode = code
                Task {
                    await scanViewModel.lookupBarcode(code: code)
                }
            } onError: { message in
                scanViewModel.errorMessage = message
            }
            .frame(width: 286, height: 332)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

            VStack {
                Spacer()
                Text(scannedBarcode.isEmpty ? localized("Align the barcode inside the frame") : localizedFormat("Scanned barcode: %@", scannedBarcode))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 18)
            }
            .frame(width: 310, height: 356)
        }
    }

    private var cameraFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 4)
                )
                .frame(width: 310, height: 356)

            VStack(spacing: 14) {
                if let previewImage = previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 270, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Text("Photo ready for analysis")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(photoReadyDescription)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                } else {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 68, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.6))

                    Text("Choose a meal photo first")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Preview, then confirm the nutrition result before saving.")
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                }
            }
        }
    }

    private var bottomCaptureControls: some View {
        VStack(spacing: 22) {
            HStack(spacing: 40) {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    captureModeButton(mode)
                }
            }

            if activeMode == .gallery || activeMode == .ai {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(localized(hasSelectedImage ? "Replace Photo" : "Choose Photo"), systemImage: activeMode == .ai ? "camera.viewfinder" : "photo.on.rectangle")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(.horizontal, 20)
            } else {
                Text(modeHelperText)
                    .font(.footnote)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Button {
                guard flow.canUseAIScan else {
                    showPaywall = true
                    return
                }
                Task {
                    await scanViewModel.analyzePhoto(
                        selectedImageData: selectedImageData,
                        service: flow.recognitionService
                    )
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text(primaryButtonTitle)
                }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(primaryButtonEnabled ? .white : Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!primaryButtonEnabled)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private func captureModeButton(_ mode: CaptureMode) -> some View {
        Button {
            if mode == .ai && !flow.canUseAIScan {
                showPaywall = true
                return
            }
            if mode != activeMode {
                selectedPhoto = nil
                selectedImageData = nil
                scannedBarcode = ""
            }
            activeMode = mode
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon(for: mode))
                    .font(.system(size: 24))
                HStack(spacing: 4) {
                    Text(localized(mode.rawValue))
                    if mode == .ai && !flow.profile.isPremium {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                    }
                }
                    .font(.caption)
            }
            .foregroundStyle(activeMode == mode ? .white : .gray)
        }
        .buttonStyle(.plain)
    }

    private func icon(for mode: CaptureMode) -> String {
        switch mode {
        case .barcode: return "barcode.viewfinder"
        case .ai: return "sparkles"
        case .gallery: return "photo.on.rectangle"
        }
    }

    private var previewImage: UIImage? {
        guard let selectedImageData else { return nil }
        return UIImage(data: selectedImageData)
    }

    private var primaryButtonEnabled: Bool {
        activeMode != .barcode && hasSelectedImage
    }

    private var primaryButtonTitle: String {
        if activeMode == .barcode {
            return localized("Scan a barcode to continue")
        }
        return hasSelectedImage ? localized("Analyze Meal") : localized("Choose a Photo First")
    }

    private var analyzingDescription: String {
        switch flow.recognitionMode {
        case .localOnly:
            return localized("Using on-device estimation. Results are rough and should be reviewed.")
        case .smartHybrid:
            return localized("Trying cloud AI first when available, then falling back to a local estimate.")
        case .cloudPreferred:
            return localized("Using cloud AI for the best recognition quality available.")
        }
    }

    private var photoReadyDescription: String {
        switch flow.recognitionMode {
        case .localOnly:
            return localized("This mode gives a rough estimate from common meal patterns.")
        case .smartHybrid:
            return localized("If cloud AI is unavailable, the app will fall back to a local estimate.")
        case .cloudPreferred:
            return localized("Your photo will be sent for cloud AI analysis before you save.")
        }
    }

    private var modeHelperText: String {
        switch activeMode {
        case .ai:
            return "\(localized("Choose or capture a food photo for AI nutrition analysis.")) \(flow.aiScanAccessText)"
        case .barcode:
            return localized("Scan packaged foods to load label nutrition.")
        case .gallery:
            return ""
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        guard let data = try? await selectedPhoto.loadTransferable(type: Data.self) else { return }
        selectedImageData = UIImage(data: data)?.jpegData(compressionQuality: 0.86) ?? data
    }
}

struct FoodConfirmationFlowView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @State private var editableName = ""
    @State private var mealType = "Lunch"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var notes = ""
    @State private var showSavedBanner = false
    @State private var selectedPortion = 1.0

    private let notesLimit = 140
    private let portionOptions: [Double] = [0.5, 1.0, 1.5, 2.0]

    var body: some View {
        if let analysis = flow.recognizedFood {
            VStack(spacing: 0) {
                heroSection(analysis: analysis)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        nutritionSummaryCard
                        editableDetailsCard(analysis: analysis)
                    }
                    .padding(20)
                }

                Button {
                    saveMeal(using: analysis)
                } label: {
                    Text("Save Meal")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
                .buttonStyle(.plain)
            }
            .background(Color(hex: "#FAFAF8"))
            .onAppear {
                hydrateForm(from: analysis)
            }
            .overlay(alignment: .top) {
                if showSavedBanner {
                    Label("Meal saved", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.green, in: Capsule())
                        .padding(.top, 18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        } else {
            VStack {
                Text("No recognized food data")
                    .foregroundStyle(.secondary)
                Button("Back") {
                    flow.recognizedFood = nil
                    flow.currentScreen = .camera
                }
            }
        }
    }

    private func heroSection(analysis: FoodAnalysis) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: "#F9E9C8"), Color(hex: "#F3F4F6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 290)
            .overlay(
                VStack(spacing: 12) {
                    FoodCartoonIcon(analysis: analysis, size: 132)
                    Text(analysis.displayFoodName(locale: locale))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 24)
                    Text(localizedFormat("%@ %lld%%", analysis.source.localizedConfidenceLabel(locale: locale), Int(analysis.confidence * 100)))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(analysis.source.localizedResultLabel(locale: locale))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.08), in: Capsule())
                }
            )

            Button {
                flow.recognizedFood = nil
                flow.currentScreen = .camera
            } label: {
                Circle()
                    .fill(.black.opacity(0.5))
                    .frame(width: 42, height: 42)
                    .overlay(Image(systemName: "chevron.left").foregroundStyle(.white))
            }
            .padding(.top, 16)
            .padding(.leading, 16)
        }
    }

    private var nutritionSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nutrition Summary")
                .font(.title3.weight(.semibold))

            Text(analysisSourceSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let analysis = flow.recognizedFood, analysis.needsReview {
                Label("Review suggested before saving", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if let analysis = flow.recognizedFood, !analysis.displayPortionDescription(locale: locale).isEmpty {
                Label(localizedFormat("Estimated portion: %@", analysis.displayPortionDescription(locale: locale)), systemImage: "scalemass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                summaryMetric(title: "Calories", value: calories, suffix: "kcal")
                summaryMetric(title: "Protein", value: protein, suffix: "g")
                summaryMetric(title: "Carbs", value: carbs, suffix: "g")
                summaryMetric(title: "Fat", value: fat, suffix: "g")
            }
        }
        .padding(18)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func editableDetailsCard(analysis: FoodAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review before saving")
                .font(.headline)

            Group {
                labeledField(title: "Food name", text: $editableName)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Portion")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        ForEach(portionOptions, id: \.self) { option in
                            Button {
                                applyPortion(option, analysis: analysis)
                            } label: {
                                Text(portionLabel(for: option))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(selectedPortion == option ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(selectedPortion == option ? Color.black : Color.gray.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Meal Type")
                        .font(.subheadline.weight(.semibold))
                    Picker("Meal Type", selection: $mealType) {
                        Text("Breakfast").tag("Breakfast")
                        Text("Lunch").tag("Lunch")
                        Text("Dinner").tag("Dinner")
                        Text("Snack").tag("Snack")
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: 10) {
                    labeledField(title: "Calories", text: $calories, keyboardType: .numberPad)
                    labeledField(title: "Protein", text: $protein, keyboardType: .decimalPad)
                }

                HStack(spacing: 10) {
                    labeledField(title: "Carbs", text: $carbs, keyboardType: .decimalPad)
                    labeledField(title: "Fat", text: $fat, keyboardType: .decimalPad)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.subheadline.weight(.semibold))
                    TextField(localized("Optional notes, serving size, ingredients..."), text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...5)
                    HStack {
                        Spacer()
                        Text("\(notes.count)/\(notesLimit)")
                            .font(.caption)
                            .foregroundStyle(notes.count >= notesLimit ? .red : .secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                let identifiedItems = analysis.displayIdentifiedItems(locale: locale)
                if !identifiedItems.isEmpty {
                    Text("Visible items")
                        .font(.subheadline.weight(.semibold))

                    Text(identifiedItems.joined(separator: " • "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("AI highlights")
                    .font(.subheadline.weight(.semibold))

                ForEach(analysis.displayHighlights(locale: locale), id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                }
            }
        }
        .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onChange(of: notes) { _, newValue in
                if newValue.count > notesLimit {
                    notes = String(newValue.prefix(notesLimit))
                }
            }
    }

    private func labeledField(title: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            TextField(title, text: text)
                .keyboardType(keyboardType)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func summaryMetric(title: String, value: String, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value) \(suffix)")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var analysisSourceSummary: String {
        guard let analysis = flow.recognizedFood else { return "" }
        return analysis.source.localizedSummaryText(locale: locale)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.formatted(key, locale: locale, arguments)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }

    private func portionLabel(for value: Double) -> String {
        if value == 1.0 {
            return "1x"
        }
        if value == floor(value) {
            return "\(Int(value))x"
        }
        return "\(value.formatted(.number.precision(.fractionLength(1))))x"
    }

    private func hydrateForm(from analysis: FoodAnalysis) {
        selectedPortion = 1.0
        editableName = analysis.displayFoodName(locale: locale)
        calories = String(analysis.calories)
        protein = String(Int(analysis.protein.rounded()))
        carbs = String(Int(analysis.carbs.rounded()))
        fat = String(Int(analysis.fat.rounded()))
    }

    private func applyPortion(_ portion: Double, analysis: FoodAnalysis) {
        selectedPortion = portion
        calories = String(Int((Double(analysis.calories) * portion).rounded()))
        protein = String(Int((analysis.protein * portion).rounded()))
        carbs = String(Int((analysis.carbs * portion).rounded()))
        fat = String(Int((analysis.fat * portion).rounded()))
    }

    private func saveMeal(using analysis: FoodAnalysis) {
        let entry = FoodEntry(
            mealType: mealType,
            foodName: editableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? analysis.displayFoodName(locale: locale) : editableName,
            calories: Int(calories) ?? analysis.calories,
            protein: Double(protein) ?? analysis.protein,
            carbs: Double(carbs) ?? analysis.carbs,
            fat: Double(fat) ?? analysis.fat,
            notes: notes
        )
        modelContext.insert(entry)
        withAnimation(.spring(duration: 0.35)) {
            showSavedBanner = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            flow.finishFoodConfirmation()
        }
    }
}

private struct FoodCartoonIcon: View {
    let analysis: FoodAnalysis
    let size: CGFloat

    private var symbol: String {
        foodCartoonSymbol(
            foodName: analysis.foodName,
            identifiedItems: analysis.identifiedItems
        )
    }

    private var colors: [Color] {
        foodCartoonColors(
            foodName: analysis.foodName,
            identifiedItems: analysis.identifiedItems
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: colors.last?.opacity(0.22) ?? .black.opacity(0.12), radius: 18, y: 10)

            Circle()
                .stroke(.white.opacity(0.72), lineWidth: 5)
                .frame(width: size - 14, height: size - 14)

            Text(symbol)
                .font(.system(size: size * 0.48))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .accessibilityLabel(Text(analysis.foodName))
    }
}

private func foodCartoonSymbol(foodName: String, identifiedItems: [String]) -> String {
    let text = ([foodName] + identifiedItems).joined(separator: " ").lowercased()

    if text.contains("salad") || text.contains("沙拉") || text.contains("蔬菜") || text.contains("生菜") {
        return "🥗"
    }
    if text.contains("rice") || text.contains("饭") || text.contains("米") {
        return "🍚"
    }
    if text.contains("noodle") || text.contains("面") || text.contains("ramen") || text.contains("pasta") {
        return "🍜"
    }
    if text.contains("chicken") || text.contains("鸡") {
        return "🍗"
    }
    if text.contains("beef") || text.contains("牛") || text.contains("steak") {
        return "🥩"
    }
    if text.contains("pork") || text.contains("猪") {
        return "🍖"
    }
    if text.contains("fish") || text.contains("鱼") || text.contains("salmon") || text.contains("tuna") {
        return "🐟"
    }
    if text.contains("shrimp") || text.contains("虾") || text.contains("seafood") || text.contains("海鲜") {
        return "🍤"
    }
    if text.contains("tofu") || text.contains("豆腐") || text.contains("豆") {
        return "🧆"
    }
    if text.contains("egg") || text.contains("蛋") {
        return "🍳"
    }
    if text.contains("pizza") || text.contains("披萨") {
        return "🍕"
    }
    if text.contains("burger") || text.contains("汉堡") {
        return "🍔"
    }
    if text.contains("sandwich") || text.contains("三明治") || text.contains("toast") {
        return "🥪"
    }
    if text.contains("soup") || text.contains("汤") || text.contains("stew") {
        return "🥣"
    }
    if text.contains("cake") || text.contains("蛋糕") || text.contains("dessert") || text.contains("甜点") {
        return "🍰"
    }
    if text.contains("fruit") || text.contains("水果") || text.contains("berry") || text.contains("苹果") {
        return "🍓"
    }

    return "🍽️"
}

private func foodCartoonColors(foodName: String, identifiedItems: [String]) -> [Color] {
    let text = ([foodName] + identifiedItems).joined(separator: " ").lowercased()

    if text.contains("salad") || text.contains("沙拉") || text.contains("蔬菜") || text.contains("生菜") {
        return [Color(hex: "#DCFCE7"), Color(hex: "#86EFAC")]
    }
    if text.contains("rice") || text.contains("饭") || text.contains("米") || text.contains("tofu") || text.contains("豆腐") {
        return [Color(hex: "#FEF3C7"), Color(hex: "#FCD34D")]
    }
    if text.contains("fish") || text.contains("鱼") || text.contains("shrimp") || text.contains("虾") || text.contains("seafood") {
        return [Color(hex: "#DBEAFE"), Color(hex: "#60A5FA")]
    }
    if text.contains("chicken") || text.contains("鸡") || text.contains("beef") || text.contains("牛") || text.contains("pork") || text.contains("猪") {
        return [Color(hex: "#FFE4E6"), Color(hex: "#FB7185")]
    }
    if text.contains("noodle") || text.contains("面") || text.contains("pasta") || text.contains("pizza") || text.contains("披萨") {
        return [Color(hex: "#FFEDD5"), Color(hex: "#FB923C")]
    }
    if text.contains("fruit") || text.contains("水果") || text.contains("berry") || text.contains("dessert") || text.contains("甜点") {
        return [Color(hex: "#FCE7F3"), Color(hex: "#F472B6")]
    }

    return [Color(hex: "#F3F4F6"), Color(hex: "#D1D5DB")]
}
