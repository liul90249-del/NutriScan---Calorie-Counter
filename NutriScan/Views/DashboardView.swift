import SwiftData
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var flow: AppFlowViewModel
    @Environment(\.locale) private var locale
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var entries: [FoodEntry]
    @State private var currentCardIndex = 0

    private var todaysEntries: [FoodEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDateInToday($0.createdAt) }
    }

    private var recentMeals: [DashboardMeal] {
        todaysEntries.prefix(5).map {
            DashboardMeal(
                title: $0.mealType,
                time: $0.createdAt.formatted(.dateTime.hour().minute().locale(locale)),
                items: [$0.foodName],
                calories: $0.calories,
                protein: Int($0.protein.rounded()),
                carbs: Int($0.carbs.rounded()),
                fat: Int($0.fat.rounded()),
                emoji: mealEmoji(for: $0.mealType)
            )
        }
    }

    private var consumedCalories: Int {
        recentMeals.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Int {
        recentMeals.reduce(0) { $0 + $1.protein }
    }

    private var totalCarbs: Int {
        recentMeals.reduce(0) { $0 + $1.carbs }
    }

    private var totalFat: Int {
        recentMeals.reduce(0) { $0 + $1.fat }
    }

    private var targetCalories: Int {
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

    private var exerciseCalories: Int { 250 }

    private var remainingCalories: Int {
        targetCalories + exerciseCalories - consumedCalories
    }

    private var calorieProgress: Double {
        let denominator = Double(max(targetCalories + exerciseCalories, 1))
        return min(max(Double(consumedCalories) / denominator, 0), 1)
    }

    private var targetProtein: Int {
        Int((flow.profile.weight * 1.6).rounded())
    }

    private var targetCarbs: Int {
        Int((Double(targetCalories) * 0.45 / 4).rounded())
    }

    private var targetFat: Int {
        Int((Double(targetCalories) * 0.3 / 9).rounded())
    }

    private var weightHistory: [WeightPoint] {
        let current = flow.profile.weight
        return [
            .init(date: "4/22", weight: current + 0.8),
            .init(date: "4/23", weight: current + 0.5),
            .init(date: "4/24", weight: current + 0.3),
            .init(date: "4/25", weight: current + 0.2),
            .init(date: "4/26", weight: current),
            .init(date: "4/27", weight: current - 0.2),
            .init(date: "4/28", weight: current),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    calorieBudgetCard
                    horizontalCardsSection
                    todaysMealsSection
                }
                .padding(.bottom, 120)
            }
            .background(Color(hex: "#F9F9FA"))
        }
        .background(Color(hex: "#F9F9FA").ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized("Today"))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(Date.now.formatted(.dateTime.year().month().day().weekday(.wide).locale(locale)))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(.white)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.4)
        }
    }

    private var calorieBudgetCard: some View {
        VStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized("Calorie Budget"))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.66))
                        Text("\(max(remainingCalories, 0))")
                            .font(.system(size: 54, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text(localized("remaining kcal"))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.14), lineWidth: 8)
                            .frame(width: 96, height: 96)

                        Circle()
                            .trim(from: 0, to: calorieProgress)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 96, height: 96)

                        Text("\(Int(calorieProgress * 100))%")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(spacing: 8) {
                    HStack {
                        formulaValue("\(targetCalories)")
                        formulaSign("+")
                        formulaValue("\(exerciseCalories)")
                        formulaSign("-")
                        formulaValue("\(consumedCalories)")
                        formulaSign("=")
                        formulaValue("\(remainingCalories)")
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                    HStack {
                        formulaLabel(localized("Goal"))
                        Spacer()
                        formulaLabel(localized("Exercise"))
                        Spacer()
                        formulaLabel(localized("Consumed"))
                        Spacer()
                        formulaLabel(localized("Left"))
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(24)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
    }

    private var horizontalCardsSection: some View {
        VStack(spacing: 14) {
            TabView(selection: $currentCardIndex) {
                activityCard
                    .tag(0)
                nutrientsCard
                    .tag(1)
                habitsCard
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 292)

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == currentCardIndex ? Color.black : Color.gray.opacity(0.25))
                        .frame(width: index == currentCardIndex ? 24 : 6, height: 6)
                }
            }
        }
        .padding(.bottom, 22)
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                metricTile(icon: "figure.walk", title: localized("Exercise"), value: "\(exerciseCalories)", suffix: localized("kcal"))
                metricTile(icon: "scalemass", title: localized("Weight"), value: String(format: "%.1f", flow.profile.weight), suffix: localized("kg"))
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(localized("Weight Trend"))
                        .font(.headline)
                    Spacer()
                    let change = weightHistory.last!.weight - weightHistory.first!.weight
                    HStack(spacing: 4) {
                        Image(systemName: change <= 0 ? "arrow.down.right" : "arrow.up.right")
                        Text(String(format: "%+.1f kg", change))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(change <= 0 ? .green : .red)
                }

                weightChart
            }
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(.horizontal, 24)
    }

    private var nutrientsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Nutrient Budget"))
                .font(.headline)

            macroProgress(title: localized("Protein"), current: totalProtein, target: targetProtein)
            macroProgress(title: localized("Carbs"), current: totalCarbs, target: targetCarbs)
            macroProgress(title: localized("Fat"), current: totalFat, target: targetFat)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 24)
    }

    private var habitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Healthy Habits"))
                .font(.headline)

            habitRow(icon: "clock.fill", emoji: "⏰", title: localized("Fasting"), subtitle: localized("2h 15m left"))
            habitRow(icon: "drop.fill", emoji: "💧", title: localized("Water"), subtitle: localized("1.5L / 2.5L"))
            habitRow(icon: "moon.fill", emoji: "😴", title: localized("Sleep"), subtitle: localized("7h 30m"))
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 24)
    }

    private var todaysMealsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Today's Meals"))
                .font(.headline)
                .padding(.horizontal, 24)

            if recentMeals.isEmpty {
                emptyMealsCard
                    .padding(.horizontal, 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(recentMeals) { meal in
                        HStack(alignment: .top, spacing: 14) {
                            Text(meal.emoji)
                                .font(.system(size: 42))

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(localizedMealType(meal.title))
                                            .font(.headline)
                                        Text(meal.time)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(meal.calories)")
                                            .font(.title3.weight(.semibold))
                                            .monospacedDigit()
                                        Text(localized("kcal"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Text(meal.items.joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                Text(localizedFormat("P %lldg • C %lldg • F %lldg", meal.protein, meal.carbs, meal.fat))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var emptyMealsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Nothing logged for today"))
                .font(.headline)

            Text(localized("Start with a meal photo and NutriScan will build your calorie and macro dashboard from real entries."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                flow.openCamera()
            } label: {
                Label(localized("Log your first meal"), systemImage: "camera.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var weightChart: some View {
        let values = weightHistory.map(\.weight)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = max(maxValue - minValue, 0.4)

        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(weightHistory) { point in
                    let ratio = (point.weight - minValue) / range
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black)
                            .frame(height: max(10, ratio * 62))
                        Text(point.date)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(localizedFormat("Last logged: %@", weightHistory[weightHistory.count - 2].date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func formulaValue(_ value: String) -> some View {
        Text(value)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .monospacedDigit()
    }

    private func formulaSign(_ value: String) -> some View {
        Text(value)
            .foregroundStyle(.white.opacity(0.45))
    }

    private func formulaLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity)
    }

    private func metricTile(icon: String, title: String, value: String, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.black)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 38, alignment: .topLeading)

            Text(value)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(suffix)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 136, alignment: .topLeading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func macroProgress(title: String, current: Int, target: Int) -> some View {
        let safeTarget = max(target, 1)
        let safeCurrent = min(max(current, 0), safeTarget)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(localizedFormat("%lldg / %lldg", current, target))
                    .monospacedDigit()
                    .font(.subheadline)
            }

            ProgressView(value: Double(safeCurrent), total: Double(safeTarget))
                .tint(.black)
        }
    }

    private func habitRow(icon: String, emoji: String, title: String, subtitle: String) -> some View {
        HStack {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: icon).foregroundStyle(.black))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(emoji)
                .font(.title2)
        }
    }

    private func mealEmoji(for mealType: String) -> String {
        switch mealType.lowercased() {
        case "breakfast": return "🥣"
        case "lunch": return "🍱"
        case "dinner": return "🍽️"
        case "snack": return "🫐"
        default: return "🍴"
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }

    private func localizedMealType(_ mealType: String) -> String {
        switch mealType {
        case "Breakfast": return localized("Breakfast")
        case "Lunch": return localized("Lunch")
        case "Dinner": return localized("Dinner")
        case "Snack": return localized("Snack")
        default: return mealType
        }
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }
}

private struct DashboardMeal: Identifiable {
    let id = UUID()
    let title: String
    let time: String
    let items: [String]
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let emoji: String
}

private struct WeightPoint: Identifiable {
    let id = UUID()
    let date: String
    let weight: Double
}
