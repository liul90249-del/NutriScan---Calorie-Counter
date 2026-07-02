import SwiftData
import SwiftUI

struct MainDashboardShellView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    @State private var showPaywall = false

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
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallSheet()
                .environmentObject(flow)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                navItem(title: "Today", systemImage: "house.fill", tab: .today)
                navItem(title: "Analysis", systemImage: "chart.bar.fill", tab: .analysis)

                Button {
                    flow.openCamera()
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 56, height: 56)
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text(localized("Log"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .offset(y: -10)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                navItem(title: "Ideas", systemImage: "lightbulb.fill", tab: .suggestions)
                navItem(title: "Settings", systemImage: "gearshape.fill", tab: .settings)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(.white)
        }
    }

    private func navItem(title: String, systemImage: String, tab: AppFlowViewModel.MainTab) -> some View {
        Button {
            if tab == .suggestions && !flow.hasPremiumSuggestions {
                showPaywall = true
                return
            }
            flow.selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(localized(title))
                    .font(.caption2)
            }
            .foregroundStyle(flow.selectedTab == tab ? Color.black : Color.gray)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
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
                        Text(range.title)
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
            Text(localizedFormat("%@ summary", selectedRange.title))
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
                        Text(item.title)
                        Spacer()
                        Text("\(item.current)\(item.unit) / \(item.target)\(item.unit)")
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { proxy in
                        let progress = min(max(Double(item.current) / Double(item.target), 0), 1)

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

    private var recentEntries: [FoodEntry] {
        Array(entries.prefix(8))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(localized("Ideas"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))

                if flow.hasPremiumSuggestions {
                    Text(localized("Suggestions update from your recent meal log."))
                        .foregroundStyle(.secondary)

                    ForEach(suggestionCards) { card in
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

                            ForEach(card.bullets, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(card.accent)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 7)
                                    Text(bullet)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(card.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                } else {
                    lockedPremiumCard(
                        title: localized("Upgrade for personalized nutrition ideas"),
                        subtitle: localized("NutriScan Pro unlocks AI-driven meal suggestions, better protein nudges, and weekly food coaching."),
                        buttonTitle: localized("Unlock Pro")
                    ) {
                        showPaywall = true
                    }
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

    var title: String {
        switch self {
        case .sevenDays: return "7D"
        case .thirtyDays: return "30D"
        }
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

private func lockedPremiumCard(title: String, subtitle: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .foregroundStyle(Color.orange)
            Text(title)
                .font(.headline)
        }

        Text(subtitle)
            .foregroundStyle(.secondary)

        Button(action: action) {
            Text(buttonTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
}
