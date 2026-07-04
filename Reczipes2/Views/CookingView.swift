//
//  CookingView.swift
//  reczipes2-imageextract
//
//  Adaptive dual-recipe cooking interface
//

import SwiftUI
import SwiftData

struct CookingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.modelContext) private var modelContext
    
    @State private var viewModel: CookingViewModel?
    @State private var keepAwakeManager = KeepAwakeManager.shared
    
    private var isWideLayout: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    if isWideLayout {
                        wideLayoutView(viewModel: viewModel)
                    } else {
                        compactLayoutView(viewModel: viewModel)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Cooking")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel != nil {
                        HelpButton(topicKey: "cookingMode")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if let viewModel = viewModel {
                        keepAwakeToggle(viewModel: viewModel)
                    }
                }
            }
        }
        .task {
            if viewModel == nil {
                let vm = CookingViewModel(modelContext: modelContext)
                viewModel = vm
                vm.loadSession()
            }
        }
        .onDisappear {
            viewModel?.cleanup()
        }
    }
    
    // MARK: - Wide Layout (iPad/Mac)
    
    @ViewBuilder
    private func wideLayoutView(viewModel: CookingViewModel) -> some View {
        HStack(spacing: 0) {
            RecipePanel(
                recipe: viewModel.selectedRecipes[0],
                slot: 0,
                viewModel: viewModel
            )
            
            Divider()
            
            RecipePanel(
                recipe: viewModel.selectedRecipes[1],
                slot: 1,
                viewModel: viewModel
            )
        }
    }
    
    // MARK: - Compact Layout (iPhone)
    
    @ViewBuilder
    private func compactLayoutView(viewModel: CookingViewModel) -> some View {
        TabView(selection: Binding(
            get: { viewModel.currentRecipeIndex },
            set: { viewModel.currentRecipeIndex = $0 }
        )) {
            RecipePanel(
                recipe: viewModel.selectedRecipes[0],
                slot: 0,
                viewModel: viewModel
            )
            .tag(0)
            
            RecipePanel(
                recipe: viewModel.selectedRecipes[1],
                slot: 1,
                viewModel: viewModel
            )
            .tag(1)
        }
        .platformPageTabViewStyle(indexDisplayMode: .always)
        .platformPageIndexViewStyle(backgroundDisplayMode: .always)
    }
    
    // MARK: - Keep Awake Toggle
    
    @ViewBuilder
    private func keepAwakeToggle(viewModel: CookingViewModel) -> some View {
        Toggle(isOn: Binding(
            get: { keepAwakeManager.isKeepAwakeEnabled },
            set: { newValue in
                if newValue {
                    keepAwakeManager.enable()
                } else {
                    keepAwakeManager.disable()
                }
                viewModel.saveSession()
            }
        )) {
            Label(
                "Keep Awake",
                systemImage: keepAwakeManager.isKeepAwakeEnabled ? "eye" : "eye.slash"
            )
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
    }
}

#Preview {
    CookingView()
        .modelContainer(for: [RecipeX.self, Book.self, CookingSession.self, VersionHistoryRecord.self], inMemory: true)
}
