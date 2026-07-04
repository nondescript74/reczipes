//
//  ContentView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/4/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecipeX.dateAdded, order: .reverse) private var savedRecipes: [RecipeX]
    @Query(sort: \CachedSharedRecipe.cachedDate, order: .reverse) private var cachedSharedRecipes: [CachedSharedRecipe]
    @Query private var allergenProfiles: [UserAllergenProfile]
    @Query(sort: \Book.dateModified, order: .reverse) private var books: [Book]
    @Query private var imageAssignments: [RecipeImageAssignment]
    
    @EnvironmentObject private var appState: AppStateManager
    
    @State private var selectedRecipe: (any RecipeDisplayProtocol)?
    @State private var selectedRecipeID: UUID?
    @State private var showingDebug = false
    @State private var showingRecipeExtractor = false
    @State private var showingCreateRecipe = false
    @State private var showingAllergenProfiles = false
    @State private var showingImport = false
    @State private var showingSearch = false
    @State private var filterMode: RecipeFilterMode = .none
    @State private var showOnlySafe = false
    @State private var isProcessingFilter = false
    @State private var triggerRepairForRecipe: RecipeX?  // triggers auto-repair in detail view
    @State private var cachedAllRecipes: [any RecipeDisplayProtocol] = [] // Cache for all recipes (both types)
    @State private var cachedFilteredRecipes: [any RecipeDisplayProtocol] = []
    @State private var cachedAllergenScores: [UUID: RecipeAllergenScore] = [:]
    @State private var cachedDiabetesScores: [UUID: DiabetesScore] = [:]
    @State private var cachedCombinedScores: [UUID: CombinedRecipeScore] = [:]
    @State private var cachedNutritionalScores: [UUID: NutritionalScore] = [:]
    
    // Content filter for showing mine/shared (default to mine)
    @State private var contentFilter: ContentFilterMode = .mine
    @Query private var sharedRecipes: [SharedRecipe]
    
    // Auto-sync tracking for shared recipes
    @State private var lastCommunitySync: Date?
    @State private var isSyncingCommunityRecipes = false
    @State private var syncProgress: String = ""
    private let syncInterval: TimeInterval = 300 // 5 minutes
    
    // Active allergen profile
    private var activeProfile: UserAllergenProfile? {
        allergenProfiles.first { $0.isActive == true }
    }
    
    // Combined scores for recipes (now cached)
    private var combinedScores: [UUID: CombinedRecipeScore] {
        cachedCombinedScores
    }
    
    // All available recipes - now returns cached version
    // This combines owned recipes (RecipeX) and shared recipes (CachedSharedRecipe)
    private var availableRecipesBeforeFilter: [any RecipeDisplayProtocol] {
        cachedAllRecipes
    }
    
    // Filtered recipes based on filter settings (now uses cached results)
    private var availableRecipes: [any RecipeDisplayProtocol] {
        let baseRecipes = filterMode != .none ? cachedFilteredRecipes : cachedAllRecipes
        
        // Apply content filter (mine/shared)
        return applyContentFilter(to: baseRecipes)
    }
    
    /// Applies the content filter (mine/shared) to recipes
    private func applyContentFilter(to recipes: [any RecipeDisplayProtocol]) -> [any RecipeDisplayProtocol] {
        switch contentFilter {
        case .mine:
            // Show only owned recipes (RecipeX)
            return recipes.filter { !$0.isSharedRecipe }
            
        case .shared:
            // Show only cached shared recipes (CachedSharedRecipe)
            return recipes.filter { $0.isSharedRecipe }
        }
    }
    
    // MARK: - Recipe Loading
    
    /// Load and cache all recipes from SwiftData (both owned and cached shared)
    private func refreshRecipeCache() {
        AppLog.debug("🔄 Refreshing recipe cache", category: .recipe)
        AppLog.debug("Saved recipes count: \(savedRecipes.count)", category: .recipe)
        AppLog.debug("Cached shared recipes count: \(cachedSharedRecipes.count)", category: .recipe)
        
        // Combine both types of recipes into a single array
        var allRecipes: [any RecipeDisplayProtocol] = []
        
        // Add owned recipes (RecipeX)
        allRecipes.append(contentsOf: savedRecipes as [any RecipeDisplayProtocol])
        
        // Add cached shared recipes (CachedSharedRecipe)
        allRecipes.append(contentsOf: cachedSharedRecipes as [any RecipeDisplayProtocol])
        
        AppLog.debug("Total available recipes count: \(allRecipes.count)", category: .recipe)
        
        // Update cache
        cachedAllRecipes = allRecipes
        
        // If not filtering, update filtered cache too
        if filterMode == .none {
            cachedFilteredRecipes = allRecipes
        }
    }
    
    // MARK: - Filter Processing
    
    /// Process filtering in background to avoid blocking UI
    private func processFilter() {
        // If no filter, just use all recipes
        guard filterMode != .none else {
            cachedFilteredRecipes = cachedAllRecipes
            cachedAllergenScores = [:]
            cachedDiabetesScores = [:]
            cachedCombinedScores = [:]
            return
        }
        
        // Show loading state
        isProcessingFilter = true
        
        // Capture values to use in task
        let recipesToProcess = cachedAllRecipes
        let shouldShowOnlySafe = showOnlySafe
        let currentMode = filterMode
        let currentProfile = activeProfile
        
        // Use regular Task instead of Task.detached to avoid sendability issues
        Task(priority: .userInitiated) {
            var allergenScores: [UUID: RecipeAllergenScore] = [:]
            var diabetesScores: [UUID: DiabetesScore] = [:]
            var combinedScores: [UUID: CombinedRecipeScore] = [:]
            var nutritionalScores: [UUID: NutritionalScore] = [:]
            
            // Convert protocol recipes to a format analyzers can work with
            // Analyzers need RecipeX or something with same properties
            // For now, we'll only analyze RecipeX objects (owned recipes)
            // Shared recipes won't have allergen/diabetes filtering
            let recipeXObjects = recipesToProcess.compactMap { $0 as? RecipeX }
            
            // Analyze for allergens if needed
            if currentMode.includesAllergenFilter, let profile = currentProfile {
                allergenScores = AllergenAnalyzer.shared.analyzeRecipes(recipeXObjects, profile: profile)
            }
            
            // Analyze for diabetes if needed
            if currentMode.includesDiabetesFilter {
                diabetesScores = DiabetesAnalyzer.shared.analyzeRecipes(recipeXObjects)
            }
            
            if currentMode.includesNutritionalFilter,
               let profile = currentProfile,
               let goals = profile.nutritionalGoals {
                nutritionalScores = NutritionalAnalyzer.shared.analyzeRecipes(
                    recipeXObjects,
                    goals: goals
                )
            }
            
            // Create combined scores (only for RecipeX)
            for recipe in recipeXObjects {
                let score = CombinedRecipeScore(
                    recipeID: recipe.safeID,
                    allergenScore: allergenScores[recipe.safeID],
                    diabetesScore: diabetesScores[recipe.safeID],
                    nutritionalScore: nutritionalScores[recipe.safeID],
                    filterMode: currentMode
                )
                combinedScores[recipe.safeID] = score
            }
            
            // Filter or sort based on settings
            let filteredRecipes: [any RecipeDisplayProtocol]
            if shouldShowOnlySafe {
                // Show only safe recipes (only applies to RecipeX)
                filteredRecipes = recipesToProcess.filter { recipe in
                    // If it's a shared recipe, include it (no filtering)
                    if recipe.isSharedRecipe {
                        return true
                    }
                    
                    // For owned recipes, check safety score
                    guard let score = combinedScores[recipe.displayID] else { return true }
                    return score.isSafe
                }
            } else {
                // Sort by safety score (safest first), shared recipes go to end
                filteredRecipes = recipesToProcess.sorted { recipe1, recipe2 in
                    // Shared recipes go to the end
                    if recipe1.isSharedRecipe && !recipe2.isSharedRecipe {
                        return false
                    }
                    if !recipe1.isSharedRecipe && recipe2.isSharedRecipe {
                        return true
                    }
                    
                    // Both same type - sort by score
                    let score1 = combinedScores[recipe1.displayID]?.overallScore ?? 0
                    let score2 = combinedScores[recipe2.displayID]?.overallScore ?? 0
                    return score1 < score2
                }
            }
            
            // Update UI on main thread
            await MainActor.run {
                cachedFilteredRecipes = filteredRecipes
                cachedAllergenScores = allergenScores
                cachedDiabetesScores = diabetesScores
                cachedCombinedScores = combinedScores
                cachedNutritionalScores = nutritionalScores
                isProcessingFilter = false
            }
        }
    }
    
    @MainActor
    private func shareRecipe(_ recipe: any RecipeDisplayProtocol) async {
        // Only allow sharing of owned recipes (RecipeX), not cached shared recipes
        guard let recipeX = recipe as? RecipeX else {
            AppLog.warning("Cannot share cached community recipes", category: .sharing)
            return
        }
        
        do {
            _ = try await CloudKitSharingService.shared.shareRecipe(
                recipeX,
                modelContext: modelContext
            )
            // Show success message
            AppLog.info("Successfully shared recipe: \(recipe.displayTitle)", category: .sharing)
        } catch {
            // Show error
            AppLog.error("Failed to share recipe: \(error)", category: .sharing)
        }
    }
    
    // MARK: - Community Sync
    
    /// Auto-sync community recipes when switching to Shared tab
    /// Only syncs once every 5 minutes to avoid excessive calls
    /// Fetches ALL available community recipes using pagination
    private func syncCommunityRecipesIfNeeded() async {
        // Check if we need to sync (only if 5+ minutes have passed since last sync)
        if let lastSync = lastCommunitySync {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            if timeSinceLastSync < syncInterval {
                AppLog.debug("Skipping sync - last synced \(Int(timeSinceLastSync))s ago", category: .sharing)
                return
            }
        }
        
        // Prevent concurrent syncs
        guard !isSyncingCommunityRecipes else {
            AppLog.debug("Sync already in progress, skipping", category: .sharing)
            return
        }
        
        isSyncingCommunityRecipes = true
        syncProgress = "Connecting to CloudKit..."
        
        AppLog.info("🔄 Auto-syncing ALL community recipes (paginated)...", category: .sharing)
        
        do {
            // Use a high limit to fetch all recipes - CloudKit will paginate automatically
            // The service uses 100-record batches internally with cursor-based pagination
            syncProgress = "Fetching recipes..."
            
            try await CloudKitSharingService.shared.syncCommunityRecipesForViewing(
                modelContext: modelContext,
                limit: Int.max // Fetch all available recipes
            )
            
            // Update last sync time
            lastCommunitySync = Date()
            
            syncProgress = "Sync complete!"
            AppLog.info("✅ Auto-sync completed successfully (all recipes synced)", category: .sharing)
            
            // Clear progress after delay
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            syncProgress = ""
        } catch {
            // Silently fail - manual sync still available
            syncProgress = "Sync failed"
            AppLog.error("Auto-sync failed: \(error)", category: .sharing)
            
            // Clear error after delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            syncProgress = ""
        }
        
        isSyncingCommunityRecipes = false
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Global batch extraction status bar
            BatchExtractionStatusBar(manager: BatchExtractionManager.shared)
            
            mainNavigationView
        }
    }
    
    // MARK: - Main Navigation View
    
    private var mainNavigationView: some View {
        navigationSplitViewWithLifecycle
            .modifier(FilterObserversModifier(
                filterMode: filterMode,
                showOnlySafe: showOnlySafe,
                activeProfile: activeProfile,
                onFilterChange: processFilter
            ))
            .modifier(RecipeObserversModifier(
                savedRecipesCount: savedRecipes.count,
                cachedRecipesCount: cachedSharedRecipes.count,
                selectedRecipe: selectedRecipe,
                selectedRecipeID: selectedRecipeID,
                contentFilter: contentFilter,
                onRecipeCountChange: handleRecipeCountChange,
                onSelectedRecipeChange: { appState.selectedRecipeId = $0?.displayID },
                onSelectedIDChange: updateSelectedRecipe,
                onContentFilterChange: handleContentFilterChange
            ))
    }
    
    private var navigationSplitViewWithLifecycle: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .onAppear(perform: handleOnAppear)
        .task(priority: .background, handleRecoveryTask)
    }
    
    private func handleOnAppear() {
        restoreSelectedRecipe()
        refreshRecipeCache()

        // Auto-clean duplicates in background after recipes load
        Task {
            // Small delay so the list renders first
            try? await Task.sleep(for: .seconds(2))
            await autoCleanDuplicates()
        }
    }

    /// Silently removes duplicate recipes so the user only ever sees unique entries.
    /// Skips the scan entirely when the recipe count hasn't changed since the last
    /// clean run, avoiding unnecessary DB pressure on every onAppear.
    private func autoCleanDuplicates() async {
        let allRecipes = savedRecipes  // already @Query'd
        guard allRecipes.count > 1 else {
            DuplicateScanTracker.recordCleanScan(recipeCount: allRecipes.count)
            return
        }

        // Skip if nothing has changed since the last clean scan
        if DuplicateScanTracker.shouldSkipScan(currentCount: allRecipes.count) {
            AppLog.info("⏭️ Skipping launch duplicate scan — recipe count unchanged (\(allRecipes.count))", category: .cloudKit)
            return
        }

        DuplicateScanTracker.recordScanRan()

        // Reuse the shared detection logic
        let clusters = DuplicateRecipeDetectorView.buildDuplicateClusters(from: allRecipes)

        guard !clusters.isEmpty else {
            DuplicateScanTracker.recordCleanScan(recipeCount: allRecipes.count)
            AppLog.info("✅ Launch duplicate scan clean — will skip until count changes", category: .cloudKit)
            return
        }

        var deletedCount = 0
        for cluster in clusters {
            for dupe in cluster.duplicatesToDelete {
                AppLog.info("🗑️ Auto-removing duplicate: '\(dupe.safeTitle)' (ID: \(String(describing: dupe.id)))", category: .cloudKit)
                modelContext.delete(dupe)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            do {
                try modelContext.save()
                AppLog.info("✅ Auto-cleaned \(deletedCount) duplicate recipe(s) on launch", category: .cloudKit)
                DuplicateScanTracker.recordCleanScan(recipeCount: allRecipes.count - deletedCount)
                refreshRecipeCache()
            } catch {
                AppLog.error("❌ Failed to auto-clean duplicates: \(error)", category: .cloudKit)
            }
        }
    }
    
    @Sendable
    private func handleRecoveryTask() async {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        let stats = DatabaseRecoveryLogger.shared.getRecoveryStatistics()
        if stats.totalAttempts > 0 {
            DatabaseRecoveryLogger.shared.logRecoveryStatistics()
        }
    }
    
    private func handleRecipeCountChange() {
        refreshRecipeCache()
        if filterMode != .none {
            processFilter()
        }
    }
    
    private func updateSelectedRecipe(_ newID: UUID?) {
        if let newID = newID {
            selectedRecipe = availableRecipes.first { $0.displayID == newID }
        } else {
            selectedRecipe = nil
        }
    }
    
    private func handleContentFilterChange(_ newValue: ContentFilterMode) {
        if newValue == .shared {
            Task {
                await syncCommunityRecipesIfNeeded()
            }
        }
    }
    
    // MARK: - Sidebar Content
    
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Content filter picker (Mine/Shared) - ALWAYS visible
            ContentFilterPicker(
                selectedFilter: $contentFilter,
                contentType: "Recipes"
            )
            
            // Sync progress indicator (only when syncing community recipes)
            if isSyncingCommunityRecipes {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(syncProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))
            }
            
            if availableRecipes.isEmpty {
                // Empty state when no recipes exist (but filter picker still visible above)
                emptyStateViewContent
            } else {
                // Recipe list when recipes are available
                recipeListContent
            }
        }
    }
    
    // MARK: - Detail Content
    
    private var detailContent: some View {
        Group {
            if let recipe = selectedRecipe {
                selectedRecipeDetailView(recipe)
            } else {
                ContentUnavailableView(
                    "Select a Recipe",
                    systemImage: "book.closed",
                    description: Text("Choose a recipe from the list to view its details")
                )
            }
        }
    }
    
    @ViewBuilder
    private func selectedRecipeDetailView(_ recipe: any RecipeDisplayProtocol) -> some View {
        if let recipeX = recipe as? RecipeX {
            RecipeDetailView(recipe: recipeX, autoRepair: triggerRepairForRecipe?.id == recipeX.id)
                .id("\(String(describing: recipeX.id))-\(recipeX.imageName ?? "no-image")-\(triggerRepairForRecipe?.id == recipeX.id ? "repair" : "")")
                .onDisappear {
                    if triggerRepairForRecipe?.id == recipeX.id {
                        triggerRepairForRecipe = nil
                    }
                }
        } else if let cachedRecipe = recipe as? CachedSharedRecipe {
            CachedRecipeDetailView(cachedRecipe: cachedRecipe)
                .id("\(cachedRecipe.id)-\(cachedRecipe.imageName ?? "no-image")")
        }
    }
    
    // MARK: - Empty State View
    
    private var emptyStateViewContent: some View {
        VStack {
            Spacer()
            
            emptyStateContent
            
            Spacer()
        }
        .navigationTitle("Recipes")
        .sheet(isPresented: $showingRecipeExtractor) {
            RecipeExtractorView(apiKey: getAPIKey())
        }
        .sheet(isPresented: $showingCreateRecipe) {
            CreateRecipeView()
        }
    }
    
    private var emptyStateContent: some View {
        ContentUnavailableView {
            emptyStateLabel
        } description: {
            emptyStateDescriptionView
        } actions: {
            emptyStateActions
        }
    }
    
    private var emptyStateLabel: some View {
        Label(emptyStateTitle, systemImage: "book.closed")
    }
    
    private var emptyStateDescriptionView: some View {
        Text(emptyStateDescription)
    }
    
    @ViewBuilder
    private var emptyStateActions: some View {
        if contentFilter != .mine {
            Button {
                contentFilter = .mine
            } label: {
                Label("Show My Recipes", systemImage: "person.fill")
            }
        }
        
        Button {
            showingRecipeExtractor = true
        } label: {
            Label("Extract Recipe", systemImage: "plus.circle.fill")
        }
    }
    
    private var emptyStateTitle: String {
        switch contentFilter {
        case .mine:
            return "No Recipes Yet"
        case .shared:
            return "No Shared Recipes"
        }
    }
    
    private var emptyStateDescription: String {
        switch contentFilter {
        case .mine:
            return "Extract recipes from text or images using the Claude API to get started"
        case .shared:
            return "No recipes have been shared by the community yet. Check back later or create and share your own recipes!"
        }
    }
    
    // MARK: - Recipe List View
    
    private var recipeListContent: some View {
        VStack(spacing: 0) {
            // Filter bar with 4-state selector
            RecipeFilterBar(
                filterMode: $filterMode,
                showOnlySafe: $showOnlySafe,
                activeProfile: activeProfile,
                onProfileTap: {
                    showingAllergenProfiles = true
                }
            )
            
            // Recipe count display (especially useful for community recipes)
            if contentFilter == .shared && !cachedSharedRecipes.isEmpty {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(Color.appInfo)
                    Text("\(availableRecipes.count) Community \(availableRecipes.count == 1 ? "Recipe" : "Recipes")")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if availableRecipes.count != cachedSharedRecipes.count {
                        Text("(\(cachedSharedRecipes.count) total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            
            // Loading indicator when processing filter
            if isProcessingFilter {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Analyzing recipes...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.appGray6)
            }
            
            List(selection: $selectedRecipeID) {
                Section {
                    ForEach(availableRecipes, id: \.displayID) { recipe in
                        Button {
                            selectedRecipe = recipe
                            selectedRecipeID = recipe.displayID
                        } label: {
                            recipeRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                        .tag(recipe.displayID)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            // Only allow deleting owned recipes
                            if let recipeX = recipe as? RecipeX {
                                Button(role: .destructive) {
                                    deleteRecipe(recipeX)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .contextMenu {
                            // Context menu options depend on recipe type
                            if let recipeX = recipe as? RecipeX {
                                // Full menu for owned recipes
                                ownedRecipeContextMenu(recipe: recipeX)
                            } else if recipe is CachedSharedRecipe {
                                // Limited menu for cached shared recipes
                                sharedRecipeContextMenu(recipe: recipe)
                            }
                        }
                    }
                } header: {
                    RecipeFilterStatusHeader(
                        filterMode: filterMode,
                        showOnlySafe: showOnlySafe,
                        totalRecipes: availableRecipesBeforeFilter.count,
                        filteredCount: availableRecipes.count
                    )
                } footer: {
                    Text("\(savedRecipes.count) recipe(s) in your collection")
                }
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 250, ideal: 300)
#endif
            .navigationTitle("Recipes")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .platformNavBarTrailing) {
                    CloudKitSyncBadge()
                }
                
                ToolbarItem(placement: .platformNavBarTrailing) {
                    Button {
                        appState.currentTab = .books
                    } label: {
                        Label("View Books", systemImage: "books.vertical")
                    }
                }
                
                ToolbarItem(placement: .platformNavBarTrailing) {
                    Button {
                        showingSearch = true
                    } label: {
                        Label("Search Recipes", systemImage: "magnifyingglass")
                    }
                }
                
                ToolbarItem(placement: .platformNavBarTrailing) {
                    Menu {
                        Button {
                            showingCreateRecipe = true
                        } label: {
                            Label("Create Recipe", systemImage: "doc.badge.plus")
                        }
                        
                        Button {
                            showingRecipeExtractor = true
                        } label: {
                            Label("Extract from Image", systemImage: "camera")
                        }
                    } label: {
                        Label("Add Recipe", systemImage: "plus")
                    }
                }
#else
                ToolbarItem(placement: .primaryAction) {
                    CloudKitSyncBadge()
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSearch = true
                    } label: {
                        Label("Search Recipes", systemImage: "magnifyingglass")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingCreateRecipe = true
                        } label: {
                            Label("Create Recipe", systemImage: "doc.badge.plus")
                        }
                        
                        Button {
                            showingRecipeExtractor = true
                        } label: {
                            Label("Extract from Image", systemImage: "camera")
                        }
                    } label: {
                        Label("Add Recipe", systemImage: "plus")
                    }
                }
#endif
            }
            .sheet(isPresented: $showingRecipeExtractor) {
                RecipeExtractorView(apiKey: getAPIKey())
            }
            .sheet(isPresented: $showingCreateRecipe) {
                CreateRecipeView()
            }
            .sheet(isPresented: $showingAllergenProfiles) {
                AllergenProfileView()
            }
            .sheet(isPresented: $showingImport) {
                RecipeBookImportView()
            }
            .sheet(isPresented: $showingSearch) {
                RecipeSearchModalView(
                    recipes: .constant(availableRecipes),
                    selectedRecipe: $selectedRecipe
                )
            }
        }
    }
    
    // MARK: - Recipe Row
    
    private func recipeRow(recipe: any RecipeDisplayProtocol) -> some View {
        return HStack(spacing: 12) {
            // Thumbnail or placeholder
            if let recipeX = recipe as? RecipeX {
                // RecipeX has both imageData (modern) and imageName (legacy)
                if recipeX.imageData != nil || recipeX.imageName != nil {
                    RecipeImageView(
                        imageName: recipeX.imageName,
                        imageData: recipeX.imageData,
                        size: CGSize(width: 50, height: 50),
                        cornerRadius: 6
                    )
                } else {
                    placeholderImage
                }
            } else if let cachedRecipe = recipe as? CachedSharedRecipe {
                // CachedSharedRecipe only has imageName
                if let imageName = cachedRecipe.imageName {
                    RecipeImageView(
                        imageName: imageName,
                        imageData: nil,
                        size: CGSize(width: 50, height: 50),
                        cornerRadius: 6
                    )
                } else {
                    placeholderImage
                }
            } else {
                placeholderImage
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(recipe.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    // Red "Fix" badge for recipes with missing data
                    if let recipeX = recipe as? RecipeX, recipeX.needsRepair {
                        Button {
                            triggerRepairForRecipe = recipeX
                            selectedRecipe = recipeX
                            selectedRecipeID = recipeX.displayID
                        } label: {
                            Text("Fix")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .statusBadgeStyle(tone: .critical)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let headerNotes = recipe.headerNotes {
                    Text(headerNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Show who shared this recipe if it's a shared recipe
                if recipe.isSharedRecipe, let sharedBy = recipe.sharedByUserName {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.appInfo)
                        Text("Shared by \(sharedBy)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Show books this recipe is in (only for RecipeX)
                if let recipeX = recipe as? RecipeX, !booksContaining(recipeX).isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed.fill")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                        Text(bookBadgeText(for: recipeX))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
            
            // Combined badge (shows allergen, diabetes, or both based on filter mode)
            // Only show for RecipeX (owned recipes)
            if !recipe.isSharedRecipe, filterMode != .none, let score = combinedScores[recipe.displayID] {
                CombinedRecipeBadge(score: score, compact: true)
            }
            if !recipe.isSharedRecipe, (filterMode == .nutrition || filterMode == .all),
               let score = cachedNutritionalScores[recipe.displayID] {
                NutritionalBadge(score: score, compact: true)
            }
        }
    }
    
    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.1))
            .frame(width: 50, height: 50)
            .overlay(
                Text("No\nImage")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            )
    }
    
    // MARK: - Book Helper Methods
    
    /// Returns all books that contain the given recipe
    private func booksContaining(_ recipe: RecipeX) -> [Book] {
        books.filter { ($0.recipeIDs ?? []).contains(recipe.safeID) }
    }
    
    /// Returns a formatted string describing which books contain this recipe
    private func bookBadgeText(for recipe: RecipeX) -> String {
        let containingBooks = booksContaining(recipe)
        if containingBooks.count == 1 {
            return "in \(containingBooks[0].name ?? "Untitled Book")"
        } else if containingBooks.count > 1 {
            return "in \(containingBooks.count) books"
        }
        return ""
    }
    
    /// Returns the primary color for a book, or a default color
    private func bookColor(for book: Book) -> Color {
        if let colorHex = book.color {
            return Color(hex: colorHex) ?? .purple
        }
        return .purple
    }
    
    // MARK: - Helper Methods
    
    /// Context menu for owned recipes (RecipeX)
    @ViewBuilder
    private func ownedRecipeContextMenu(recipe: RecipeX) -> some View {
        // Add to Book submenu
        Menu {
            if books.isEmpty {
                Button {
                    // Switch to books tab to create a book
                    appState.currentTab = .books
                } label: {
                    Label("Create First Book", systemImage: "plus.circle")
                }
            } else {
                ForEach(books) { book in
                    Button {
                        toggleRecipeInBook(recipe, book: book)
                    } label: {
                        HStack {
                            Text(book.name ?? "Untitled Book")
                            Spacer()
                            if (book.recipeIDs ?? []).contains(recipe.safeID) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.appInfo)
                            }
                        }
                    }
                }
                
                Divider()
                
                Button {
                    // Switch to books tab to create a new book
                    appState.currentTab = .books
                } label: {
                    Label("Create New Book", systemImage: "plus.circle")
                }
            }
        } label: {
            Label("Add to Book", systemImage: "book.closed")
        }
        
        Divider()
        
        Button {
            Task {
                await shareRecipe(recipe)
            }
        } label: {
            Label("Share with Community", systemImage: "square.and.arrow.up")
        }
        
        Button(role: .destructive) {
            deleteRecipe(recipe)
        } label: {
            Label("Delete Recipe", systemImage: "trash")
        }
    }
    
    /// Context menu for cached shared recipes (CachedSharedRecipe)
    @ViewBuilder
    private func sharedRecipeContextMenu(recipe: any RecipeDisplayProtocol) -> some View {
        Button {
            // Import to permanent collection
            if let cachedRecipe = recipe as? CachedSharedRecipe {
                importCachedRecipe(cachedRecipe)
            }
        } label: {
            Label("Add to My Recipes", systemImage: "plus.square.on.square")
        }
        
        // Option to view in browser if it has a reference
        if let reference = recipe.reference, let url = URL(string: reference) {
            Button {
                PlatformURLOpener.open(url)
            } label: {
                Label("View Original", systemImage: "safari")
            }
        }
    }
    
    /// Import a cached shared recipe into permanent collection
    private func importCachedRecipe(_ cachedRecipe: CachedSharedRecipe) {
        do {
            try CloudKitSharingService.shared.importCachedRecipe(cachedRecipe, modelContext: modelContext)
            AppLog.info("Imported cached recipe: \(cachedRecipe.title)", category: .sharing)
        } catch {
            AppLog.error("Failed to import cached recipe: \(error)", category: .sharing)
        }
    }
    
    private func toggleRecipeInBook(_ recipe: RecipeX, book: Book) {
        withAnimation {
            let recipeIDs = book.recipeIDs ?? []
            if recipeIDs.contains(recipe.safeID) {
                // Remove from book
                book.removeRecipe(recipe.safeID)
                AppLog.info("Removed '\(recipe.safeTitle)' from book '\(book.name ?? "Unknown")'", category: .recipe)
            } else {
                // Add to book
                book.addRecipe(recipe.safeID)
                AppLog.info("Added '\(recipe.safeTitle)' to book '\(book.name ?? "Unknown")'", category: .recipe)
            }
            
            // Save the context
            do {
                try modelContext.save()
            } catch {
                AppLog.error("Failed to update book membership: \(error)", category: .recipe)
            }
        }
    }
    
    private func restoreSelectedRecipe() {
        // Restore selected recipe from app state if available
        if let recipeId = appState.selectedRecipeId {
            // Find the recipe in available recipes (both RecipeX and CachedSharedRecipe)
            if let recipe = availableRecipes.first(where: { $0.displayID == recipeId }) {
                selectedRecipe = recipe
                selectedRecipeID = recipeId
                AppLog.info("Restored selected recipe: \(recipe.displayTitle)", category: .state)
            } else {
                // Recipe no longer exists, clear the selection
                appState.selectedRecipeId = nil
                selectedRecipeID = nil
            }
        }
    }
    
    private func deleteRecipe(_ recipe: RecipeX) {
        withAnimation {
            AppLog.info("Deleting recipe: \(recipe.safeTitle) (ID: \(recipe.safeID))", category: .recipe)
            
            // Delete associated image file if it exists
            if let imageName = recipe.imageName {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fileURL = documentsPath.appendingPathComponent(imageName)
                try? FileManager.default.removeItem(at: fileURL)
                AppLog.info("Deleted image file: \(imageName)", category: .storage)
            }
            
            // Delete any RecipeImageAssignments for this recipe
            let assignmentsToDelete = imageAssignments.filter { $0.recipeID == recipe.safeID }
            for assignment in assignmentsToDelete {
                modelContext.delete(assignment)
                AppLog.debug("Deleted image assignment for recipe", category: .storage)
            }
            
            // Delete the recipe itself
            modelContext.delete(recipe)
            
            // Save the context to persist the deletion
            do {
                try modelContext.save()
                AppLog.info("Recipe deleted and changes saved", category: .recipe)
            } catch {
                AppLog.error("Failed to save deletion: \(error)", category: .storage)
            }
        }
    }
    
    private func getAPIKey() -> String {
        // Get API key from keychain, or return empty string
        // The RecipeExtractorView will handle the case when API key is missing
        return APIKeyHelper.getAPIKey() ?? ""
    }
}

// MARK: - View Modifiers for Change Observers

/// View modifier to handle filter-related changes
private struct FilterObserversModifier: ViewModifier {
    let filterMode: RecipeFilterMode
    let showOnlySafe: Bool
    let activeProfile: UserAllergenProfile?
    let onFilterChange: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onChange(of: filterMode) { _, _ in
                onFilterChange()
            }
            .onChange(of: showOnlySafe) { _, _ in
                if filterMode != .none {
                    onFilterChange()
                }
            }
            .onChange(of: activeProfile?.id) { _, _ in
                if filterMode.includesAllergenFilter {
                    onFilterChange()
                }
            }
            .onChange(of: activeProfile?.diabetesStatus) { _, _ in
                if filterMode.includesDiabetesFilter {
                    onFilterChange()
                }
            }
    }
}

/// View modifier to handle recipe and selection changes
private struct RecipeObserversModifier: ViewModifier {
    let savedRecipesCount: Int
    let cachedRecipesCount: Int
    let selectedRecipe: (any RecipeDisplayProtocol)?
    let selectedRecipeID: UUID?
    let contentFilter: ContentFilterMode
    let onRecipeCountChange: () -> Void
    let onSelectedRecipeChange: ((any RecipeDisplayProtocol)?) -> Void
    let onSelectedIDChange: (UUID?) -> Void
    let onContentFilterChange: (ContentFilterMode) -> Void
    
    func body(content: Content) -> some View {
        content
            .onChange(of: savedRecipesCount) { _, _ in
                onRecipeCountChange()
            }
            .onChange(of: cachedRecipesCount) { _, _ in
                onRecipeCountChange()
            }
            .onChange(of: selectedRecipe?.displayID) { _, _ in
                onSelectedRecipeChange(selectedRecipe)
            }
            .onChange(of: selectedRecipeID) { _, newID in
                onSelectedIDChange(newID)
            }
            .onChange(of: contentFilter) { _, newValue in
                onContentFilterChange(newValue)
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [RecipeX.self, RecipeImageAssignment.self, UserAllergenProfile.self, Book.self, SavedLink.self, VersionHistoryRecord.self], inMemory: true)
        .environmentObject(AppStateManager.shared)
}
// MARK: - Recipe Book Badge View

/// A compact badge showing which books contain a recipe
struct BookBadge: View {
    let books: [Book]
    let compact: Bool
    
    init(books: [Book], compact: Bool = true) {
        self.books = books
        self.compact = compact
    }
    
    var body: some View {
        if books.isEmpty {
            EmptyView()
        } else if compact {
            compactBadge
        } else {
            expandedBadge
        }
    }
    
    private var compactBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "book.closed.fill")
                .font(.caption2)
                .foregroundStyle(.purple)
            
            if books.count == 1 {
                Text("in \(books[0].name ?? "Untitled Book")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("in \(books.count) books")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var expandedBadge: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("In Recipe Books", systemImage: "books.vertical.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.purple)
            
            ForEach(books) { book in
                HStack(spacing: 6) {
                    Circle()
                        .fill(bookColor(for: book))
                        .frame(width: 6, height: 6)
                    
                    Text(book.name ?? "Untitled Book")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("\(book.recipeCount) recipes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func bookColor(for book: Book) -> Color {
        if let colorHex = book.color {
            return Color(hex: colorHex) ?? .purple
        }
        return .purple
    }
}

