//
//  MealsView.swift
//  Reczipes2
//
//  Top-level tab that lists meals — a meal groups together several
//  recipes that go on the table together (e.g., spaghetti + garlic
//  bread + green salad). Seeds a built-in preset list on first launch.
//

import SwiftUI
import SwiftData

struct MealsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meal.dateModified, order: .reverse) private var meals: [Meal]
    @Query private var recipes: [RecipeX]

    @State private var showingEditor = false
    @State private var editingMeal: Meal?
    @State private var selectedMeal: Meal?
    @State private var searchText = ""

    private var filteredMeals: [Meal] {
        guard !searchText.isEmpty else { return meals }
        return meals.filter { meal in
            (meal.name ?? "").localizedCaseInsensitiveContains(searchText) ||
            (meal.mealDescription ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredMeals.isEmpty {
                    emptyState
                } else {
                    mealList
                }
            }
            .navigationTitle("Meals")
            .searchable(text: $searchText, prompt: "Search meals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingMeal = nil
                        showingEditor = true
                    } label: {
                        Label("New Meal", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                MealEditorView(meal: editingMeal)
            }
            .sheet(item: $selectedMeal) { meal in
                MealDetailView(meal: meal)
            }
            .onAppear {
                MealPresets.seedIfNeeded(in: modelContext)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack {
            Spacer()
            ContentUnavailableView {
                Label(searchText.isEmpty ? "No Meals Yet" : "No Matching Meals",
                      systemImage: "fork.knife.circle")
            } description: {
                Text(searchText.isEmpty
                     ? "Create a meal to plan multiple recipes together — like a main, a side, and a salad."
                     : "Try a different search term.")
            } actions: {
                if searchText.isEmpty {
                    Button {
                        editingMeal = nil
                        showingEditor = true
                    } label: {
                        Label("Create Meal", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Spacer()
        }
    }

    // MARK: - List

    private var mealList: some View {
        List {
            ForEach(filteredMeals) { meal in
                Button {
                    selectedMeal = meal
                } label: {
                    MealRow(meal: meal, recipes: recipes)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        delete(meal)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        editingMeal = meal
                        showingEditor = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func delete(_ meal: Meal) {
        withAnimation {
            modelContext.delete(meal)
            try? modelContext.save()
        }
    }
}

// MARK: - Meal Row

private struct MealRow: View {
    let meal: Meal
    let recipes: [RecipeX]

    private var linkedCount: Int {
        meal.courses.filter { $0.recipeID != nil }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [.orange, .red.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: "fork.knife")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(meal.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if meal.isPreset == true {
                        Text("Preset")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }

                if let desc = meal.mealDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text("\(meal.courseCount) \(meal.courseCount == 1 ? "course" : "courses") • \(linkedCount) linked")
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

#Preview {
    MealsView()
        .modelContainer(for: [Meal.self, RecipeX.self], inMemory: true)
}
