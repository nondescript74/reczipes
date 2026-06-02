//
//  MealEditorView.swift
//  Reczipes2
//
//  Create or edit a meal and its courses. Each course slot can be
//  linked to an existing recipe from the user's library, or it can
//  hold a placeholder name that the user resolves via web search.
//

import SwiftUI
import SwiftData

struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecipeX.title) private var allRecipes: [RecipeX]

    let meal: Meal?

    @State private var name: String
    @State private var description: String
    @State private var notes: String
    @State private var courses: [MealCourse]

    @State private var pickingRecipeForCourseID: UUID?
    @State private var searchingCourse: CourseSearchContext?

    init(meal: Meal? = nil) {
        self.meal = meal
        _name = State(initialValue: meal?.name ?? "")
        _description = State(initialValue: meal?.mealDescription ?? "")
        _notes = State(initialValue: meal?.notes ?? "")
        _courses = State(initialValue: meal?.courses ?? [])
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Meal Name", text: $name)
                        .textInputAutocapitalization(.words)

                    TextField("Description (Optional)",
                              text: $description,
                              axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    if courses.isEmpty {
                        Text("Add courses like Main, Side, or Salad — then link each to a recipe or search the web for ideas.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($courses) { $course in
                            CourseRow(
                                course: $course,
                                recipes: allRecipes,
                                onPickRecipe: { pickingRecipeForCourseID = course.id },
                                onSearchWeb: { openWebSearch(for: course) },
                                onClearRecipe: { clearRecipe(for: course.id) }
                            )
                        }
                        .onDelete(perform: deleteCourses)
                        .onMove(perform: moveCourses)
                    }

                    Button {
                        addCourse()
                    } label: {
                        Label("Add Course", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Courses")
                } footer: {
                    Text("Tip: tap a course to link it to a recipe in your library, or use Search Web to find ideas on Google.")
                }

                Section("Notes") {
                    TextField("Optional notes (drinks, occasion, etc.)",
                              text: $notes,
                              axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(meal == nil ? "New Meal" : "Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !courses.isEmpty {
                        EditButton()
                    }
                }
            }
            .sheet(item: Binding<CoursePickerContext?>(
                get: {
                    guard let id = pickingRecipeForCourseID else { return nil }
                    return CoursePickerContext(courseID: id)
                },
                set: { newValue in
                    pickingRecipeForCourseID = newValue?.courseID
                }
            )) { context in
                RecipePickerSheet(currentRecipeID: nil) { recipe in
                    linkRecipe(recipe, toCourseID: context.courseID)
                    pickingRecipeForCourseID = nil
                }
            }
            .sheet(item: $searchingCourse) { context in
                CourseSearchView(
                    courseName: context.courseName,
                    recipes: allRecipes,
                    onRecipeSelected: { recipe in
                        linkRecipe(recipe, toCourseID: context.courseID)
                    }
                )
            }
        }
    }

    // MARK: - Course Mutation

    private func addCourse() {
        courses.append(MealCourse(name: ""))
    }

    private func deleteCourses(at offsets: IndexSet) {
        courses.remove(atOffsets: offsets)
    }

    private func moveCourses(from source: IndexSet, to destination: Int) {
        courses.move(fromOffsets: source, toOffset: destination)
    }

    private func linkRecipe(_ recipe: RecipeX, toCourseID id: UUID) {
        guard let index = courses.firstIndex(where: { $0.id == id }) else { return }
        courses[index].recipeID = recipe.id
        courses[index].recipeTitle = recipe.title
        if courses[index].name.trimmingCharacters(in: .whitespaces).isEmpty,
           let title = recipe.title {
            courses[index].name = title
        }
    }

    private func clearRecipe(for id: UUID) {
        guard let index = courses.firstIndex(where: { $0.id == id }) else { return }
        courses[index].recipeID = nil
        courses[index].recipeTitle = nil
    }

    private func openWebSearch(for course: MealCourse) {
        let query = course.searchQuery?.isEmpty == false
            ? (course.searchQuery ?? "")
            : course.name
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchingCourse = CourseSearchContext(courseID: course.id, courseName: trimmed)
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop empty courses on save.
        let cleanCourses = courses.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
        }

        if let meal = meal {
            meal.name = trimmedName
            meal.mealDescription = trimmedDesc.isEmpty ? nil : trimmedDesc
            meal.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            meal.setCourses(cleanCourses)
        } else {
            let new = Meal(
                name: trimmedName,
                mealDescription: trimmedDesc.isEmpty ? nil : trimmedDesc,
                courses: cleanCourses,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                isPreset: false
            )
            modelContext.insert(new)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            AppLog.error("Failed to save meal: \(error)", category: .storage)
        }
    }
}

// MARK: - Course Row

private struct CourseRow: View {
    @Binding var course: MealCourse
    let recipes: [RecipeX]
    let onPickRecipe: () -> Void
    let onSearchWeb: () -> Void
    let onClearRecipe: () -> Void

    private var linkedRecipe: RecipeX? {
        guard let id = course.recipeID else { return nil }
        return recipes.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Course (e.g., Main, Side, Salad)", text: $course.name)
                .textInputAutocapitalization(.words)
                .font(.body)

            if let recipe = linkedRecipe {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundStyle(.green)
                    Text(recipe.title ?? "Untitled Recipe")
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Button(role: .destructive, action: onClearRecipe) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 8) {
                    Button {
                        onPickRecipe()
                    } label: {
                        Label("Pick Recipe", systemImage: "book")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onSearchWeb()
                    } label: {
                        Label("Search Web", systemImage: "magnifyingglass")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(course.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sheet Context

private struct CoursePickerContext: Identifiable {
    let courseID: UUID
    var id: UUID { courseID }
}

private struct CourseSearchContext: Identifiable {
    let courseID: UUID
    let courseName: String
    var id: UUID { courseID }
}

#Preview {
    MealEditorView()
        .modelContainer(for: [Meal.self, RecipeX.self], inMemory: true)
}
