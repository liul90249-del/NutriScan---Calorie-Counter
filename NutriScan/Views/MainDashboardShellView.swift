import SwiftData
import SwiftUI

struct MainDashboardShellView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    @State private var slideEnergy: CGFloat = 0
    @State private var slideDirection: CGFloat = 1
    private let bottomBarHeight: CGFloat = 62

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch flow.selectedTab {
                case .today:
                    DashboardView()
                case .analysis:
                    AnalysisDashboardView()
                case .suggestions:
                    SuggestionsDashboardView()
                case .settings:
                    ProfileView()
                }
            }

            bottomBar
        }
        .gesture(tabSwipeGesture)
    }

    private var bottomBar: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 14
            let itemCount: CGFloat = 5
            let itemWidth = max((proxy.size.width - horizontalPadding * 2) / itemCount, 1)
            let selectedIndex = visualTabIndex(for: flow.selectedTab)

            ZStack(alignment: .center) {
                bottomBarBackground

                LiquidGlassTabHighlight(energy: slideEnergy, direction: slideDirection)
                    .frame(width: itemWidth - 10, height: 44)
                    .offset(x: (CGFloat(selectedIndex) - 2) * itemWidth)
                    .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selectedIndex)

                HStack(spacing: 0) {
                    navItem(title: "Today", systemImage: "house.fill", tab: .today)
                    navItem(title: "Analysis", systemImage: "chart.bar.fill", tab: .analysis)

                    Button {
                        flow.openCamera()
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(Color.primary)
                                    .frame(width: 64, height: 64)
                                    .shadow(color: .black.opacity(0.18), radius: 18, y: 9)
                                Image(systemName: "plus")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(Color(uiColor: .systemBackground))
                            }
                            Text(localized("Log"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .offset(y: -18)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)

                    navItem(title: "Ideas", systemImage: "lightbulb.fill", tab: .suggestions)
                    navItem(title: "Settings", systemImage: "gearshape.fill", tab: .settings)
                }
                .padding(.horizontal, horizontalPadding)
                .frame(height: bottomBarHeight, alignment: .center)
            }
            .onChange(of: flow.selectedTab) { oldTab, newTab in
                triggerSlideFlow(from: oldTab, to: newTab)
            }
        }
        .frame(height: bottomBarHeight)
        .padding(.horizontal, 34)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var bottomBarBackground: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.5), Color.white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.14), radius: 22, y: 8)
    }

    /// Fires the chromatic "liquid glass" burst when the selected tab changes.
    /// Energy is seeded to 1 instantly, then eased back to 0 so the rainbow
    /// rim brightens and the red/cyan ghosts trail the moving capsule.
    private func triggerSlideFlow(from oldTab: AppFlowViewModel.MainTab, to newTab: AppFlowViewModel.MainTab) {
        let delta = visualTabIndex(for: newTab) - visualTabIndex(for: oldTab)
        guard delta != 0 else { return }
        slideDirection = delta > 0 ? 1 : -1
        slideEnergy = 1
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.5)) {
                slideEnergy = 0
            }
        }
    }

    private func visualTabIndex(for tab: AppFlowViewModel.MainTab) -> Int {
        switch tab {
        case .today:
            return 0
        case .analysis:
            return 1
        case .suggestions:
            return 3
        case .settings:
            return 4
        }
    }

    private var tabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 36)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.4 else { return }
                guard abs(horizontal) > 56 else { return }

                if horizontal < 0 {
                    moveTab(direction: 1)
                } else {
                    moveTab(direction: -1)
                }
            }
    }

    private func moveTab(direction: Int) {
        let tabs = AppFlowViewModel.MainTab.allCases
        guard let currentIndex = tabs.firstIndex(of: flow.selectedTab) else { return }
        let nextIndex = min(max(currentIndex + direction, 0), tabs.count - 1)
        let nextTab = tabs[nextIndex]

        guard nextTab != flow.selectedTab else { return }
        AnalyticsService.logTabSelected(nextTab)
        withAnimation(.snappy(duration: 0.22)) {
            flow.selectedTab = nextTab
        }
    }

    private func navItem(title: String, systemImage: String, tab: AppFlowViewModel.MainTab) -> some View {
        let isSelected = flow.selectedTab == tab
        return Button {
            AnalyticsService.logTabSelected(tab)
            flow.selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(localized(title))
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}

/// Sliding selection capsule with a hand-rolled "liquid glass" look:
/// a frosted lens with a top sheen and an iridescent rim that brightens,
/// sweeps, and sheds red/cyan chromatic ghosts while it slides between tabs.
private struct LiquidGlassTabHighlight: View {
    /// 1 right after a tab change, eased back to 0 — drives the chromatic burst.
    var energy: CGFloat
    /// +1 when moving toward a later tab, -1 toward an earlier one.
    var direction: CGFloat

    var body: some View {
        let shape = Capsule(style: .continuous)
        // Stretch from the leading edge so the capsule trails a liquid tail
        // in the direction of travel while sliding, then relaxes at rest.
        let stretchAnchor = UnitPoint(x: direction > 0 ? 1 : 0, y: 0.5)

        shape
            .fill(.ultraThinMaterial)
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(motionTrail(shape: shape))
            .overlay(
                // Glass rim: a clean neutral outline that reads at rest and
                // brightens while sliding.
                shape.strokeBorder(Color.white.opacity(0.26 + 0.5 * energy), lineWidth: 1)
            )
            // Soft neutral glow that lights up only during a slide.
            .shadow(color: .white.opacity(0.16 * energy), radius: 12 * energy)
            .compositingGroup()
            // Fade the resting oval; it only becomes prominent during a slide.
            .opacity(0.5 + 0.5 * energy)
            // Liquid stretch/squash in the direction of travel.
            .scaleEffect(x: 1 + 0.16 * energy, y: 1 - 0.05 * energy, anchor: stretchAnchor)
    }

    /// Neutral white motion trail that bleeds from both edges while sliding —
    /// a monochrome liquid-glass shimmer, no chromatic color.
    @ViewBuilder
    private func motionTrail(shape: Capsule) -> some View {
        ZStack {
            shape
                .strokeBorder(Color.white, lineWidth: 1.5)
                .blur(radius: 3)
                .offset(x: direction * 11 * energy)
            shape
                .strokeBorder(Color.white, lineWidth: 1.5)
                .blur(radius: 3)
                .offset(x: -direction * 11 * energy)
        }
        .opacity(0.32 * energy)
    }
}

private struct AnalysisDashboardView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var entries: [FoodEntry]
    @State private var selectedRange: TrendRange = .sevenDays
    @State private var showPaywall = false

    private var filteredEntries: [FoodEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -(selectedRange.dayCount - 1), to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
        return entries.filter { $0.createdAt >= cutoff }
    }

    private var groupedDays: [DailyNutritionSummary] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { calendar.startOfDay(for: $0.createdAt) }

        let days = (0..<selectedRange.dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now))
        }

        return days.reversed().map { day in
            let items = grouped[day, default: []]
            return DailyNutritionSummary(
                date: day,
                calories: items.reduce(0) { $0 + $1.calories },
                protein: items.reduce(0) { $0 + $1.protein },
                carbs: items.reduce(0) { $0 + $1.carbs },
                fat: items.reduce(0) { $0 + $1.fat },
                mealCount: items.count
            )
        }
    }

    private var loggedDays: [DailyNutritionSummary] {
        groupedDays.filter { $0.mealCount > 0 }
    }

    private var averageCalories: Int {
        guard !loggedDays.isEmpty else { return 0 }
        return loggedDays.map(\.calories).reduce(0, +) / loggedDays.count
    }

    private var averageProtein: Int {
        guard !loggedDays.isEmpty else { return 0 }
        let total = loggedDays.reduce(0.0) { $0 + $1.protein }
        return Int((total / Double(loggedDays.count)).rounded())
    }

    private var averageCarbs: Int {
        guard !loggedDays.isEmpty else { return 0 }
        let total = loggedDays.reduce(0.0) { $0 + $1.carbs }
        return Int((total / Double(loggedDays.count)).rounded())
    }

    private var averageFat: Int {
        guard !loggedDays.isEmpty else { return 0 }
        let total = loggedDays.reduce(0.0) { $0 + $1.fat }
        return Int((total / Double(loggedDays.count)).rounded())
    }

    private var calorieGoal: Int {
        let base = flow.profile.gender == "Female" ? 1500 : 1800
        let activityBoost: Int
        switch flow.profile.activityLevel {
        case "Very active": activityBoost = 450
        case "Moderately active": activityBoost = 300
        case "Lightly active": activityBoost = 180
        default: activityBoost = 0
        }
        let maintenance = base + activityBoost
        let deficit = Int((flow.profile.weeklyLossRate * 7700 / 7).rounded())
        return max(1200, maintenance - deficit)
    }

    private var targetProtein: Int {
        Int((flow.profile.weight * 1.6).rounded())
    }

    private var targetCarbs: Int {
        Int((Double(calorieGoal) * 0.45 / 4).rounded())
    }

    private var targetFat: Int {
        Int((Double(calorieGoal) * 0.3 / 9).rounded())
    }

    private var macroProgressItems: [MacroProgressItem] {
        [
            MacroProgressItem(title: "Protein", current: averageProtein, target: max(targetProtein, 1), tint: Color(hex: "#2563EB"), unit: "g"),
            MacroProgressItem(title: "Carbs", current: averageCarbs, target: max(targetCarbs, 1), tint: Color(hex: "#F97316"), unit: "g"),
            MacroProgressItem(title: "Fat", current: averageFat, target: max(targetFat, 1), tint: Color(hex: "#059669"), unit: "g")
        ]
    }

    private var calorieTargetHitRate: Int {
        guard !loggedDays.isEmpty else { return 0 }
        let hitCount = loggedDays.filter { abs($0.calories - calorieGoal) <= 150 }.count
        return Int((Double(hitCount) / Double(loggedDays.count) * 100).rounded())
    }

    private var proteinTargetHitRate: Int {
        guard !loggedDays.isEmpty else { return 0 }
        let hitCount = loggedDays.filter { Int($0.protein.rounded()) >= Int(Double(targetProtein) * 0.85) }.count
        return Int((Double(hitCount) / Double(loggedDays.count) * 100).rounded())
    }

    private var loggingConsistency: Int {
        let loggedCount = groupedDays.filter { $0.mealCount > 0 }.count
        return Int((Double(loggedCount) / Double(max(groupedDays.count, 1)) * 100).rounded())
    }

    private var calorieTrendDelta: Int {
        guard let first = loggedDays.first?.calories, let last = loggedDays.last?.calories else { return 0 }
        return last - first
    }

    private var calorieTrendText: String {
        guard loggedDays.count >= 2 else { return localized("Log a few days to spot trends.") }
        if calorieTrendDelta > 120 {
            return localizedFormat("Calories are trending upward by %lld kcal across the selected period.", calorieTrendDelta)
        } else if calorieTrendDelta < -120 {
            return localizedFormat("Calories are trending down by %lld kcal across the selected period.", abs(calorieTrendDelta))
        }
        return localized("Calories are staying fairly steady across the selected period.")
    }

    private var mealTypeBreakdown: [MealTypeBreakdown] {
        let grouped = Dictionary(grouping: filteredEntries, by: \.mealType)

        return grouped
            .map { mealType, items in
                MealTypeBreakdown(
                    mealType: mealType,
                    count: items.count,
                    calories: items.reduce(0) { $0 + $1.calories }
                )
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.calories > $1.calories
                }
                return $0.count > $1.count
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(localized("Analysis"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))

                rangePicker

                if filteredEntries.isEmpty {
                    emptyState(
                        title: localized("No trend data yet"),
                        subtitle: localized("Save meals across a few days to unlock calorie and macro trends.")
                    )
                } else {
                    summaryCard
                    trendCard
                    adherenceCard
                    macroCard
                    mealTypeCard
                    dailyBreakdownCard
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .background(Color(hex: "#FAFAF8").ignoresSafeArea())
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallSheet()
                .environmentObject(flow)
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 10) {
            ForEach(TrendRange.allCases) { range in
                Button {
                    guard range != .thirtyDays || flow.hasPremiumAnalytics else {
                        showPaywall = true
                        return
                    }
                    selectedRange = range
                } label: {
                    HStack(spacing: 6) {
                        Text(range.title(locale: locale))
                        if range == .thirtyDays && !flow.hasPremiumAnalytics {
                            Image(systemName: "crown.fill")
                                .font(.caption2)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(selectedRange == range ? Color.black : Color.white, in: Capsule())
                    .foregroundStyle(selectedRange == range ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localizedFormat("%@ summary", selectedRange.title(locale: locale)))
                .font(.headline)

            HStack(spacing: 12) {
                statChip(title: localized("Avg kcal"), value: "\(averageCalories)", tint: Color.black)
                statChip(title: localized("Goal"), value: "\(calorieGoal)", tint: Color(hex: "#2563EB"))
                statChip(title: localized("Delta"), value: "\(averageCalories - calorieGoal)", tint: Color(hex: averageCalories > calorieGoal ? "#DC2626" : "#059669"))
            }

            Text(localizedFormat("%lld of %lld days logged", loggedDays.count, selectedRange.dayCount))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Daily calorie trend"))
                .font(.headline)

            HStack(alignment: .bottom, spacing: 8) {
                let maxCalories = max(groupedDays.map(\.calories).max() ?? 0, calorieGoal, 1)
                ForEach(groupedDays) { day in
                    VStack(spacing: 8) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.gray.opacity(0.12))
                                .frame(height: 132)

                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(day.calories > calorieGoal ? Color(hex: "#F97316") : Color(hex: "#111827"))
                                .frame(height: max(CGFloat(day.calories) / CGFloat(maxCalories) * 132, day.calories == 0 ? 6 : 18))
                        }

                        Text(day.shortLabel(locale: locale))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(calorieTrendText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var adherenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Goal adherence"))
                .font(.headline)

            HStack(spacing: 12) {
                adherenceChip(title: localized("Calorie target"), value: "\(calorieTargetHitRate)%", subtitle: localized("within ±150 kcal"), tint: Color(hex: "#111827"))
                adherenceChip(title: localized("Protein target"), value: "\(proteinTargetHitRate)%", subtitle: localized("85%+ of goal"), tint: Color(hex: "#2563EB"))
                adherenceChip(title: localized("Logging"), value: "\(loggingConsistency)%", subtitle: localized("days completed"), tint: Color(hex: "#059669"))
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var macroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Average macros per logged day"))
                .font(.headline)

            ForEach(macroProgressItems) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(localized(item.title))
                        Spacer()
                        Text("\(item.current)\(item.unit) / \(item.target)\(item.unit)")
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { proxy in
                        let progress = clampedProgress(Double(item.current) / Double(item.target))

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.12))
                            Capsule()
                                .fill(item.tint)
                                .frame(width: max(proxy.size.width * progress, 12))
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var mealTypeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Meal distribution"))
                .font(.headline)

            ForEach(mealTypeBreakdown) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedMealType(item.mealType, locale: locale))
                        Text(localizedFormat("%lld entries", item.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(localizedFormat("%lld kcal", item.calories))
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var dailyBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Daily breakdown"))
                .font(.headline)

            ForEach(groupedDays.filter { $0.mealCount > 0 }.reversed()) { day in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(day.longLabel(locale: locale))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(localizedFormat("%lld kcal", day.calories))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(localizedFormat("%lld meals logged", day.mealCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(localizedFormat("P %lldg • C %lldg • F %lldg", Int(day.protein.rounded()), Int(day.carbs.rounded()), Int(day.fat.rounded())))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)

                if day.id != groupedDays.filter({ $0.mealCount > 0 }).first?.id {
                    Divider()
                }
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func adherenceChip(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }

    private func statChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct SuggestionsDashboardView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var entries: [FoodEntry]
    @State private var showPaywall = false
    @State private var coachSuggestions: CoachSuggestionsResponse?
    @State private var isLoadingCoachSuggestions = false
    @State private var coachSuggestionsErrorMessage = ""

    private let coachSuggestionsService = CoachSuggestionsService()
    private let isoDateFormatter = ISO8601DateFormatter()
    private let cacheMaxAge: TimeInterval = 48 * 60 * 60
    private let changedMealsRefreshInterval: TimeInterval = 6 * 60 * 60
    private let cachePayloadKey = "nutriscan.coach_suggestions.payload"
    private let cacheDateKey = "nutriscan.coach_suggestions.saved_at"
    private let cacheFingerprintKey = "nutriscan.coach_suggestions.meal_fingerprint"

    private var recentEntries: [FoodEntry] {
        Array(entries.prefix(8))
    }

    private var coachRequestEntries: [FoodEntry] {
        Array(entries.prefix(30))
    }

    private var lowProteinMeals: [FoodEntry] {
        recentEntries.filter { $0.protein < 25 }
    }

    private var highCalorieMeals: [FoodEntry] {
        recentEntries.filter { $0.calories > 650 }
    }

    private var lowFiberStyleMeals: [FoodEntry] {
        recentEntries.filter { $0.carbs > 45 && $0.protein < 20 }
    }

    private var suggestionCards: [SuggestionCardModel] {
        var cards: [SuggestionCardModel] = []

        if let meal = lowProteinMeals.first {
            cards.append(
                SuggestionCardModel(
                    title: localizedFormat("Raise protein in %@", localizedMealType(meal.mealType, locale: locale).lowercased()),
                    subtitle: localizedFormat("%@ logged only %lldg protein.", meal.foodName, Int(meal.protein.rounded())),
                    bullets: [
                        localized("Add Greek yogurt, eggs, tofu, or chicken for a +15g to +25g protein bump."),
                        localizedFormat("Aim for about %lldg protein in each main meal.", max(Int((flow.profile.weight * 0.3).rounded()), 25))
                    ],
                    accent: Color(hex: "#2563EB"),
                    icon: "figure.strengthtraining.traditional"
                )
            )
        }

        if let meal = highCalorieMeals.first {
            cards.append(
                SuggestionCardModel(
                    title: localized("Lighten the densest meal"),
                    subtitle: localizedFormat("%@ was your heaviest recent entry at %lld kcal.", meal.foodName, meal.calories),
                    bullets: [
                        localized("Swap one calorie-dense side for fruit, soup, or a vegetable volume add-on."),
                        localized("Keep the core meal, but trim sauces, oils, or sugary drinks first.")
                    ],
                    accent: Color(hex: "#F97316"),
                    icon: "flame.fill"
                )
            )
        }

        if let meal = lowFiberStyleMeals.first {
            cards.append(
                SuggestionCardModel(
                    title: localized("Steady energy with better carb pairing"),
                    subtitle: localizedFormat("%@ leaned high-carb without enough protein.", meal.foodName),
                    bullets: [
                        localized("Pair starches with lean protein or beans to slow hunger rebound."),
                        localized("Favor oats, rice with protein, potatoes with yogurt sauce, or wraps with chicken.")
                    ],
                    accent: Color(hex: "#059669"),
                    icon: "leaf.fill"
                )
            )
        }

        if cards.isEmpty {
            cards = [
                SuggestionCardModel(
                    title: localized("Start with 3 balanced meals"),
                    subtitle: localized("You need a few saved meals before NutriScan can personalize recommendations."),
                    bullets: [
                        localized("Log breakfast, lunch, and dinner once to establish a pattern."),
                        localized("Try to include a protein source in each meal photo.")
                    ],
                    accent: Color.black,
                    icon: "sparkles"
                )
            ]
        }

        cards.append(
            SuggestionCardModel(
                title: localized("Consistency target for this week"),
                subtitle: localized("A realistic win is better than an aggressive reset."),
                bullets: [
                    localized("Log at least 2 meals per day for the next 5 days."),
                    localized("Review the Analysis tab after each day to spot calorie drift early.")
                ],
                accent: Color(hex: "#7C3AED"),
                icon: "calendar.badge.clock"
            )
        )

        return cards
    }

    var body: some View {
        let isLocked = !flow.hasPremiumSuggestions
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(localized("Ideas"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))

                premiumSuggestionsContent
            }
            .padding(20)
            .padding(.bottom, 120)
            // Locked users see the real suggestions as a blurred, non-interactive
            // preview instead of an abrupt subscription pop-up.
            .blur(radius: isLocked ? 7 : 0)
            .allowsHitTesting(!isLocked)
        }
        .background(Color(hex: "#FAFAF8").ignoresSafeArea())
        .overlay {
            if isLocked {
                premiumPreviewOverlay
            }
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallSheet()
                .environmentObject(flow)
        }
        .task {
            await loadCoachSuggestionsIfNeeded(force: false)
        }
        .onChange(of: flow.hasActivePremium) { _, hasActivePremium in
            guard hasActivePremium else {
                coachSuggestions = nil
                clearCoachSuggestionsCache()
                return
            }

            Task {
                await loadCoachSuggestionsIfNeeded(force: false)
            }
        }
        .onChange(of: entries.count) { _, _ in
            Task {
                await loadCoachSuggestionsIfNeeded(force: false)
            }
        }
    }

    /// Soft, centered upsell shown over the blurred suggestions preview for
    /// locked users — a gentle trial invitation instead of an abrupt paywall.
    private var premiumPreviewOverlay: some View {
        VStack(spacing: 26) {
            Spacer()

            Text(localized("Your diet and health — our top priority and care"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                AnalyticsService.logPaywallViewed(source: "suggestions_preview")
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Text(localized("Start 3-day free trial"))
                        .font(.headline)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.vertical, 17)
                .padding(.horizontal, 32)
                .background(Color.black, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var premiumSuggestionsContent: some View {
        if let coachSuggestions {
            Text(coachSuggestions.summary)
                .font(.body)
                .foregroundStyle(.secondary)

            nextGoalCard(coachSuggestions.nextGoal)

            ForEach(Array(coachSuggestions.cards.enumerated()), id: \.offset) { index, card in
                remoteSuggestionCard(card, accent: accentColor(for: index))
            }
        } else {
            Text(localized(isLoadingCoachSuggestions ? "Personalizing suggestions in the background." : "Suggestions update from your recent meal log."))
                .foregroundStyle(.secondary)
        }

        if coachSuggestions == nil {
            ForEach(suggestionCards) { card in
                localSuggestionCard(card)
            }
        }

        if isLoadingCoachSuggestions {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text(localized("Personalizing suggestions in the background."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !coachSuggestionsErrorMessage.isEmpty {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(Color(hex: "#B45309"))
                Text(localized(coachSuggestionsErrorMessage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(localized("Retry")) {
                    Task {
                        await loadCoachSuggestionsIfNeeded(force: true)
                    }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(hex: "#FEF3C7").opacity(0.72), in: Capsule())
        }
    }

    private func localSuggestionCard(_ card: SuggestionCardModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(card.title)
                    .font(.headline)
            } icon: {
                Image(systemName: card.icon)
            }
            .foregroundStyle(card.accent)

            Text(card.subtitle)
                .foregroundStyle(.secondary)

            bulletList(card.bullets, accent: card.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(card.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func remoteSuggestionCard(_ card: CoachSuggestionResponseCard, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(card.title)
                    .font(.headline)
            } icon: {
                Image(systemName: iconName(for: card.targetFocus))
            }
            .foregroundStyle(accent)

            Text(card.subtitle)
                .foregroundStyle(.secondary)

            bulletList(card.bullets, accent: accent)

            if !card.suggestedFoods.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(card.suggestedFoods, id: \.self) { food in
                        Text(food)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(.white.opacity(0.75), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func nextGoalCard(_ nextGoal: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: "#7C3AED"))
            VStack(alignment: .leading, spacing: 5) {
                Text(localized("Next goal"))
                    .font(.headline)
                Text(nextGoal)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(hex: "#7C3AED").opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func bulletList(_ bullets: [String], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(bullet)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private func loadCoachSuggestionsIfNeeded(force: Bool) async {
        guard flow.hasPremiumSuggestions else { return }
        let currentFingerprint = mealFingerprint()
        if !force {
            restoreCachedCoachSuggestionsIfNeeded()
            guard shouldRefreshCoachSuggestions(currentFingerprint: currentFingerprint) else { return }
        }
        guard !isLoadingCoachSuggestions else { return }

        isLoadingCoachSuggestions = true
        coachSuggestionsErrorMessage = ""
        defer {
            isLoadingCoachSuggestions = false
        }

        do {
            let response = try await coachSuggestionsService.fetchSuggestions(payload: coachSuggestionsRequest())
            coachSuggestions = response.cards.isEmpty ? nil : response
            if !response.cards.isEmpty {
                saveCoachSuggestionsCache(response, fingerprint: currentFingerprint)
            }
        } catch let error as CoachSuggestionsError {
            coachSuggestionsErrorMessage = error.localizedDescription
        } catch {
            coachSuggestionsErrorMessage = "Nutrition coaching suggestions are unavailable right now."
        }
    }

    private func restoreCachedCoachSuggestionsIfNeeded() {
        guard coachSuggestions == nil,
              let data = UserDefaults.standard.data(forKey: cachePayloadKey),
              let cached = try? JSONDecoder().decode(CoachSuggestionsResponse.self, from: data) else {
            return
        }
        coachSuggestions = cached
    }

    private func shouldRefreshCoachSuggestions(currentFingerprint: String) -> Bool {
        guard let savedAt = UserDefaults.standard.object(forKey: cacheDateKey) as? Date else { return true }
        let age = Date().timeIntervalSince(savedAt)
        guard age < cacheMaxAge else { return true }

        let savedFingerprint = UserDefaults.standard.string(forKey: cacheFingerprintKey)
        if savedFingerprint != currentFingerprint {
            return age >= changedMealsRefreshInterval
        }

        return false
    }

    private func saveCoachSuggestionsCache(_ response: CoachSuggestionsResponse, fingerprint: String) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        UserDefaults.standard.set(data, forKey: cachePayloadKey)
        UserDefaults.standard.set(Date(), forKey: cacheDateKey)
        UserDefaults.standard.set(fingerprint, forKey: cacheFingerprintKey)
    }

    private func clearCoachSuggestionsCache() {
        UserDefaults.standard.removeObject(forKey: cachePayloadKey)
        UserDefaults.standard.removeObject(forKey: cacheDateKey)
        UserDefaults.standard.removeObject(forKey: cacheFingerprintKey)
    }

    private func mealFingerprint() -> String {
        coachRequestEntries
            .map { entry in
                [
                    entry.id.uuidString,
                    "\(entry.calories)",
                    "\(Int(entry.protein.rounded()))",
                    "\(Int(entry.carbs.rounded()))",
                    "\(Int(entry.fat.rounded()))",
                    entry.createdAt.timeIntervalSince1970.formatted(.number.precision(.fractionLength(0)))
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    private func coachSuggestionsRequest() -> CoachSuggestionsRequest {
        CoachSuggestionsRequest(
            locale: locale.identifier,
            profile: CoachUserProfilePayload(
                gender: flow.profile.gender,
                height: flow.profile.height,
                weight: flow.profile.weight,
                goalWeight: flow.profile.goalWeight,
                activityLevel: flow.profile.activityLevel,
                weeklyLossRate: flow.profile.weeklyLossRate,
                unit: flow.profile.unit.rawValue,
                isPremium: flow.hasActivePremium
            ),
            recentMeals: coachRequestEntries.map { entry in
                CoachMealPayload(
                    mealType: entry.mealType,
                    foodName: entry.foodName,
                    calories: entry.calories,
                    protein: entry.protein,
                    carbs: entry.carbs,
                    fat: entry.fat,
                    notes: entry.notes,
                    createdAt: isoDateFormatter.string(from: entry.createdAt)
                )
            }
        )
    }

    private func accentColor(for index: Int) -> Color {
        let colors = [
            Color(hex: "#2563EB"),
            Color(hex: "#F97316"),
            Color(hex: "#059669"),
            Color(hex: "#7C3AED"),
            Color(hex: "#DC2626")
        ]
        return colors[index % colors.count]
    }

    private func iconName(for targetFocus: String) -> String {
        switch targetFocus.lowercased() {
        case "protein":
            return "figure.strengthtraining.traditional"
        case "calories", "calorie":
            return "flame.fill"
        case "carbs", "fiber", "vegetables":
            return "leaf.fill"
        case "hydration", "water":
            return "drop.fill"
        default:
            return "sparkles"
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }
}

private func localizedMealType(_ mealType: String, locale: Locale) -> String {
    switch mealType {
    case "Breakfast": return AppLocalization.localized("Breakfast", locale: locale)
    case "Lunch": return AppLocalization.localized("Lunch", locale: locale)
    case "Dinner": return AppLocalization.localized("Dinner", locale: locale)
    case "Snack": return AppLocalization.localized("Snack", locale: locale)
    default: return mealType
    }
}

private struct MacroProgressItem: Identifiable {
    let id = UUID()
    let title: String
    let current: Int
    let target: Int
    let tint: Color
    let unit: String
}

private enum TrendRange: String, CaseIterable, Identifiable {
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        AppLocalization.formatted("%lld days", locale: locale, [dayCount])
    }

    var dayCount: Int {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        }
    }
}

private struct DailyNutritionSummary: Identifiable {
    let date: Date
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let mealCount: Int

    var id: Date { date }

    func shortLabel(locale: Locale) -> String {
        date.formatted(.dateTime.weekday(.narrow).locale(locale))
    }

    func longLabel(locale: Locale) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
    }
}

private struct MealTypeBreakdown: Identifiable {
    let id = UUID()
    let mealType: String
    let count: Int
    let calories: Int
}

private struct SuggestionCardModel: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let bullets: [String]
    let accent: Color
    let icon: String
}

