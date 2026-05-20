//
//  RecipeValidationView.swift
//  Reczipes2
//
//  View for validating and correcting recipe content after extraction
//

import SwiftUI

typealias MisplacedContent = RecipeValidationResult.RecipeCorrections.MisplacedContent

struct RecipeValidationView: View {
    let recipe: RecipeX
    let validationResult: RecipeValidationResult
    let onApplyCorrections: (RecipeValidationResult) -> Void
    let onSkipValidation: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingDetails = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Validation Status
                    validationStatusSection
                    
                    // Suggestions
                    if !validationResult.suggestions.isEmpty {
                        suggestionsSection
                    }
                    
                    // Corrections Preview
                    if let corrections = validationResult.corrections {
                        correctionsSection(corrections)
                    }
                    
                    // Action Buttons
                    actionButtonsSection
                }
                .padding()
            }
            .navigationTitle("Validate Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var validationStatusSection: some View {
        VStack(spacing: 12) {
            Image(systemName: validationResult.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(validationResult.isValid ? .green : .orange)
            
            Text(validationResult.isValid ? "Recipe Looks Good!" : "Improvements Suggested")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Confidence: \(Int(validationResult.confidence * 100))%")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if !validationResult.isValid {
                Text("We found some potential issues with the extracted content. Review the suggestions below.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
    
    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggestions")
                .font(.headline)
            
            ForEach(Array(validationResult.suggestions.enumerated()), id: \.offset) { index, suggestion in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "\(index + 1).circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                    
                    Text(suggestion)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func correctionsSection(_ corrections: RecipeValidationResult.RecipeCorrections) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Proposed Corrections")
                .font(.headline)
            
            // Title correction
            if let newTitle = corrections.title, newTitle != recipe.title {
                correctionItem(
                    label: "Title",
                    original: recipe.title ?? "",
                    corrected: newTitle
                )
            }
            
            // Cuisine correction
            if let newCuisine = corrections.cuisine, newCuisine != recipe.cuisine {
                correctionItem(
                    label: "Cuisine",
                    original: recipe.cuisine ?? "Not specified",
                    corrected: newCuisine
                )
            }
            
            // Yield correction
            if let newYield = corrections.recipeYield, newYield != recipe.recipeYield {
                correctionItem(
                    label: "Yield",
                    original: recipe.recipeYield ?? "",
                    corrected: newYield
                )
            }
            
            // Header notes correction
            if let newNotes = corrections.headerNotes, newNotes != recipe.headerNotes {
                correctionItem(
                    label: "Description",
                    original: recipe.headerNotes ?? "",
                    corrected: newNotes
                )
            }
            
            // Misplaced content
            if let misplaced = corrections.misplacedContent, !misplaced.isEmpty {
                misplacedContentSection(misplaced)
            }
            
            Button {
                showingDetails.toggle()
            } label: {
                HStack {
                    Text(showingDetails ? "Hide Details" : "Show Full Details")
                    Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func correctionItem(label: String, original: String, corrected: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(original.isEmpty ? "(empty)" : original)
                        .font(.caption)
                        .foregroundColor(.red)
                        .strikethrough()
                }
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Corrected:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(corrected)
                        .font(.caption)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func misplacedContentSection(_ misplaced: [MisplacedContent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Misplaced Content")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ForEach(misplaced.indices, id: \.self) { index in
                let item = misplaced[index]
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.content)
                        .font(.caption)
                        .padding(8)
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(6)
                    
                    HStack {
                        Text("From: \(item.currentLocation)")
                        Image(systemName: "arrow.right")
                        Text("To: \(item.suggestedLocation)")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    
                    Text(item.reason)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Apply corrections
            Button {
                onApplyCorrections(validationResult)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Apply Corrections")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            // Skip everything
            Button {
                onSkipValidation()
                dismiss()
            } label: {
                Text("Skip & Save As Is")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
}
