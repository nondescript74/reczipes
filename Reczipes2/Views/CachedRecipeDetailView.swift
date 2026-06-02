//
//  CachedRecipeDetailView.swift
//  Reczipes2
//
//  Created on 1/31/26.
//

import SwiftUI
import SwiftData

/// Detail view for cached shared recipes from the community
/// Shows recipe details with import option
struct CachedRecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let cachedRecipe: CachedSharedRecipe
    
    @State private var showingImportConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with community badge
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cachedRecipe.title)
                                .font(.title)
                                .fontWeight(.bold)
                            
                            if let sharedBy = cachedRecipe.sharedByUserName {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                    Text("Shared by \(sharedBy)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Import button
                        Button {
                            showingImportConfirmation = true
                        } label: {
                            Label("Add to My Recipes", systemImage: "plus.square.on.square")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    
                    if let headerNotes = cachedRecipe.headerNotes {
                        Text(headerNotes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                
                // Image (if available)
                if let imageName = cachedRecipe.imageName {
                    GeometryReader { geometry in
                        RecipeImageView(
                            imageName: imageName,
                            imageData: nil,
                            size: CGSize(width: geometry.size.width - 32, height: 250),
                            cornerRadius: 12
                        )
                        .padding(.horizontal)
                    }
                    .frame(height: 250)
                }
                
                // Yield
                if let yield = cachedRecipe.yield {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Yield")
                            .font(.headline)
                        Text(yield)
                            .font(.body)
                    }
                    .padding(.horizontal)
                }
                
                // Ingredients
                if !cachedRecipe.ingredientSections.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ingredients")
                            .font(.headline)
                        
                        ForEach(cachedRecipe.ingredientSections, id: \.id) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                if let sectionTitle = section.title {
                                    Text(sectionTitle)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                
                                ForEach(section.ingredients, id: \.id) { ingredient in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                            .font(.caption)
                                        Text(formatIngredient(ingredient))
                                            .font(.body)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Instructions
                if !cachedRecipe.instructionSections.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Instructions")
                            .font(.headline)
                        
                        ForEach(cachedRecipe.instructionSections, id: \.id) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                if let sectionTitle = section.title {
                                    Text(sectionTitle)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                
                                ForEach(Array(section.steps.enumerated()), id: \.element.id) { index, step in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(index + 1).")
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                        
                                        Text(step.text)
                                            .font(.body)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Notes
                if !cachedRecipe.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        
                        ForEach(cachedRecipe.notes, id: \.id) { note in
                            Text(note.text)
                                .font(.body)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Reference/Source
                if let reference = cachedRecipe.reference, let url = URL(string: reference) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source")
                            .font(.headline)
                        
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "link")
                                Text("View Original")
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.body)
                            .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Community info
                VStack(alignment: .leading, spacing: 8) {
                    Text("About This Recipe")
                        .font(.headline)
                    
                    Text("This is a community recipe shared on \(cachedRecipe.sharedDate.formatted(date: .abbreviated, time: .omitted)). Add it to your collection to save it permanently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Add to My Recipes?", isPresented: $showingImportConfirmation) {
            Button("Add to My Recipes") {
                importRecipe()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will create a permanent copy of this recipe in your collection.")
        }
    }
    
    private func importRecipe() {
        do {
            try CloudKitSharingService.shared.importCachedRecipe(cachedRecipe, modelContext: modelContext)
            AppLog.info("Imported cached recipe: \(cachedRecipe.title)", category: .sharing)
        } catch {
            AppLog.error("Failed to import cached recipe: \(error)", category: .sharing)
        }
    }
    
    private func formatIngredient(_ ingredient: Ingredient) -> String {
        var parts: [String] = []
        
        if let quantity = ingredient.quantity, !quantity.isEmpty {
            parts.append(quantity)
        }
        
        if let unit = ingredient.unit, !unit.isEmpty {
            parts.append(unit)
        }
        
        parts.append(ingredient.name)
        
        if let preparation = ingredient.preparation, !preparation.isEmpty {
            parts.append("(\(preparation))")
        }
        
        return parts.joined(separator: " ")
    }
}
