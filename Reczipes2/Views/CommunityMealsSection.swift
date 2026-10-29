//
//  CommunityMealsSection.swift
//  Reczipes2
//
//  Δ-163: meals are shared with everyone, always. Other people's meals were
//  downloaded (CachedSharedMeal) but never shown; they appear in the Meals tab
//  under "Shared by others", read-only. A meal its owner deleted keeps a
//  "User Deleted" badge and leaves only when this person removes it.
//

import SwiftUI
import SwiftData

struct CommunityMealRow: View {
    let meal: CachedSharedMeal
    let isOwnerDeleted: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.teal, .blue.opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "fork.knife")
                    .font(.title2)
                    .foregroundStyle(Color.onTint)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(meal.name.isEmpty ? "Untitled meal" : meal.name)
                        .font(.headline)
                        .lineLimit(1)
                    if isOwnerDeleted { UserDeletedBadge() }
                }
                if let desc = meal.mealDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                let count = CommunityMealDetailView.courses(of: meal).count
                Text("\(count) \(count == 1 ? "course" : "courses")" + (meal.sharedByUserName.map { " • by \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct CommunityMealDetailView: View {
    let meal: CachedSharedMeal
    @Environment(\.dismiss) private var dismiss
    @Query private var cachedRecipes: [CachedSharedRecipe]
    @ObservedObject private var ownerDeleted = OwnerDeletedStore.shared

    static func courses(of meal: CachedSharedMeal) -> [MealCourse] {
        guard let data = meal.coursesData else { return [] }
        return (try? JSONDecoder().decode([MealCourse].self, from: data)) ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if ownerDeleted.isDeleted(.meal, meal.id) {
                        UserDeletedNote(kind: "meal")
                    }
                    if let desc = meal.mealDescription, !desc.isEmpty {
                        Text(desc)
                    }
                    if let by = meal.sharedByUserName {
                        Label("Shared by \(by)", systemImage: "person.crop.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Courses") {
                    ForEach(Self.courses(of: meal)) { course in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name).font(.headline)
                            Text(recipeTitle(for: course) ?? "No recipe linked")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let notes = meal.notes, !notes.isEmpty {
                    Section("Notes") { Text(notes) }
                }
            }
            .navigationTitle(meal.name.isEmpty ? "Meal" : meal.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func recipeTitle(for course: MealCourse) -> String? {
        if let id = course.recipeID, let cached = cachedRecipes.first(where: { $0.id == id }) {
            return cached.title
        }
        return course.recipeTitle
    }
}
