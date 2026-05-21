//
//  MealImportView.swift
//  Reczipes2
//
//  Settings entry point for importing meal plans. Offers two paths:
//  - Import the meals bundled with the app (from the Reminders
//    "Meal Plans" list).
//  - Import meals from a user-supplied JSON file.
//
//  Imported meals are matched against existing recipes by title; any
//  meals whose names already exist in the user's library are skipped.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MealImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var meals: [Meal]
    @Query private var recipes: [RecipeX]

    @State private var isImporting = false
    @State private var showFilePicker = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var bundledPreview: MealImportPackage?

    var body: some View {
        List {
            currentStatusSection
            bundledImportSection
            fileImportSection
            howItWorksSection
        }
        .onAppear {
            if bundledPreview == nil {
                bundledPreview = try? MealImportManager.loadBundledPackage()
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handlePickedFile(result)
        }
        .alert("Import Complete", isPresented: .constant(resultMessage != nil)) {
            Button("OK") { resultMessage = nil }
        } message: {
            if let resultMessage {
                Text(resultMessage)
            }
        }
        .alert("Import Failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Sections

    private var currentStatusSection: some View {
        Section("Current Library") {
            HStack {
                Image(systemName: "fork.knife")
                    .foregroundStyle(.orange)
                Text("Meals")
                Spacer()
                Text("\(meals.count)").bold()
            }
            HStack {
                Image(systemName: "book.closed")
                    .foregroundStyle(.blue)
                Text("Recipes")
                Spacer()
                Text("\(recipes.count)").bold()
            }
        }
    }

    private var bundledImportSection: some View {
        Section {
            if let bundledPreview {
                HStack {
                    Image(systemName: "tray.full")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bundledPreview.source ?? "Bundled Meal Plans")
                            .font(.body)
                        Text("\(bundledPreview.meals.count) meals available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                Task { await importBundled() }
            } label: {
                if isImporting {
                    HStack {
                        ProgressView()
                        Text("Importing...")
                    }
                } else {
                    Label("Import Bundled Meal Plans", systemImage: "square.and.arrow.down.on.square")
                }
            }
            .disabled(isImporting || bundledPreview == nil)
        } header: {
            Text("Quick Import")
        } footer: {
            Text("Imports the meal-plan list that ships with the app. Meals whose names already exist in your library are skipped.")
        }
    }

    private var fileImportSection: some View {
        Section {
            Button {
                showFilePicker = true
            } label: {
                Label("Import from JSON File", systemImage: "doc.text")
            }
            .disabled(isImporting)
        } header: {
            Text("Import From File")
        } footer: {
            Text("Pick a meal-plan JSON file from Files or iCloud Drive. Use the bundled file as a template for the expected format.")
        }
    }

    private var howItWorksSection: some View {
        Section("How It Works") {
            InfoRow(
                icon: "magnifyingglass",
                title: "Recipe matching",
                description: "Each course name is matched against your existing recipes by title (case-insensitive). Matches are linked automatically."
            )
            InfoRow(
                icon: "circle.dashed",
                title: "Unmatched courses",
                description: "Courses without a recipe match become placeholders. You can link them later via Edit, or tap Search Web to find ideas."
            )
            InfoRow(
                icon: "arrow.up.doc.on.clipboard",
                title: "Duplicate protection",
                description: "Meals whose names already exist in your library (case-insensitive) are skipped."
            )
        }
    }

    private struct InfoRow: View {
        let icon: String
        let title: String
        let description: String

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).bold()
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func importBundled() async {
        isImporting = true
        defer { isImporting = false }

        do {
            let package = try MealImportManager.loadBundledPackage()
            let result = try MealImportManager.importPackage(
                package,
                into: modelContext,
                existingMeals: meals,
                existingRecipes: recipes
            )
            resultMessage = result.summary
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handlePickedFile(_ result: Result<[URL], Error>) {
        Task {
            isImporting = true
            defer { isImporting = false }

            do {
                let urls = try result.get()
                guard let url = urls.first else { return }

                guard url.startAccessingSecurityScopedResource() else {
                    errorMessage = "Cannot access selected file."
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let package = try MealImportManager.loadPackage(from: url)
                let importResult = try MealImportManager.importPackage(
                    package,
                    into: modelContext,
                    existingMeals: meals,
                    existingRecipes: recipes
                )
                resultMessage = importResult.summary
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        MealImportView()
            .modelContainer(for: [Meal.self, RecipeX.self], inMemory: true)
    }
}
