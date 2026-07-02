import SwiftData
import SwiftUI

struct MealLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var entries: [FoodEntry]
    @State private var editingEntry: FoodEntry?
    @State private var searchText = ""
    @State private var selectedMealType = "All"

    private let mealTypeFilters = ["All", "Breakfast", "Lunch", "Dinner", "Snack"]

    private var filteredEntries: [FoodEntry] {
        entries.filter { entry in
            let matchesMealType = selectedMealType == "All" || entry.mealType == selectedMealType
            let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch =
                trimmedQuery.isEmpty ||
                entry.foodName.localizedCaseInsensitiveContains(trimmedQuery) ||
                entry.notes.localizedCaseInsensitiveContains(trimmedQuery)

            return matchesMealType && matchesSearch
        }
    }

    private var groupedEntries: [(date: Date, items: [FoodEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.createdAt)
        }

        return grouped
            .map { key, value in
                (date: key, items: value.sorted { $0.createdAt > $1.createdAt })
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                if groupedEntries.isEmpty {
                    ContentUnavailableView(
                        filteredEntries.isEmpty && !searchText.isEmpty || selectedMealType != "All" ? "No matching meals" : "No meals saved yet",
                        systemImage: "fork.knife.circle",
                        description: Text(localized(filteredEntries.isEmpty && !searchText.isEmpty || selectedMealType != "All" ? "Try another keyword or clear the current filter." : "Analyze and save your first meal to build your log."))
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(groupedEntries, id: \.date) { section in
                        Section(section.date.formatted(.dateTime.month(.wide).day().weekday(.wide).locale(locale))) {
                            ForEach(section.items) { entry in
                                Button {
                                    editingEntry = entry
                                } label: {
                                    mealRow(for: entry)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                deleteEntries(offsets: offsets, items: section.items)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Meal Log")
            .searchable(text: $searchText, prompt: "Search meals or notes")
            .safeAreaInset(edge: .top, spacing: 0) {
                filterBar
                    .background(.ultraThinMaterial)
            }
            .sheet(item: $editingEntry) { entry in
                MealEntryEditorView(entry: entry)
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(mealTypeFilters, id: \.self) { mealType in
                    Button {
                        selectedMealType = mealType
                    } label: {
                        Text(localizedMealType(mealType))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedMealType == mealType ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedMealType == mealType ? Color.black : Color.gray.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func mealRow(for entry: FoodEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.foodName)
                    .font(.headline)
                Spacer()
                Image(systemName: "square.and.pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(localizedMealType(entry.mealType)) • \(entry.createdAt.formatted(.dateTime.hour().minute().locale(locale)))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(localizedFormat("%lld kcal • P %lld • C %lld • F %lld", entry.calories, Int(entry.protein.rounded()), Int(entry.carbs.rounded()), Int(entry.fat.rounded())))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(entry.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private func deleteEntries(offsets: IndexSet, items: [FoodEntry]) {
        for index in offsets {
            modelContext.delete(items[index])
        }
    }

    private func localizedMealType(_ mealType: String) -> String {
        switch mealType {
        case "All": return AppLocalization.localized("All", locale: locale)
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

private struct MealEntryEditorView: View {
    @Bindable var entry: FoodEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Form {
                Section(localized("Meal")) {
                    TextField(localized("Food name"), text: $entry.foodName)

                    Picker(localized("Meal Type"), selection: $entry.mealType) {
                        Text("Breakfast").tag("Breakfast")
                        Text("Lunch").tag("Lunch")
                        Text("Dinner").tag("Dinner")
                        Text("Snack").tag("Snack")
                    }
                }

                Section(localized("Nutrition")) {
                    TextField(localized("Calories"), value: $entry.calories, format: .number)
                        .keyboardType(.numberPad)
                    TextField(localized("Protein"), value: $entry.protein, format: .number)
                        .keyboardType(.decimalPad)
                    TextField(localized("Carbs"), value: $entry.carbs, format: .number)
                        .keyboardType(.decimalPad)
                    TextField(localized("Fat"), value: $entry.fat, format: .number)
                        .keyboardType(.decimalPad)
                }

                Section(localized("Notes")) {
                    TextField(localized("Serving size, ingredients, context..."), text: $entry.notes, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .navigationTitle(localized("Edit Meal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localized("Close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key, locale: locale)
    }
}
