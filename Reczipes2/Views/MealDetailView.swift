//
//  MealDetailView.swift
//  Reczipes2
//
//  Read-only detail view for a meal. Lists the courses; tapping a
//  linked course navigates into the underlying recipe detail.
//

import SwiftUI
import SwiftData

struct MealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [RecipeX]

    let meal: Meal

    @State private var showingEditor = false
    @State private var selectedRecipe: RecipeX?
    @State private var searchURL: URL?
    @State private var showSafari = false

    private var courses: [MealCourse] { meal.courses }

    var body: some View {
        NavigationStack {
            List {
                if let desc = meal.mealDescription, !desc.isEmpty {
                    Section("About") {
                        Text(desc)
                            .font(.body)
                    }
                }

                Section("Courses") {
                    if courses.isEmpty {
                        Text("No courses yet. Tap Edit to add some.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(courses) { course in
                            courseRow(course)
                        }
                    }
                }

                if let notes = meal.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                            .font(.body)
                    }
                }
            }
            .navigationTitle(meal.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showingEditor = true }
                }
            }
            .sheet(isPresented: $showingEditor) {
                MealEditorView(meal: meal)
            }
            .sheet(item: $selectedRecipe) { recipe in
                NavigationStack {
                    RecipeDetailView(recipe: recipe)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { selectedRecipe = nil }
                            }
                        }
                }
            }
            .sheet(isPresented: $showSafari) {
                if let url = searchURL {
                    SafariView(url: url, entersReaderIfAvailable: false)
                        .ignoresSafeArea()
                }
            }
        }
    }

    @ViewBuilder
    private func courseRow(_ course: MealCourse) -> some View {
        if let recipe = linkedRecipe(for: course) {
            Button {
                selectedRecipe = recipe
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "fork.knife.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(recipe.title ?? "Untitled Recipe")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(.headline)
                    Text("Not yet linked to a recipe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    openWebSearch(for: course.name)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func linkedRecipe(for course: MealCourse) -> RecipeX? {
        guard let id = course.recipeID else { return nil }
        return recipes.first { $0.id == id }
    }

    private func openWebSearch(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = "\(trimmed) recipe".addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
              ),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else {
            return
        }
        searchURL = url
        showSafari = true
    }
}

#Preview {
    MealDetailView(meal: Meal(
        name: "Italian Dinner",
        mealDescription: "A classic Italian meal",
        courses: [
            MealCourse(name: "Spaghetti"),
            MealCourse(name: "Garlic Bread"),
            MealCourse(name: "Green Salad")
        ]
    ))
    .modelContainer(for: [Meal.self, RecipeX.self], inMemory: true)
}
