//
//  SharedRecipesBrowserView.swift
//  Reczipes2
//
//  Created on 1/15/26.
//

import SwiftUI
import SwiftData

struct SharedRecipesBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sharingService = CloudKitSharingService.shared
    
    @State private var sharedRecipes: [CloudKitRecipe] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedRecipe: CloudKitRecipe?
    @State private var showingImportConfirmation = false
    @State private var searchText = ""
    @State private var currentSharingError: SharingError?
    @State private var showingOnboarding = false
    
    var filteredRecipes: [CloudKitRecipe] {
        if searchText.isEmpty {
            return sharedRecipes
        } else {
            return sharedRecipes.filter { recipe in
                recipe.title.localizedCaseInsensitiveContains(searchText) ||
                recipe.sharedByUserName?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
    }
    
    var body: some View {
        ZStack {
            Group {
                if isLoading && sharedRecipes.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading community recipes...")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = errorMessage, currentSharingError == nil {
                    errorView(error)
                } else if sharedRecipes.isEmpty {
                    emptyStateView
                } else {
                    recipeListView
                        .disabled(isLoading)
                }
            }
            
            // Overlay for refresh operations
            if isLoading && !sharedRecipes.isEmpty {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Refreshing...")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
                .shadow(radius: 20)
            }
        }
        .navigationTitle("Community Recipes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isLoading {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await loadSharedRecipes()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if !sharedRecipes.isEmpty {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(.blue)
                    Text("\(filteredRecipes.count) \(filteredRecipes.count == 1 ? "Recipe" : "Recipes")")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if searchText.isEmpty && filteredRecipes.count != sharedRecipes.count {
                        Text("(\(sharedRecipes.count) total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !searchText.isEmpty {
                        Text("of \(sharedRecipes.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
        .searchable(text: $searchText, prompt: "Search recipes or authors")
        .sheet(item: $selectedRecipe) { recipe in
            SharedRecipeDetailView(recipe: recipe) { recipeToImport in
                Task {
                    await importRecipe(recipeToImport)
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil && currentSharingError == nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .alert("Sharing Failed", isPresented: Binding(
            get: { currentSharingError != nil },
            set: { if !$0 { currentSharingError = nil } }
        )) {
            if let error = currentSharingError, error.canOpenOnboarding {
                Button("Open Setup & Diagnostics") {
                    showingOnboarding = true
                    currentSharingError = nil
                }
            }
            Button("OK", role: .cancel) {
                currentSharingError = nil
            }
        } message: {
            if let error = currentSharingError {
                Text(error.errorDescription ?? "An unknown error occurred.")
            }
        }
        .sheet(isPresented: $showingOnboarding) {
            CloudKitOnboardingView()
        }
        .task {
            await loadSharedRecipes()
        }
    }
    
    // MARK: - Subviews
    
    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Failed to Load", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task {
                    await loadSharedRecipes()
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Shared Recipes", systemImage: "tray.fill")
        } description: {
            Text("Be the first to share a recipe with the community!")
        } actions: {
            NavigationLink("Share Your Recipes") {
                SharingSettingsView()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var recipeListView: some View {
        List(filteredRecipes) { recipe in
            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.title)
                    .font(.headline)
                
                HStack {
                    if let userName = recipe.sharedByUserName {
                        Label(userName, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(recipe.sharedDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let notes = recipe.headerNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedRecipe = recipe
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadSharedRecipes() async {
        isLoading = true
        errorMessage = nil
        currentSharingError = nil
        
        do {
            // Communal library: fetch every shared recipe from all users (incl. self), no cap.
            let recipes = try await sharingService.fetchSharedRecipes(limit: Int.max, excludeCurrentUser: false)
            await MainActor.run {
                self.sharedRecipes = recipes
                self.isLoading = false
            }
        } catch let error as SharingError {
            await MainActor.run {
                self.currentSharingError = error
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func importRecipe(_ recipe: CloudKitRecipe) async {
        do {
            try await sharingService.importSharedRecipe(recipe, modelContext: modelContext)
            // Show success message
        } catch {
            errorMessage = "Failed to import: \(error.localizedDescription)"
        }
    }
}

// MARK: - Shared Recipe Detail View

struct SharedRecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: CloudKitRecipe
    let onImport: (CloudKitRecipe) -> Void
    
    @State private var showingImportConfirmation = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recipe.title)
                            .font(.title)
                            .bold()
                        
                        HStack {
                            if let userName = recipe.sharedByUserName {
                                Label(userName, systemImage: "person.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(recipe.sharedDate, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let notes = recipe.headerNotes {
                            Text(notes)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let yield = recipe.yield {
                            Label(yield, systemImage: "person.2.fill")
                                .font(.subheadline)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    // Ingredients
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ingredients")
                            .font(.title2)
                            .bold()
                        
                        ForEach(recipe.ingredientSections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                if let title = section.title {
                                    Text(title)
                                        .font(.headline)
                                }
                                
                                ForEach(section.ingredients) { ingredient in
                                    HStack(alignment: .top) {
                                        Text("•")
                                        Text(ingredientText(ingredient))
                                    }
                                    .font(.body)
                                }
                                
                                if let transition = section.transitionNote {
                                    Text(transition)
                                        .font(.caption)
                                        .italic()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Instructions")
                            .font(.title2)
                            .bold()
                        
                        ForEach(recipe.instructionSections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                if let title = section.title {
                                    Text(title)
                                        .font(.headline)
                                }
                                
                                ForEach(section.steps) { step in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(step.stepNumber).")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.blue)
                                        
                                        Text(step.text)
                                    }
                                    .font(.body)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    // Notes
                    if !recipe.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Notes")
                                .font(.title2)
                                .bold()
                            
                            ForEach(recipe.notes) { note in
                                HStack(alignment: .top) {
                                    Image(systemName: iconForNoteType(note.type))
                                        .foregroundStyle(colorForNoteType(note.type))
                                    
                                    Text(note.text)
                                        .font(.body)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    
                    // Reference
                    if let reference = recipe.reference, !reference.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reference")
                                .font(.headline)
                            
                            Text(reference)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Recipe Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImportConfirmation = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .alert("Import Recipe", isPresented: $showingImportConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Import") {
                    onImport(recipe)
                    dismiss()
                }
            } message: {
                Text("Add this recipe to your collection?")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func ingredientText(_ ingredient: Ingredient) -> String {
        var parts: [String] = []
        
        if let quantity = ingredient.quantity {
            parts.append(quantity)
        }
        
        if let unit = ingredient.unit {
            parts.append(unit)
        }
        
        parts.append(ingredient.name)
        
        if let prep = ingredient.preparation {
            parts.append("(\(prep))")
        }
        
        return parts.joined(separator: " ")
    }
    
    private func iconForNoteType(_ type: RecipeNoteType) -> String {
        switch type {
        case .tip: return "lightbulb.fill"
        case .substitution: return "arrow.triangle.swap"
        case .warning: return "exclamationmark.triangle.fill"
        case .timing: return "clock.fill"
        case .general: return "note.text"
        }
    }
    
    private func colorForNoteType(_ type: RecipeNoteType) -> Color {
        switch type {
        case .tip: return .blue
        case .substitution: return .green
        case .warning: return .red
        case .timing: return .orange
        case .general: return .gray
        }
    }
}

#Preview {
    NavigationStack {
        SharedRecipesBrowserView()
            .modelContainer(for: [RecipeX.self])
    }
}
