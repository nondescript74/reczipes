//
//  RecipeComparisonView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/20/26.
//

import SwiftUI
import SwiftData

struct RecipeComparisonView: View {
    let existingRecipe: RecipeX
    let newRecipe: RecipeX
    let canReplaceExisting: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    var onKeepExisting: () -> Void
    var onKeepBoth: () -> Void
    var onKeepNew: () -> Void
    
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Comparison Mode", selection: $selectedTab) {
                    Text("Side by Side").tag(0)
                    Text("Existing").tag(1)
                    Text("New").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                if selectedTab == 0 {
                    sideBySideView
                } else if selectedTab == 1 {
                    existingRecipeView
                } else {
                    newRecipeView
                }
                
                Divider()
                
                // Action buttons
                actionButtons
            }
            .navigationTitle("Compare Recipes")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Side by Side View
    
    private var sideBySideView: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                // Existing Recipe Column
                VStack(alignment: .leading, spacing: 12) {
                    Text("Existing")
                        .font(.headline)
                        .foregroundStyle(Color.appInfo)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    recipeCard_a(for: existingRecipe)
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                
                // New Recipe Column
                VStack(alignment: .leading, spacing: 12) {
                    Text("New")
                        .font(.headline)
                        .foregroundStyle(Color.appSuccess)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    recipeCard_a(for: newRecipe)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }
    
    // MARK: - Individual Views
    
    private var existingRecipeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Existing Recipe")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                recipeCard_a(for: existingRecipe)
            }
            .padding()
        }
    }
    
    private var newRecipeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Recipe")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                recipeCard_a(for: newRecipe)
            }
            .padding()
        }
    }
    
    // MARK: - Recipe Cards
    
    private func recipeCard_a(for recipe: RecipeX) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(recipe.title ?? "No title")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            // Date Created
            if let date = recipe.dateCreated {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Date Added")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                }
            }
            
            // Header Notes
            if let headerNotes = recipe.headerNotes, !headerNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Header Notes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(headerNotes)
                        .font(.subheadline)
                }
            }
            
            // Yield
            if let recipeYield = recipe.recipeYield, !recipeYield.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Yield")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(recipeYield)
                        .font(.subheadline)
                }
            }
            
            // Ingredients
            VStack(alignment: .leading, spacing: 4) {
                Text("Ingredients")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(recipe.ingredients.count) ingredient(s)")
                    .font(.subheadline)
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 4) {
                Text("Instructions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(recipe.instructions.count) step(s)")
                    .font(.subheadline)
            }
            
            // Reference
            if let reference = recipe.reference, !reference.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reference")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(reference)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color.appSecondaryBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Keep Existing
            Button {
                onKeepExisting()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Keep Existing Only")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AdaptiveToneSolidFill(tone: .info))
                .foregroundStyle(Color.onTint)
                .cornerRadius(12)
            }
            
            // Keep Both
            Button {
                onKeepBoth()
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc.fill")
                    Text("Keep Both")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundStyle(Color.onTint)
                .cornerRadius(12)
            }
            
            // Keep New (Replace)
            Button {
                onKeepNew()
            } label: {
                HStack {
                    Image(systemName: canReplaceExisting ? "arrow.triangle.2.circlepath" : "lock.fill")
                    Text(canReplaceExisting ? "Replace with New" : "Replace Unavailable")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canReplaceExisting ? Color.orange : Color.gray)
                .foregroundStyle(Color.onTint)
                .cornerRadius(12)
            }
            .disabled(!canReplaceExisting)
        }
        .padding()
    }
}

