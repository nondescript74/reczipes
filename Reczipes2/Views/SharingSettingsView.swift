//
//  SharingSettingsView.swift
//  Reczipes2
//
//  Created on 1/15/26.
//

import SwiftUI
import SwiftData

struct SharingSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sharingService = CloudKitSharingService.shared
    
    @Query private var sharingPreferences: [SharingPreferences]
    @Query private var sharedRecipes: [SharedRecipe]
    @Query private var sharedMeals: [SharedMeal]
    @Query private var sharedRecipeBooks: [SharedRecipeBook]
    @Query private var allBooks: [Book]
    @Query private var allMeals: [Meal]
    @Query private var recipeXEntities: [RecipeX]

    @State private var showingRecipeSelector = false
    @State private var showingBookSelector = false
    @State private var isSharing = false
    @State private var sharingStatus = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingOnboarding = false
    @State private var currentSharingError: SharingError?
    @State private var showingUnshareAllConfirmation = false
    @State private var showingUnshareAllBooksConfirmation = false
    @State private var showingUnshareAllMealsConfirmation = false
    
    private var preferences: SharingPreferences {
        if let existing = sharingPreferences.first {
            return existing
        } else {
            let newPrefs = SharingPreferences()
            modelContext.insert(newPrefs)
            return newPrefs
        }
    }
    
    // Count of recipes shared by the current user
    private var mySharedRecipesCount: Int {
        guard let currentUserID = sharingService.currentUserID else {
            return 0
        }
        return sharedRecipes.filter { $0.isActive && $0.sharedByUserID == currentUserID }.count
    }
    
    // Count of books shared by the current user (tracked via SharedRecipeBook)
    private var mySharedBooksCount: Int {
        guard let currentUserID = sharingService.currentUserID else { return 0 }
        return sharedRecipeBooks.filter { $0.isActive && $0.sharedByUserID == currentUserID }.count
    }

    // Count of meals shared by the current user
    private var mySharedMealsCount: Int {
        guard let currentUserID = sharingService.currentUserID else { return 0 }
        return sharedMeals.filter { $0.isActive && $0.sharedByUserID == currentUserID }.count
    }
    
    var body: some View {
        ZStack {
            List {
                // Info banner explaining iCloud sync vs public sharing
                infoSection
                
                // CloudKit Status
                cloudKitStatusSection
                
                // Auto-Sync Settings
                autoSyncSection
                
                // Sharing Preferences
                sharingPreferencesSection
                
                // My Shared Content
                mySharedContentSection
                
                // Quick Actions
                quickActionsSection
                
                // CloudKit Management (advanced)
                cloudKitManagementSection
            }
            .disabled(isSharing) // Disable all interactions during operations
            
            // Progress overlay
            if isSharing {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    if !sharingStatus.isEmpty {
                        Text(sharingStatus)
                            .font(.headline)
                            .foregroundStyle(Color.onTint)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
                .shadow(radius: 20)
            }
        }
        .navigationTitle("Public Sharing")
        .platformNavigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Initialize CloudKitSharingService with current preferences
            sharingService.updateUserDisplayName(from: preferences)
        }
        .sheet(isPresented: $showingRecipeSelector) {
            RecipeSelectorView(
                selectedRecipes: [],
                onShare: { recipes in
                    Task {
                        await shareRecipes(recipes)
                    }
                }
            )
        }
        .sheet(isPresented: $showingBookSelector) {
            BookSelectorView(
                selectedBooks: [],
                onShare: { books in
                    Task {
                        await shareBooks(books)
                    }
                }
            )
        }
        .alert("Sharing Status", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
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
                Text(error.localizedDescription)
            }
        }
        .sheet(isPresented: $showingOnboarding) {
            CloudKitOnboardingView()
        }
        .confirmationDialog(
            "Unshare All Recipes",
            isPresented: $showingUnshareAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unshare \(mySharedRecipesCount) Recipes", role: .destructive) {
                Task {
                    await unshareAllRecipes()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all \(mySharedRecipesCount) recipes from public sharing. They will remain in your personal library. This action cannot be undone.")
        }
        .confirmationDialog(
            "Unshare All Books",
            isPresented: $showingUnshareAllBooksConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unshare \(mySharedBooksCount) Books", role: .destructive) {
                Task {
                    await unshareAllBooks()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all \(mySharedBooksCount) books from public sharing. They will remain in your personal library. This action cannot be undone.")
        }
        .confirmationDialog(
            "Unshare All Meals",
            isPresented: $showingUnshareAllMealsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unshare \(mySharedMealsCount) Meals", role: .destructive) {
                Task { await unshareAllMeals() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all \(mySharedMealsCount) meals from public sharing. They will remain in your personal library.")
        }
        .task {
            await sharingService.checkCloudKitAvailability()
        }
    }
    
    // MARK: - Sections
    
    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.appInfo)
                        .font(.title3)
                    Text("About Public Sharing & License")
                        .font(.headline)
                }
                
                Text("Your recipes and books are automatically synced to iCloud across all your devices. This page is for **publicly sharing** specific content with the wider community.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("iCloud Sync: Always On", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.appSuccess)
                    
                    Label("Public Sharing: Your Choice", systemImage: "person.3.fill")
                        .font(.caption)
                        .foregroundStyle(Color.appInfo)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(Color.appSuccess)
                        Text("Sharing License")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    Text("All recipes you publicly share are automatically licensed under **Creative Commons BY 4.0** (attribution required). You may choose to share or keep your content private at any time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Sections
    
    private var cloudKitStatusSection: some View {
        Section {
            HStack {
                Image(systemName: sharingService.isCloudKitAvailable ? "icloud.fill" : "icloud.slash.fill")
                    .foregroundStyle(sharingService.isCloudKitAvailable ? .green : .red)
                
                VStack(alignment: .leading) {
                    Text(sharingService.isCloudKitAvailable ? "Ready to Share Publicly" : "Not Available")
                        .font(.headline)
                    
                    if let userName = sharingService.currentUserName {
                        Text("Signed in as \(userName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !sharingService.isCloudKitAvailable {
                        Text("Sign in to iCloud to enable public sharing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Public Sharing Status")
        } footer: {
            Text("Public sharing requires iCloud. Your private sync works regardless of these settings.")
        }
    }
    
    // MARK: - Auto-Sync Section
    
    private var autoSyncSection: some View {
        Section {
            Toggle("Auto-Sync Community Content", isOn: $sharingService.autoSyncEnabled)
                .disabled(!sharingService.isCloudKitAvailable)
            
            if sharingService.autoSyncEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Sync Interval")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(sharingService.syncIntervalDescription)
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(
                        value: $sharingService.syncInterval,
                        in: 300...1800,
                        step: 60
                    ) {
                        Text("Sync Interval")
                    } minimumValueLabel: {
                        Text("5m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("30m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Sync status indicator
                    if sharingService.isSyncing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Syncing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let lastSync = sharingService.lastSyncDate {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.appSuccess)
                                .font(.caption)
                            Text("Last synced: \(lastSync, style: .relative) ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let timeUntilNext = sharingService.timeUntilNextSync, timeUntilNext > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .foregroundStyle(Color.appInfo)
                                    .font(.caption)
                                Text("Next sync in \(Int(timeUntilNext))s")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // Manual sync button
                    Button {
                        Task {
                            await sharingService.manualSync(modelContext: modelContext)
                        }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(sharingService.isSyncing)
                }
            }
        } header: {
            Text("Auto-Sync")
        } footer: {
            if sharingService.autoSyncEnabled {
                Text("Automatically checks for new community recipes and books every \(sharingService.syncIntervalDescription). Longer intervals reduce database load and improve app performance.")
            } else {
                Text("Enable to automatically sync community recipes and books in the background. You can still browse and manually sync when disabled.")
            }
        }
    }
    
    private var cloudKitManagementSection: some View {
        Section {
            NavigationLink {
                SharedRecipesBrowserView()
            } label: {
                Label("Browse Community Recipes", systemImage: "book.pages")
            }
            
            NavigationLink {
                SharedBooksBrowserView()
            } label: {
                Label("Browse Community Books", systemImage: "books.vertical")
            }
            
            Divider()
            
            NavigationLink {
                CloudKitRecipeManagerView()
            } label: {
                Label("Manage CloudKit Recipes", systemImage: "cloud")
            }
            
            NavigationLink {
                CloudKitRecipeBookManagerView()
            } label: {
                Label("Manage CloudKit Recipe Books", systemImage: "books.vertical")
            }
        } header: {
            Text("Community & CloudKit Management")
        } footer: {
            Text("Browse recipes and books shared by the community, or manage your own CloudKit content including orphaned items.")
        }
    }

    
    private var sharingPreferencesSection: some View {
        Section {
            Toggle("Auto-Share New Recipes", isOn: Binding(
                get: { preferences.shareAllRecipes },
                set: { newValue in
                    preferences.shareAllRecipes = newValue
                    preferences.dateModified = Date()
                    try? modelContext.save()
                    
                    if newValue {
                        Task {
                            await shareAllRecipes()
                        }
                    } else {
                        Task {
                            await unshareAllRecipes()
                        }
                    }
                }
            ))
            .disabled(!sharingService.isCloudKitAvailable)
            
            Toggle("Auto-Share New Recipe Books", isOn: Binding(
                get: { preferences.shareAllBooks },
                set: { newValue in
                    preferences.shareAllBooks = newValue
                    preferences.dateModified = Date()
                    try? modelContext.save()

                    if newValue {
                        Task {
                            await shareAllBooks()
                        }
                    } else {
                        Task {
                            await unshareAllBooks()
                        }
                    }
                }
            ))
            .disabled(!sharingService.isCloudKitAvailable)

            Toggle("Auto-Share New Meals", isOn: Binding(
                get: { preferences.shareAllMeals },
                set: { newValue in
                    preferences.shareAllMeals = newValue
                    preferences.dateModified = Date()
                    try? modelContext.save()
                    if newValue {
                        Task { await shareAllMeals() }
                    } else {
                        Task { await unshareAllMeals() }
                    }
                }
            ))
            .disabled(!sharingService.isCloudKitAvailable)

            Toggle("Browse Community Library", isOn: Binding(
                get: { preferences.browseCommunity },
                set: { newValue in
                    preferences.browseCommunity = newValue
                    preferences.dateModified = Date()
                    try? modelContext.save()

                    if newValue {
                        // Immediately hydrate the communal library (all users, incl. self).
                        Task {
                            try? await sharingService.syncCommunityRecipesForViewing(
                                modelContext: modelContext,
                                limit: Int.max,
                                includeSelf: true
                            )
                        }
                    }
                }
            ))
            .disabled(!sharingService.isCloudKitAvailable)

            Toggle("Show My Name Publicly", isOn: Binding(
                get: { preferences.allowOthersToSeeMyName },
                set: { newValue in
                    preferences.allowOthersToSeeMyName = newValue
                    preferences.dateModified = Date()
                    try? modelContext.save()
                    
                    // Update CloudKitSharingService with new preference
                    sharingService.updateUserDisplayName(from: preferences)
                }
            ))
            .disabled(!sharingService.isCloudKitAvailable)
            
            if preferences.allowOthersToSeeMyName {
                TextField("Display Name", text: Binding(
                    get: { preferences.displayName ?? "" },
                    set: { newValue in
                        preferences.displayName = newValue.isEmpty ? nil : newValue
                        preferences.dateModified = Date()
                        try? modelContext.save()
                        
                        // Update CloudKitSharingService with new name
                        sharingService.updateUserDisplayName(from: preferences)
                    }
                ))
                .textContentType(.name)
                .autocorrectionDisabled()
                .disabled(!sharingService.isCloudKitAvailable)
                
                Text("This name will be shown when you publicly share recipes and books")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
        } header: {
            Text("Public Sharing Preferences")
        } footer: {
            Text("When auto-share is enabled, new recipes/books will be automatically shared with the community under Creative Commons BY 4.0 license (attribution required). Turn off to share items manually or keep them private. You retain full ownership and can stop sharing at any time.")
        }
    }
    
    private var mySharedContentSection: some View {
        Section {
            HStack {
                Label("\(mySharedRecipesCount) Recipes", systemImage: "book.fill")
                Spacer()
                Text("Publicly Shared")
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Label("\(mySharedBooksCount) Recipe Books", systemImage: "books.vertical.fill")
                Spacer()
                Text("Publicly Shared")
                    .foregroundStyle(.secondary)
            }
            
            NavigationLink("Manage Public Shares") {
                ManageSharedContentView()
            }
            
            // Bulk unshare actions
            if mySharedRecipesCount > 0 {
                Button(role: .destructive) {
                    showingUnshareAllConfirmation = true
                } label: {
                    Label("Unshare All Recipes (\(mySharedRecipesCount))", systemImage: "trash")
                }
                .disabled(!sharingService.isCloudKitAvailable)
            }
            
            if mySharedBooksCount > 0 {
                Button(role: .destructive) {
                    showingUnshareAllBooksConfirmation = true
                } label: {
                    Label("Unshare All Books (\(mySharedBooksCount))", systemImage: "trash")
                }
                .disabled(!sharingService.isCloudKitAvailable)
            }
        } header: {
            Text("My Public Shares")
        } footer: {
            Text("These items are shared publicly with the community under Creative Commons BY 4.0 license. They're separate from your private iCloud sync and you can stop sharing them at any time.")
        }
    }
    
    private var quickActionsSection: some View {
        Section {
            Button {
                showingRecipeSelector = true
            } label: {
                Label("Share Specific Recipes", systemImage: "square.and.arrow.up")
            }
            .disabled(!sharingService.isCloudKitAvailable)
            
            Button {
                showingBookSelector = true
            } label: {
                Label("Share Specific Books", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(!sharingService.isCloudKitAvailable)
            
            // Advanced Tools (collapsed into disclosure group)
            DisclosureGroup {
                // Diagnostic & Cleanup Tools - Recipes
                Button {
                    Task {
                        await cleanupGhostRecipes()
                    }
                } label: {
                    Label("Clean Up Ghost Recipes", systemImage: "sparkles")
                }
                .disabled(!sharingService.isCloudKitAvailable)
                
                Button {
                    Task {
                        await syncLocalTracking()
                    }
                } label: {
                    Label("Sync Recipe Sharing Status", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!sharingService.isCloudKitAvailable)
                
                Button {
                    Task {
                        await repairRecipeCloudKitIDs()
                    }
                } label: {
                    Label("Repair Recipe CloudKit IDs", systemImage: "wrench.and.screwdriver")
                }
                .disabled(!sharingService.isCloudKitAvailable)
                
                Divider()
                
                // Diagnostic & Cleanup Tools - Recipe Books
                Button {
                    Task {
                        await cleanupGhostRecipeBooks()
                    }
                } label: {
                    Label("Clean Up Ghost Recipe Books", systemImage: "sparkles.rectangle.stack")
                }
                .disabled(!sharingService.isCloudKitAvailable)
                
                Button {
                    Task {
                        await syncLocalRecipeBookTracking()
                    }
                } label: {
                    Label("Sync Recipe Book Sharing Status", systemImage: "arrow.triangle.2.circlepath.circle")
                }
                .disabled(!sharingService.isCloudKitAvailable)
                
                Button {
                    Task {
                        await repairRecipeBookCloudKitIDs()
                    }
                } label: {
                    Label("Repair Recipe Book CloudKit IDs", systemImage: "wrench.and.screwdriver.fill")
                }
                .disabled(!sharingService.isCloudKitAvailable)
                
                Divider()
                
                // Community Sync
                Button {
                    Task {
                        await syncCommunityBooks()
                    }
                } label: {
                    Label("Sync Community Books", systemImage: "books.vertical.circle")
                }
                .disabled(!sharingService.isCloudKitAvailable)
                
                Button {
                    Task {
                        await syncCommunityRecipes()
                    }
                } label: {
                    Label("Sync Community Recipes", systemImage: "book.circle")
                }
                .disabled(!sharingService.isCloudKitAvailable)
                
                Button {
                    Task {
                        await diagnoseSharedBooks()
                    }
                } label: {
                    Label("Diagnose Shared Books", systemImage: "stethoscope")
                }
                .disabled(!sharingService.isCloudKitAvailable)
            } label: {
                Label("Advanced Tools", systemImage: "gearshape.2")
            }
        } header: {
            Text("Quick Actions")
        } footer: {
            Text("Use 'Share Specific' buttons to manually share content. Advanced tools help resolve issues with shared content.")
        }
    }
    
    // MARK: - Actions
    
    private func shareAllRecipes() async {
        guard !recipeXEntities.isEmpty else { return }
        
        isSharing = true
        sharingStatus = "Sharing all recipes..."
        // Use RecipeX entities directly
        let result = await sharingService.shareMultipleRecipes(recipeXEntities, modelContext: modelContext)
        isSharing = false
        
        switch result {
        case .success(let message):
            alertMessage = message
            showingAlert = true
        case .partialSuccess(let successful, let failed):
            alertMessage = "Shared \(successful) recipes. \(failed) failed."
            showingAlert = true
        case .failure(let error):
            if let sharingError = error as? SharingError {
                currentSharingError = sharingError
            } else {
                alertMessage = "Failed to share recipes: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
    
    private func shareAllBooks() async {
        guard !allBooks.isEmpty else { return }

        isSharing = true
        sharingStatus = "Sharing all books..."

        var successful = 0
        var failed = 0

        for book in allBooks {
            guard book.id != nil, book.name != nil, book.recipeIDs != nil else {
                failed += 1
                continue
            }
            do {
                _ = try await sharingService.shareRecipeBook(book, modelContext: modelContext)
                successful += 1
            } catch {
                AppLog.error("Failed to share book '\(book.displayName)': \(error)", category: .sharing)
                failed += 1
            }
        }

        isSharing = false

        if failed == 0 {
            alertMessage = "Successfully shared all \(successful) books"
        } else {
            alertMessage = "Shared \(successful) of \(allBooks.count) books. \(failed) failed."
        }
        showingAlert = true
    }
    
    private func shareRecipes(_ recipes: [RecipeX]) async {
        // Share selected RecipeX entities
        isSharing = true
        let result = await sharingService.shareMultipleRecipes(recipes, modelContext: modelContext)
        isSharing = false
        
        switch result {
        case .success(let message):
            alertMessage = message
            showingAlert = true
        case .partialSuccess(let successful, let failed):
            alertMessage = "Shared \(successful) recipes. \(failed) failed."
            showingAlert = true
        case .failure(let error):
            if let sharingError = error as? SharingError {
                currentSharingError = sharingError
            } else {
                alertMessage = "Failed to share recipes: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
    
    private func shareBooks(_ books: [Book]) async {
        isSharing = true

        var successful = 0
        var failed = 0

        for book in books {
            guard book.id != nil, book.name != nil, book.recipeIDs != nil else {
                failed += 1
                continue
            }
            do {
                _ = try await sharingService.shareRecipeBook(book, modelContext: modelContext)
                successful += 1
            } catch {
                AppLog.error("Failed to share book '\(book.displayName)': \(error)", category: .sharing)
                failed += 1
            }
        }

        isSharing = false

        if books.isEmpty {
            alertMessage = "No books to share"
        } else if failed == 0 {
            alertMessage = "Successfully shared all \(successful) books"
        } else {
            alertMessage = "Shared \(successful) of \(books.count) books. \(failed) failed."
        }
        showingAlert = true
    }
    
    private func unshareAllRecipes() async {
        isSharing = true
        sharingStatus = "Preparing to unshare recipes..."
        
        // Get all active shared recipes for current user
        guard let currentUserID = sharingService.currentUserID else {
            alertMessage = "Not signed in to iCloud"
            showingAlert = true
            isSharing = false
            return
        }
        
        let activeSharedRecipes = sharedRecipes.filter { 
            $0.isActive && $0.sharedByUserID == currentUserID 
        }
        
        let total = activeSharedRecipes.count
        guard total > 0 else {
            alertMessage = "No shared recipes found"
            showingAlert = true
            isSharing = false
            return
        }
        
        AppLog.info("Starting bulk unshare: \(total) recipes", category: .sharing)
        
        var successful = 0
        var failed = 0
        var skipped = 0
        
        // Process in batches for better performance and progress updates
        let batchSize = 10
        let batches = stride(from: 0, to: total, by: batchSize).map { start in
            Array(activeSharedRecipes[start..<min(start + batchSize, total)])
        }
        
        for (batchIndex, batch) in batches.enumerated() {
            // Update progress
            let progress = Int((Double(batchIndex) / Double(batches.count)) * 100)
            sharingStatus = "Unsharing recipes: \(successful + failed + skipped)/\(total) (\(progress)%)"
            
            // Process batch sequentially (CloudKit operations must be sequential)
            for sharedRecipe in batch {
                guard let cloudRecordID = sharedRecipe.cloudRecordID else {
                    sharedRecipe.isActive = false
                    skipped += 1
                    continue
                }
                
                do {
                    try await sharingService.unshareRecipe(
                        cloudRecordID: cloudRecordID,
                        modelContext: modelContext
                    )
                    successful += 1
                } catch {
                    AppLog.error("Failed to unshare: \(error.localizedDescription)", category: .sharing)
                    failed += 1
                }
            }
            
            // Save periodically after each batch
            try? modelContext.save()
        }
        
        isSharing = false
        
        // Build result message
        if failed == 0 && skipped == 0 {
            alertMessage = "Successfully unshared all \(successful) recipes"
        } else {
            var parts: [String] = []
            if successful > 0 {
                parts.append("\(successful) unshared")
            }
            if failed > 0 {
                parts.append("\(failed) failed")
            }
            if skipped > 0 {
                parts.append("\(skipped) skipped")
            }
            alertMessage = "Unshare completed: " + parts.joined(separator: ", ")
        }
        
        AppLog.info("Bulk unshare complete: \(alertMessage)", category: .sharing)
        showingAlert = true
    }
    
    private func unshareAllBooks() async {
        isSharing = true
        sharingStatus = "Preparing to unshare books..."

        guard let currentUserID = sharingService.currentUserID else {
            alertMessage = "Not signed in to iCloud"
            showingAlert = true
            isSharing = false
            return
        }

        let activeSharedBooks = sharedRecipeBooks.filter { $0.isActive && $0.sharedByUserID == currentUserID }
        let total = activeSharedBooks.count

        guard total > 0 else {
            alertMessage = "No shared books found"
            showingAlert = true
            isSharing = false
            return
        }

        var successful = 0
        var failed = 0

        for (index, sharedBook) in activeSharedBooks.enumerated() {
            sharingStatus = "Unsharing books: \(index + 1)/\(total)"
            guard let cloudRecordID = sharedBook.cloudRecordID else {
                sharedBook.isActive = false
                successful += 1
                continue
            }
            do {
                try await sharingService.unshareRecipeBook(cloudRecordID: cloudRecordID, modelContext: modelContext)
                successful += 1
            } catch {
                AppLog.error("Failed to unshare book: \(error.localizedDescription)", category: .sharing)
                failed += 1
            }
        }

        try? modelContext.save()
        isSharing = false

        alertMessage = failed == 0
            ? "Successfully unshared all \(successful) books"
            : "Unshared \(successful) of \(total) books. \(failed) failed."
        showingAlert = true
    }
    
    // MARK: - Meal Sharing Actions

    private func shareAllMeals() async {
        guard !allMeals.isEmpty else { return }

        isSharing = true
        sharingStatus = "Sharing all meals..."

        var successful = 0
        var failed = 0

        for meal in allMeals {
            do {
                _ = try await sharingService.shareMeal(meal, modelContext: modelContext)
                successful += 1
            } catch {
                AppLog.error("Failed to share meal '\(meal.displayName)': \(error)", category: .sharing)
                failed += 1
            }
        }

        isSharing = false

        if failed == 0 {
            alertMessage = "Successfully shared all \(successful) meals"
        } else {
            alertMessage = "Shared \(successful) of \(allMeals.count) meals. \(failed) failed."
        }
        showingAlert = true
    }

    private func unshareAllMeals() async {
        isSharing = true
        sharingStatus = "Preparing to unshare meals..."

        guard let currentUserID = sharingService.currentUserID else {
            alertMessage = "Not signed in to iCloud"
            showingAlert = true
            isSharing = false
            return
        }

        let activeSharedMeals = sharedMeals.filter { $0.isActive && $0.sharedByUserID == currentUserID }
        let total = activeSharedMeals.count

        guard total > 0 else {
            alertMessage = "No shared meals found"
            showingAlert = true
            isSharing = false
            return
        }

        var successful = 0
        var failed = 0

        for sharedMeal in activeSharedMeals {
            guard let cloudRecordID = sharedMeal.cloudRecordID else {
                sharedMeal.isActive = false
                continue
            }
            do {
                try await sharingService.unshareMeal(cloudRecordID: cloudRecordID, modelContext: modelContext)
                successful += 1
            } catch {
                AppLog.error("Failed to unshare meal: \(error.localizedDescription)", category: .sharing)
                failed += 1
            }
        }

        try? modelContext.save()
        isSharing = false

        alertMessage = failed == 0
            ? "Successfully unshared all \(successful) meals"
            : "Unshared \(successful) meals. \(failed) failed."
        showingAlert = true
    }

    // MARK: - Cleanup & Sync Actions

    private func cleanupGhostRecipes() async {
        isSharing = true
        sharingStatus = "Cleaning up ghost recipes..."
        
        do {
            let result = try await sharingService.cleanupGhostRecipes(modelContext: modelContext)
            
            if result.ghostsFound == 0 {
                alertMessage = "✅ No ghost recipes found!\n\nYour CloudKit and local records are perfectly synchronized."
            } else if result.failed == 0 {
                alertMessage = "✅ Ghost Cleanup Complete!\n\nFound: \(result.ghostsFound) ghost recipes\nDeleted: \(result.deleted)\n\nAll orphaned CloudKit records have been removed."
            } else {
                alertMessage = "⚠️ Cleanup Partially Complete\n\nFound: \(result.ghostsFound) ghost recipes\nDeleted: \(result.deleted)\nFailed: \(result.failed)\n\nSome records couldn't be deleted. Try again or check your connection."
            }
            showingAlert = true
        } catch {
            alertMessage = "❌ Cleanup Failed\n\n\(error.localizedDescription)\n\nPlease check your CloudKit connection and try again."
            showingAlert = true
        }
        
        isSharing = false
    }
    
    private func syncLocalTracking() async {
        isSharing = true
        sharingStatus = "Syncing recipe sharing status..."
        
        do {
            try await sharingService.syncLocalTrackingWithCloudKit(modelContext: modelContext)
            alertMessage = "✅ Recipe sharing status synced! Check Console logs for details."
            showingAlert = true
        } catch {
            alertMessage = "Failed to sync recipes: \(error.localizedDescription)"
            showingAlert = true
        }
        
        isSharing = false
    }
    
    private func repairRecipeCloudKitIDs() async {
        isSharing = true
        sharingStatus = "Repairing recipe CloudKit IDs..."
        
        do {
            try await sharingService.repairMissingRecipeCloudKitIDs(modelContext: modelContext)
            alertMessage = "✅ Recipe CloudKit IDs repaired! Check Console logs for details."
            showingAlert = true
        } catch {
            alertMessage = "Failed to repair recipe IDs: \(error.localizedDescription)"
            showingAlert = true
        }
        
        isSharing = false
    }
    
    // MARK: - Recipe Book Cleanup & Sync Actions
    
    private func cleanupGhostRecipeBooks() async {
        isSharing = true
        sharingStatus = "Cleaning up ghost recipe books..."
        
        do {
            let result = try await sharingService.cleanupGhostRecipeBooks(modelContext: modelContext)
            
            if result.ghostsFound == 0 {
                alertMessage = "✅ No ghost recipe books found!\n\nYour CloudKit and local records are perfectly synchronized."
            } else if result.failed == 0 {
                alertMessage = "✅ Ghost Cleanup Complete!\n\nFound: \(result.ghostsFound) ghost books\nDeleted: \(result.deleted)\n\nAll orphaned CloudKit records have been removed."
            } else {
                alertMessage = "⚠️ Cleanup Partially Complete\n\nFound: \(result.ghostsFound) ghost books\nDeleted: \(result.deleted)\nFailed: \(result.failed)\n\nSome records couldn't be deleted. Try again or check your connection."
            }
            showingAlert = true
        } catch {
            alertMessage = "❌ Cleanup Failed\n\n\(error.localizedDescription)\n\nPlease check your CloudKit connection and try again."
            showingAlert = true
        }
        
        isSharing = false
    }
    
    private func syncLocalRecipeBookTracking() async {
        isSharing = true
        sharingStatus = "Syncing recipe book sharing status..."
        
        do {
            try await sharingService.syncLocalRecipeBookTrackingWithCloudKit(modelContext: modelContext)
            alertMessage = "✅ Recipe book sharing status synced! Check Console logs for details."
            showingAlert = true
        } catch {
            alertMessage = "Failed to sync recipe books: \(error.localizedDescription)"
            showingAlert = true
        }
        
        isSharing = false
    }
    
    private func repairRecipeBookCloudKitIDs() async {
        isSharing = true
        sharingStatus = "Repairing recipe book CloudKit IDs..."
        
        do {
            try await sharingService.repairMissingRecipeBookCloudKitIDs(modelContext: modelContext)
            alertMessage = "✅ Recipe book CloudKit IDs repaired! Check Console logs for details."
            showingAlert = true
        } catch {
            alertMessage = "Failed to repair recipe book IDs: \(error.localizedDescription)"
            showingAlert = true
        }
        
        isSharing = false
    }
    
    // MARK: - Community Sync Actions
    
    private func syncCommunityBooks() async {
        isSharing = true
        sharingStatus = "Syncing community books..."
        
        do {
            try await sharingService.syncCommunityBooksToLocal(modelContext: modelContext)
            alertMessage = "✅ Community books synced! Shared books should now appear in the Books view."
            showingAlert = true
        } catch {
            alertMessage = "Failed to sync community books: \(error.localizedDescription)"
            showingAlert = true
        }
        
        isSharing = false
    }
    
    private func syncCommunityRecipes() async {
        isSharing = true
        sharingStatus = "Syncing ALL community recipes..."
        
        do {
            // Fetch all available community recipes using pagination
            try await sharingService.syncCommunityRecipesForViewing(modelContext: modelContext, limit: Int.max)
            alertMessage = "✅ Community recipes synced! All shared recipes are now available for viewing and cooking."
            showingAlert = true
        } catch {
            alertMessage = "Failed to sync community recipes: \(error.localizedDescription)"
            showingAlert = true
        }
        
        isSharing = false
    }
    
    // MARK: - Diagnostic Actions
    
    private func diagnoseSharedBooks() async {
        isSharing = true
        sharingStatus = "Running diagnostics..."
        
        guard let result = await sharingService.diagnoseSharedRecipeBooks(modelContext: modelContext) else {
            alertMessage = "❌ Diagnostic Failed\n\nCould not access CloudKit. Please check your iCloud connection."
            showingAlert = true
            isSharing = false
            return
        }
        
        // Build a comprehensive diagnostic message
        var message = "📊 Recipe Book Diagnostics\n\n"
        
        message += "☁️ CloudKit:\n"
        message += "  Total: \(result.cloudKitBooks)\n"
        message += "  Mine: \(result.myCloudKitBooks)\n"
        message += "  Others: \(result.othersCloudKitBooks)\n\n"
        
        message += "📱 Local Storage:\n"
        message += "  Books: \(result.localBooks)\n"
        message += "  Active Tracking: \(result.activeTracking)\n"
        message += "  Inactive Tracking: \(result.inactiveTracking)\n\n"
        
        // Add warnings/issues
        var issues: [String] = []
        
        if result.duplicateBookIDs > 0 {
            issues.append("⚠️ \(result.duplicateBookIDs) duplicate book IDs in CloudKit")
        }
        
        if result.orphanedBooks > 0 {
            issues.append("⚠️ \(result.orphanedBooks) books without tracking")
        }
        
        if result.othersCloudKitBooks > 0 && result.othersTracking == 0 {
            issues.append("⚠️ Community books not synced locally")
        }
        
        if !issues.isEmpty {
            message += "Issues Found:\n"
            for issue in issues {
                message += "  \(issue)\n"
            }
            message += "\n💡 Run 'Sync Community Books' to fix most issues."
        } else {
            message += "✅ Everything looks good!\nNo issues detected."
        }
        
        alertMessage = message
        showingAlert = true
        isSharing = false
    }
}

// MARK: - Recipe Selector

struct RecipeSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allRecipes: [RecipeX]
    
    @State var selectedRecipes: [RecipeX]
    let onShare: ([RecipeX]) -> Void
    
    var body: some View {
        NavigationView {
            #if os(macOS)
            macOSList
            #else
            iOSList
            #endif
        }
    }
    
    // macOS version with native selection
    #if os(macOS)
    private var macOSList: some View {
        List(allRecipes, selection: $selectedRecipes) { recipe in
            recipeRow(recipe)
        }
        .navigationTitle("Select Recipes")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Share") {
                    onShare(selectedRecipes)
                    dismiss()
                }
                .disabled(selectedRecipes.isEmpty)
            }
        }
    }
    #endif
    
    // iOS version with manual selection
    private var iOSList: some View {
        List(allRecipes) { recipe in
            Button {
                toggleSelection(for: recipe)
            } label: {
                recipeRow(recipe)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Select Recipes")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Share") {
                    onShare(selectedRecipes)
                    dismiss()
                }
                .disabled(selectedRecipes.isEmpty)
            }
        }
    }
    
    @ViewBuilder
    private func recipeRow(_ recipe: RecipeX) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(recipe.safeTitle)
                    .font(.headline)
                
                if let description = recipe.headerNotes {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if selectedRecipes.contains(where: { $0.id == recipe.id }) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appInfo)
            }
        }
    }
    
    private func toggleSelection(for recipe: RecipeX) {
        if let index = selectedRecipes.firstIndex(where: { $0.id == recipe.id }) {
            selectedRecipes.remove(at: index)
        } else {
            selectedRecipes.append(recipe)
        }
    }
}

// MARK: - Book Selector

struct BookSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allBooks: [Book]
    
    @State var selectedBooks: [Book]
    let onShare: ([Book]) -> Void
    
    var body: some View {
        NavigationView {
            #if os(macOS)
            macOSList
            #else
            iOSList
            #endif
        }
    }
    
    // macOS version with native selection
    #if os(macOS)
    private var macOSList: some View {
        List(allBooks, selection: $selectedBooks) { book in
            bookRow(book)
        }
        .navigationTitle("Select Books")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Share") {
                    onShare(selectedBooks)
                    dismiss()
                }
                .disabled(selectedBooks.isEmpty)
            }
        }
    }
    #endif
    
    // iOS version with manual selection
    private var iOSList: some View {
        List(allBooks) { book in
            Button {
                toggleSelection(for: book)
            } label: {
                bookRow(book)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Select Books")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Share") {
                    onShare(selectedBooks)
                    dismiss()
                }
                .disabled(selectedBooks.isEmpty)
            }
        }
    }
    
    @ViewBuilder
    private func bookRow(_ book: Book) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(book.displayName)
                    .font(.headline)
                
                if let description = book.bookDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if selectedBooks.contains(where: { $0.id == book.id }) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appInfo)
            }
        }
    }
    
    private func toggleSelection(for book: Book) {
        if let index = selectedBooks.firstIndex(where: { $0.id == book.id }) {
            selectedBooks.remove(at: index)
        } else {
            selectedBooks.append(book)
        }
    }
}

// MARK: - Manage Shared Content View

struct ManageSharedContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sharingService = CloudKitSharingService.shared
    
    @Query(filter: #Predicate<SharedRecipe> { $0.isActive == true })
    private var allActiveSharedRecipes: [SharedRecipe]
    
    @Query(filter: #Predicate<Book> { $0.isShared == true })
    private var allActiveSharedBooks: [Book]
    
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var itemToUnshare: (id: String, type: UnshareType)?
    
    enum UnshareType {
        case recipe
        case book
    }
    
    // Filter to show only items shared by the current user
    private var activeSharedRecipes: [SharedRecipe] {
        guard let currentUserID = sharingService.currentUserID else {
            AppLog.info("🔍 activeSharedRecipes: No currentUserID yet", category: .sharing)
            return []
        }
        let filtered = allActiveSharedRecipes.filter { $0.sharedByUserID == currentUserID }
        AppLog.info("🔍 activeSharedRecipes: currentUserID=\(currentUserID), total=\(allActiveSharedRecipes.count), filtered=\(filtered.count)", category: .sharing)
        
        // Debug: log all recipes with their sharedByUserID
        for recipe in allActiveSharedRecipes {
            AppLog.info("🔍   Recipe '\(recipe.recipeTitle)': sharedByUserID=\(recipe.sharedByUserID ?? "nil")", category: .sharing)
        }
        
        return filtered
    }
    
    private var activeSharedBooks: [Book] {
        guard let currentUserID = sharingService.currentUserID else {
            AppLog.info("🔍 activeSharedBooks: No currentUserID yet", category: .sharing)
            return []
        }
        let filtered = allActiveSharedBooks.filter { $0.ownerUserID == currentUserID }
        AppLog.info("🔍 activeSharedBooks: currentUserID=\(currentUserID), total=\(allActiveSharedBooks.count), filtered=\(filtered.count)", category: .sharing)
        
        // Debug: log all books with their ownerUserID
        for book in allActiveSharedBooks {
            AppLog.info("🔍   Book '\(book.displayName)': ownerUserID=\(book.ownerUserID ?? "nil")", category: .sharing)
        }
        
        return filtered
    }
    
    var body: some View {
        Group {
            if activeSharedRecipes.isEmpty && activeSharedBooks.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "tray.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("No Shared Content")
                        .font(.headline)
                    
                    if sharingService.currentUserID == nil {
                        Text("Loading your sharing information...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Text("You haven't shared any recipes or books yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        NavigationLink("Share Content") {
                            SharingSettingsView()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !activeSharedRecipes.isEmpty {
                        Section {
                            ForEach(activeSharedRecipes) { sharedRecipe in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(sharedRecipe.recipeTitle)
                                            .font(.headline)
                                        
                                        Text("Shared \(sharedRecipe.sharedDate, style: .date)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        if sharedRecipe.cloudRecordID == nil {
                                            Text("⚠️ No CloudKit ID")
                                                .font(.caption2)
                                                .foregroundStyle(Color.appWarning)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if let cloudRecordID = sharedRecipe.cloudRecordID {
                                        Button(role: .destructive) {
                                            AppLog.info("🗑️ User tapped unshare for recipe: \(sharedRecipe.recipeTitle)", category: .sharing)
                                            itemToUnshare = (cloudRecordID, .recipe)
                                        } label: {
                                            Label("Unshare", systemImage: "xmark.circle.fill")
                                                .labelStyle(.iconOnly)
                                                .foregroundStyle(Color.appCritical)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        // Recipe has no CloudKit ID - show error
                                        Button {
                                            alertMessage = "Cannot unshare '\(sharedRecipe.recipeTitle)': No CloudKit record ID found. Try running 'Sync Recipe Sharing Status' first."
                                            showingAlert = true
                                        } label: {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(Color.appWarning)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if let cloudRecordID = sharedRecipe.cloudRecordID {
                                        Button(role: .destructive) {
                                            AppLog.info("🗑️ User swiped to unshare recipe: \(sharedRecipe.recipeTitle)", category: .sharing)
                                            itemToUnshare = (cloudRecordID, .recipe)
                                        } label: {
                                            Label("Unshare", systemImage: "xmark.circle")
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Shared Recipes")
                        } footer: {
                            Text("Tap the ✕ button or swipe to stop sharing a recipe.")
                        }
                    }
                    
                    if !activeSharedBooks.isEmpty {
                        Section {
                            ForEach(activeSharedBooks) { book in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(book.displayName)
                                            .font(.headline)
                                        
                                        if let description = book.bookDescription {
                                            Text(description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        
                                        if let sharedDate = book.sharedDate {
                                            Text("Shared \(sharedDate, style: .date)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        if book.cloudRecordID == nil {
                                            Text("⚠️ No CloudKit ID")
                                                .font(.caption2)
                                                .foregroundStyle(Color.appWarning)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if let cloudRecordID = book.cloudRecordID {
                                        Button(role: .destructive) {
                                            AppLog.info("🗑️ User tapped unshare for book: \(book.displayName)", category: .sharing)
                                            itemToUnshare = (cloudRecordID, .book)
                                        } label: {
                                            Label("Unshare", systemImage: "xmark.circle.fill")
                                                .labelStyle(.iconOnly)
                                                .foregroundStyle(Color.appCritical)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        // Book has no CloudKit ID - show error
                                        Button {
                                            alertMessage = "Cannot unshare '\(book.displayName)': No CloudKit record ID found. Try running 'Sync Recipe Book Sharing Status' first."
                                            showingAlert = true
                                        } label: {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(Color.appWarning)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if let cloudRecordID = book.cloudRecordID {
                                        Button(role: .destructive) {
                                            AppLog.info("🗑️ User swiped to unshare book: \(book.displayName)", category: .sharing)
                                            itemToUnshare = (cloudRecordID, .book)
                                        } label: {
                                            Label("Unshare", systemImage: "xmark.circle")
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Shared Recipe Books")
                        } footer: {
                            Text("Tap the ✕ button or swipe to stop sharing a recipe book.")
                        }
                    }
                }
            }
        }
        .id(sharingService.currentUserID) // Force view rebuild when user ID changes
        .navigationTitle("My Shared Content")
        .alert("Unshare Content", isPresented: Binding(
            get: { itemToUnshare != nil },
            set: { if !$0 { itemToUnshare = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                AppLog.info("🚫 User cancelled unshare", category: .sharing)
                itemToUnshare = nil
            }
            Button("Unshare", role: .destructive) {
                if let item = itemToUnshare {
                    AppLog.info("✅ User confirmed unshare for \(item.type)", category: .sharing)
                    Task {
                        await unshareItem(cloudRecordID: item.id, type: item.type)
                    }
                } else {
                    AppLog.error("❌ itemToUnshare was nil in alert confirmation", category: .sharing)
                }
            }
        } message: {
            if let item = itemToUnshare {
                Text("This will remove this \(item.type == .recipe ? "recipe" : "recipe book") from the community. You can share it again later.")
            } else {
                Text("This will remove the item from the community.")
            }
        }
        .alert("Status", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }
    
    private func unshareItem(cloudRecordID: String, type: UnshareType) async {
        AppLog.info("🔄 Starting unshare process for \(type): \(cloudRecordID)", category: .sharing)
        
        do {
            switch type {
            case .recipe:
                AppLog.info("🍽️ Calling unshareRecipe...", category: .sharing)
                try await sharingService.unshareRecipe(cloudRecordID: cloudRecordID, modelContext: modelContext)
                alertMessage = "Recipe unshared successfully"
                AppLog.info("✅ Recipe unshared successfully", category: .sharing)
            case .book:
                AppLog.info("📚 Calling unshare book...", category: .sharing)
                // Find the book with this cloudRecordID
                let descriptor = FetchDescriptor<Book>(
                    predicate: #Predicate { $0.cloudRecordID == cloudRecordID }
                )
                if let books = try? modelContext.fetch(descriptor), let book = books.first {
                    // Use BookSyncService to delete the book from CloudKit
                    let syncService = BookSyncService(modelContext: modelContext)
                    try await syncService.deleteBookFromCloud(book)
                    
                    alertMessage = "Recipe book unshared successfully"
                    AppLog.info("✅ Recipe book unshared successfully", category: .sharing)
                } else {
                    throw BookSyncError.bookNotFound
                }
            }
            itemToUnshare = nil
            showingAlert = true
        } catch {
            AppLog.error("❌ Failed to unshare \(type): \(error)", category: .sharing)
            alertMessage = "Failed to unshare: \(error.localizedDescription)"
            itemToUnshare = nil
            showingAlert = true
        }
    }
}

// MARK: - Shared Books Browser

struct SharedBooksBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sharingService = CloudKitSharingService.shared
    
    @State private var sharedBooks: [CloudKitRecipeBook] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var showingBookDetail: CloudKitRecipeBook?
    
    var filteredBooks: [CloudKitRecipeBook] {
        guard !sharedBooks.isEmpty else { return [] }
        
        if searchText.isEmpty {
            return sharedBooks
        }
        
        return sharedBooks.filter { book in
            // Safely access properties with fallbacks
            let name = book.name
            let userName = book.sharedByUserName ?? ""
            let description = book.bookDescription ?? ""
            
            return name.localizedCaseInsensitiveContains(searchText) ||
                   userName.localizedCaseInsensitiveContains(searchText) ||
                   description.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        ZStack {
            Group {
                if isLoading && sharedBooks.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading community recipe books...")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                } else if sharedBooks.isEmpty {
                    ContentUnavailableView(
                        "No Community Recipe Books",
                        systemImage: "books.vertical.fill",
                        description: Text("No recipe books have been shared by the community yet. Be the first to share!")
                    )
                } else {
                    List(filteredBooks) { book in
                        SharedBookRow(book: book) {
                            showingBookDetail = book
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search books or authors")
                    .disabled(isLoading)
                }
            }
            
            // Overlay for refresh operations
            if isLoading && !sharedBooks.isEmpty {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Refreshing...")
                        .font(.headline)
                        .foregroundStyle(Color.onTint)
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
                .shadow(radius: 20)
            }
        }
        .navigationTitle("Browse Community Books")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isLoading {
                ToolbarItem(placement: .platformNavBarTrailing) {
                    Button {
                        Task { await loadBooks() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if !sharedBooks.isEmpty {
                HStack {
                    Image(systemName: "books.vertical.fill")
                        .foregroundStyle(Color.appInfo)
                    Text("\(filteredBooks.count) \(filteredBooks.count == 1 ? "Book" : "Books")")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if searchText.isEmpty && filteredBooks.count != sharedBooks.count {
                        Text("(\(sharedBooks.count) total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !searchText.isEmpty {
                        Text("of \(sharedBooks.count)")
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
        .task {
            await loadBooks()
        }
        .refreshable {
            await loadBooks()
        }
        .sheet(item: $showingBookDetail) { book in
            SharedBookDetailView(book: book)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }
    
    private func loadBooks() async {
        isLoading = true
        errorMessage = nil
        
        do {
            AppLog.info("📚 Starting to fetch shared recipe books...", category: .sharing)
            let books = try await sharingService.fetchSharedRecipeBooks(excludeCurrentUser: true)
            
            await MainActor.run {
                sharedBooks = books
                AppLog.info("📚 Loaded \(books.count) shared books from CloudKit", category: .sharing)
            }
            
            // Automatically sync to local SwiftData so books appear in RecipeBooksView
            do {
                AppLog.info("📚 Starting sync to local SwiftData...", category: .sharing)
                try await sharingService.syncCommunityBooksToLocal(modelContext: modelContext)
                AppLog.info("✅ Successfully synced community books to local SwiftData", category: .sharing)
            } catch {
                AppLog.error("❌ Failed to sync community books to local: \(error)", category: .sharing)
                // Don't show error to user - the browse view still works
            }
        } catch {
            await MainActor.run {
                let errorDetails = "\(error.localizedDescription) [\(type(of: error))]"
                errorMessage = "Failed to load recipe books: \(errorDetails)"
                AppLog.error("❌ Failed to load shared books: \(error)", category: .sharing)
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
}

struct SharedBookRow: View {
    let book: CloudKitRecipeBook
    let onTap: () -> Void
    
    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        if let userName = book.sharedByUserName {
                            Label(userName, systemImage: "person.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack(spacing: 12) {
                            Label("\(book.recipeIDs.count) recipes", systemImage: "book.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            
                            Text("Shared \(book.sharedDate, style: .date)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                if let description = book.bookDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

struct SharedBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let book: CloudKitRecipeBook
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let description = book.bookDescription {
                        Text(description)
                            .font(.body)
                    }
                    
                    if let userName = book.sharedByUserName {
                        LabeledContent("Shared by") {
                            Text(userName)
                        }
                    }
                    
                    LabeledContent("Shared on") {
                        Text(book.sharedDate, style: .date)
                    }
                    
                    LabeledContent("Recipes") {
                        Text("\(book.recipeIDs.count)")
                    }
                } header: {
                    Text("Book Information")
                }
                
                Section {
                    Text("Recipe IDs:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(book.recipeIDs, id: \.self) { recipeID in
                        Text(recipeID.uuidString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Recipes in This Book (\(book.recipeIDs.count))")
                } footer: {
                    Text("To view these recipes, you'll need to import them individually from Browse Community Recipes.")
                }
            }
            .navigationTitle(book.name)
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SharingSettingsView()
            .modelContainer(for: [SharingPreferences.self, SharedRecipe.self, Book.self, RecipeX.self])
    }
}
