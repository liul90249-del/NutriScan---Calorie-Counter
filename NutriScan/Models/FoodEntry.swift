import Foundation
import SwiftData

@Model
final class FoodEntry {
    var id: UUID
    var createdAt: Date
    var mealType: String
    var foodName: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var notes: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        mealType: String,
        foodName: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        notes: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mealType = mealType
        self.foodName = foodName
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.notes = notes
    }
}
