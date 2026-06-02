//
//  SharedRecipeViewerView.swift
//  Reczipes2
//
//  Created on 1/25/26.
//

import SwiftUI
import SwiftData

/// Downloads and displays a full shared recipe on-demand
/// Shows loading state while fetching, then displays read-only recipe detail view
struct SharedRecipeViewerView: View {
    let preview: CloudKitRecipePreview
    
    @StateObject private var viewService = SharedRecipeViewService.shared
    @State private var fullRecipe: CloudKitRecipe?
    @State private var isLoading = false
    @State private var error: Error?
    
    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let recipe = fullRecipe {
                ReadOnlyRecipeDetailView(recipe: recipe, preview: preview)
            } else if let error = error {
                errorView(error)
            }
        }
        .navigationTitle(preview.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadFullRecipe()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading recipe...")
                .font(.headline)
            
            Text(preview.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            
            Text("Unable to Load Recipe")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(error.localizedDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                Task {
                    await loadFullRecipe()
                }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    // MARK: - Loading Logic
    
    private func loadFullRecipe() async {
        isLoading = true
        error = nil
        
        do {
            let recipe = try await viewService.fetchRecipeForViewing(preview: preview)
            fullRecipe = recipe
            AppLog.info("✅ Loaded full recipe: '\(recipe.title)'", category: .sharing)
        } catch {
            self.error = error
            AppLog.error("❌ Failed to load recipe: \(error)", category: .sharing)
        }
        
        isLoading = false
    }
}

// MARK: - Preview

#Preview("Loading State") {
    let preview = CloudKitRecipePreview(
        id: UUID(),
        title: "Pasta Carbonara",
        headerNotes: "Classic Italian pasta dish",
        imageName: nil,
        imageData: nil,
        sharedByUserID: "test-user",
        sharedByUserName: "Maria Rossi",
        recipeYield: "4 servings",
        bookID: UUID(),
        cloudRecordID: nil
    )
    
    return NavigationStack {
        SharedRecipeViewerView(preview: preview)
    }
}
