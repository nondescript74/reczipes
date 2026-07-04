//
//  DuplicateResolutionView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/20/26.
//


import SwiftUI
import SwiftData

struct DuplicateResolutionView: View {
    let existingRecipe: RecipeX
    let newRecipe: RecipeX
    let duplicateMatch: DuplicateMatch
    
    @Environment(\.dismiss) private var dismiss
    

    var onReplaceOriginal: () -> Void
    var onKeepOriginal: () -> Void
    
    @State private var showingComparison = false
    
    var isShared: Bool {
        // Check if recipe has CloudKit share record
        // For now, we'll be conservative and assume recipes could be shared
        // TODO: Implement proper CloudKit share tracking in Recipe model
        false
    }
    
    var isInRecipeBook: Bool {
        // Check if recipe belongs to any recipe books
        // TODO: Implement relationship check when RecipeBook relationship is available
        false
    }
    
    var recipeBookNames: [String] {
        // TODO: Implement when RecipeBook relationship is available
        []
    }
    
    var canReplace: Bool {
        !isShared && !isInRecipeBook
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Match Details
                    matchDetailsSection
                    
                    // Existing Recipe Info
                    existingRecipeSection
                    
                    // Warning if shared/in cookbook
                    if !canReplace {
                        warningSection
                    }
                    
                    Divider()
                    
                    // Action Options
                    actionOptionsSection
                }
                .padding()
            }
            .navigationTitle("Duplicate Detected")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingComparison) {
                RecipeComparisonView(
                    existingRecipe: existingRecipe,
                    newRecipe: newRecipe,
                    canReplaceExisting: canReplace,
                    onKeepExisting: {
                        showingComparison = false
                        onKeepOriginal()
                        dismiss()
                    }, onKeepBoth: {
                        showingComparison = false
                        onKeepOriginal()
                        dismiss()
                    },
                    onKeepNew: {
                        showingComparison = false
                        if canReplace {
                            onReplaceOriginal()
                        }
                        dismiss()
                    }
                )
            }
        }
    }
    
    private var matchDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Match Details", systemImage: "chart.bar.fill")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                matchDetail("Overall Confidence", value: duplicateMatch.confidence)
                
                ForEach(duplicateMatch.reasons, id: \.self) { reason in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                            .font(.caption)
                        Text(reason)
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(Color.appSecondaryBackground)
        .cornerRadius(12)
    }
    
    private func matchDetail(_ label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text("\(Int(value * 100))%")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
    
    private var existingRecipeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Existing Recipe", systemImage: "book.fill")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(existingRecipe.title ?? "No title")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                if let date = existingRecipe.dateCreated {
                    HStack {
                        Image(systemName: "calendar")
                        Text("Added: \(date.formatted(date: .abbreviated, time: .omitted))")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                if isInRecipeBook {
                    HStack {
                        Image(systemName: "books.vertical.fill")
                        Text("In \(recipeBookNames.count) recipe book\(recipeBookNames.count == 1 ? "" : "s")")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.appInfo)
                }
                
                if isShared {
                    HStack {
                        Image(systemName: "person.2.fill")
                        Text("Shared with others")
                    }
                    .font(.caption)
                    .foregroundColor(.purple)
                }
            }
        }
        .padding()
        .background(Color.appSecondaryBackground)
        .cornerRadius(12)
    }
    
    private var warningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(isShared ? "Cannot Replace Shared Recipe" : "Cannot Replace Recipe in Recipe Book")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.appWarning)
            }
            .font(.headline)
            
            Text(warningMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .adaptiveToneBackground(.warning, baseOpacity: 0.1)
        .cornerRadius(12)
    }
    
    private var warningMessage: String {
        if isShared && isInRecipeBook {
            return "This recipe is shared with others AND part of \(recipeBookNames.count) recipe book(s). Replacing it would affect all users and recipe books."
        } else if isShared {
            return "This recipe is currently shared with others. Replacing it would affect all users who have access."
        } else {
            let names = recipeBookNames.prefix(3).joined(separator: ", ")
            let more = recipeBookNames.count > 3 ? " and \(recipeBookNames.count - 3) more" : ""
            return "This recipe is part of: \(names)\(more). Replacing it would affect these recipe books."
        }
    }
    
    private var actionOptionsSection: some View {
        VStack(spacing: 16) {
            Text("What would you like to do?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Option 1: Keep Both
            actionButton(
                title: "Keep Both Recipes",
                subtitle: "New will be saved as \"\(String(describing: newRecipe.title)) (2)\"",
                icon: "doc.on.doc.fill",
                color: .green
            ) {
                onKeepOriginal()
                dismiss()
            }
            
            // Option 2: Replace (if allowed)
            actionButton(
                title: "Replace Original",
                subtitle: canReplace ? "Update existing recipe with new extraction" : "Not available for shared/recipe book recipes",
                icon: "arrow.triangle.2.circlepath",
                color: .blue,
                disabled: !canReplace
            ) {
                onReplaceOriginal()
                dismiss()
            }
            
            // Option 3: Keep Original
            actionButton(
                title: "Keep Original Only",
                subtitle: "Discard new extraction",
                icon: "xmark.circle.fill",
                color: .red
            ) {
                onKeepOriginal()
                dismiss()
            }
            
            Divider()
            
            // Comparison button
            Button {
                showingComparison = true
            } label: {
                Label("Compare Side-by-Side", systemImage: "square.split.2x1")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.appSystemBackground)
                    .foregroundColor(.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 2)
                    )
            }
            .buttonStyle(.plain)
        }
    }
    
    private func actionButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(disabled ? .gray : color)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(disabled ? .gray : .primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if disabled {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .background(disabled ? Color.appGray5 : Color.appSecondaryBackground)
            .cornerRadius(12)
        }
        .disabled(disabled)
        .buttonStyle(.plain)
    }
}
