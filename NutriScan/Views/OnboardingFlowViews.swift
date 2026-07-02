import SwiftUI

private struct FlowPageContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#FFF7ED"), .white, Color(hex: "#EFF6FF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
        }
    }
}

struct WelcomeFlowView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    @State private var currentIndex = 0

    private let slides: [(icon: String, title: String, subtitle: String, description: String, color: Color)] = [
        ("sparkles", "AI-Powered Food Logging", "Snap to track", "Skip manual calorie counting. Just take a photo and let AI estimate your meal and nutrition.", Color.orange),
        ("target", "Smart calorie deficit", "Healthy fat loss", "Get a daily calorie target based on your body metrics and activity level.", Color.blue),
        ("chart.line.uptrend.xyaxis", "Visual progress tracking", "See long-term change", "Understand your trends with clean charts and daily nutrition feedback.", Color.green)
    ]

    var body: some View {
        FlowPageContainer {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(slides.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == currentIndex ? Color.orange : Color.gray.opacity(0.25))
                            .frame(width: index == currentIndex ? 34 : 8, height: 8)
                    }
                }
                .padding(.top, 28)

                Spacer()

                let slide = slides[currentIndex]
                VStack(spacing: 18) {
                    Image(systemName: slide.icon)
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(slide.color)
                    Text(localized(slide.title))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(localized(slide.subtitle))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(localized(slide.description))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .lineSpacing(6)
                        .frame(maxWidth: 320)
                }

                Spacer()

                Button {
                    if currentIndex < slides.count - 1 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentIndex += 1
                        }
                    } else {
                        flow.goToNextOnboardingStep()
                    }
                } label: {
                    HStack {
                        Text(localized(currentIndex == slides.count - 1 ? "Get Started" : "Continue"))
                        Image(systemName: "chevron.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

struct PainPointsFlowView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale

    private let options = [
        "Overeating at night",
        "Hard to track calories",
        "Emotional snacking",
        "Not enough protein",
        "Inconsistent meal routine",
        "Weight loss plateau"
    ]

    var body: some View {
        FlowPageContainer {
            VStack(alignment: .leading, spacing: 22) {
                Text(localized("What feels hardest right now?"))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))

                Text(localized("Choose all that apply so NutriScan can tailor your plan."))
                    .foregroundStyle(.secondary)

                LazyVStack(spacing: 12) {
                    ForEach(options, id: \.self) { option in
                        let isSelected = flow.profile.painPoints.contains(option)
                        Button {
                            if isSelected {
                                flow.profile.painPoints.remove(option)
                            } else {
                                flow.profile.painPoints.insert(option)
                            }
                        } label: {
                            HStack {
                                Text(localized(option))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.orange : Color.gray.opacity(0.4))
                            }
                            .padding(18)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                FlowPrimaryButton(title: "Continue") {
                    flow.goToNextOnboardingStep()
                }
            }
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

struct GenderFlowView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    private let options = ["Male", "Female", "Prefer not to say"]

    var body: some View {
        FlowPageContainer {
            VStack(alignment: .leading, spacing: 22) {
                Text(localized("Tell us about yourself"))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(localized("We use this to estimate your calorie target."))
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    ForEach(options, id: \.self) { option in
                        FlowSelectableRow(
                            title: option,
                            isSelected: flow.profile.gender == option
                        ) {
                            flow.profile.gender = option
                        }
                    }
                }

                Spacer()
                FlowPrimaryButton(title: "Continue") {
                    flow.goToNextOnboardingStep()
                }
                .disabled(flow.profile.gender.isEmpty)
            }
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

struct HeightWeightFlowView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        FlowPageContainer {
            VStack(alignment: .leading, spacing: 22) {
                Text(localized("Height & Weight"))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(localized("Used to calculate your personalized nutrition baseline."))
                    .foregroundStyle(.secondary)

                VStack(spacing: 18) {
                    FlowValueCard(title: "Height", value: "\(Int(flow.profile.height)) cm") {
                        Slider(value: $flow.profile.height, in: 140...210, step: 1)
                            .tint(.orange)
                    }

                    FlowValueCard(title: "Weight", value: "\(Int(flow.profile.weight)) kg") {
                        Slider(value: $flow.profile.weight, in: 35...160, step: 1)
                            .tint(.orange)
                    }
                }

                Spacer()
                FlowPrimaryButton(title: "Continue") {
                    flow.goToNextOnboardingStep()
                }
            }
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

struct ActivityLevelFlowView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    private let levels = [
        "Mostly sedentary",
        "Lightly active",
        "Moderately active",
        "Very active"
    ]

    var body: some View {
        FlowPageContainer {
            VStack(alignment: .leading, spacing: 22) {
                Text(localized("How active are you?"))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(localized("This helps us estimate your maintenance calories."))
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    ForEach(levels, id: \.self) { level in
                        FlowSelectableRow(
                            title: level,
                            isSelected: flow.profile.activityLevel == level
                        ) {
                            flow.profile.activityLevel = level
                        }
                    }
                }

                Spacer()
                FlowPrimaryButton(title: "Continue") {
                    flow.goToNextOnboardingStep()
                }
                .disabled(flow.profile.activityLevel.isEmpty)
            }
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

struct GoalWeightFlowView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        FlowPageContainer {
            VStack(alignment: .leading, spacing: 22) {
                Text(localized("Your goal weight"))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(localized("Set a target that feels realistic and sustainable."))
                    .foregroundStyle(.secondary)

                FlowValueCard(title: "Goal", value: "\(Int(flow.profile.goalWeight)) kg") {
                    Slider(value: $flow.profile.goalWeight, in: 35...160, step: 1)
                        .tint(.orange)
                }

                Spacer()
                FlowPrimaryButton(title: "Continue") {
                    flow.goToNextOnboardingStep()
                }
            }
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

struct WeightSpeedFlowView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        FlowPageContainer {
            VStack(alignment: .leading, spacing: 22) {
                Text(localized("Weekly target speed"))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(localized("Choose a pace for your calorie deficit."))
                    .foregroundStyle(.secondary)

                FlowValueCard(title: "Weekly loss", value: String(format: "%.1f kg / week", flow.profile.weeklyLossRate)) {
                    Slider(value: $flow.profile.weeklyLossRate, in: 0.2...1.0, step: 0.1)
                        .tint(.orange)
                }

                Spacer()
                FlowPrimaryButton(title: "Continue") {
                    flow.goToNextOnboardingStep()
                }
            }
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

struct HealthConnectFlowView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        FlowPageContainer {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 76))
                    .foregroundStyle(.pink)

                Text(localized("Connect Apple Health"))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))

                Text(localized("Sync activity and body metrics later if you want more accurate recommendations."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320)

                Spacer()

                VStack(spacing: 12) {
                    FlowPrimaryButton(title: "Connect") {
                        flow.goToNextOnboardingStep()
                    }
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    Button(localized("Skip for now")) {
                        flow.goToNextOnboardingStep()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

struct FakeLoadingFlowView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    @State private var progress: Double = 0.12

    var body: some View {
        FlowPageContainer {
            VStack(spacing: 22) {
                Spacer()
                ProgressView(value: progress)
                    .tint(.orange)
                    .scaleEffect(x: 1, y: 2.8, anchor: .center)
                Text(localized("Building your plan..."))
                    .font(.title2.weight(.semibold))
                Text(localized("Estimating calories, goals, and meal rhythm."))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .task {
                for step in stride(from: 0.2, through: 1.0, by: 0.16) {
                    try? await Task.sleep(for: .milliseconds(350))
                    progress = min(max(step, 0), 1)
                }
                flow.goToNextOnboardingStep()
            }
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

struct SocialProofFlowView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        FlowPageContainer {
            VStack(alignment: .leading, spacing: 18) {
                Text(localized("People stay consistent when tracking feels simple."))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))

                VStack(spacing: 12) {
                    testimonialCard(quote: "Photo logging finally made calorie tracking sustainable.", author: "Lina, 29")
                    testimonialCard(quote: "Seeing macros after each scan changed how I build meals.", author: "Chris, 34")
                    testimonialCard(quote: "The app feels lighter than a spreadsheet and smarter than guessing.", author: "Ava, 26")
                }

                Spacer()
                FlowPrimaryButton(title: "Continue") {
                    flow.goToNextOnboardingStep()
                }
            }
        }
    }

    private func testimonialCard(quote: String, author: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizedFormat("“%@”", localized(quote)))
            Text(author)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }
}

struct PaywallFlowView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    @State private var purchaseTaskRunning = false

    var body: some View {
        FlowPageContainer {
            VStack(alignment: .leading, spacing: 20) {
                Text(localized("Unlock your full AI nutrition coach"))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))

                VStack(alignment: .leading, spacing: 12) {
                    paywallLine("Unlimited photo meal scans")
                    paywallLine("Smart calorie and macro estimates")
                    paywallLine("Insights, suggestions, and long-term progress")
                }
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text(localized("Annual Premium"))
                        .font(.headline)
                    Text(flow.availableProducts[.annual]?.displayPrice ?? localized("$29.99 / year"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(localized("3-day free trial, then yearly renewal."))
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .foregroundStyle(.white)

                Spacer()

                VStack(spacing: 12) {
                    if flow.storeConfigurationHint != nil {
                        Text(localized("StoreKit products are not available yet. Add the subscription product IDs in App Store Connect or a StoreKit config file."))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    if !flow.purchaseErrorMessage.isEmpty {
                        Text(flow.purchaseErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        guard !purchaseTaskRunning else { return }
                        purchaseTaskRunning = true
                        Task {
                            let purchased = await flow.purchase(plan: .annual)
                            purchaseTaskRunning = false
                            if purchased {
                                flow.currentScreen = .dashboard
                            }
                        }
                    } label: {
                        HStack {
                            if purchaseTaskRunning || flow.purchaseInFlight {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(localized("Start Free Trial"))
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(purchaseTaskRunning || flow.purchaseInFlight)

                    Button(localized("Maybe Later")) {
                        flow.skipPaywall()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await flow.loadProductsIfNeeded()
        }
    }

    private func paywallLine(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(localized(text))
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

private struct FlowSelectableRow: View {
    @Environment(\.locale) private var locale
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(localized(title))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .orange : Color.gray.opacity(0.4))
            }
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

private struct FlowValueCard<Content: View>: View {
    @Environment(\.locale) private var locale
    let title: String
    let value: String
    let content: Content

    init(title: String, value: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(localized(title))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.title3.weight(.semibold))
            }
            content
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

private struct FlowPrimaryButton: View {
    @Environment(\.locale) private var locale
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(localized(title))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}
