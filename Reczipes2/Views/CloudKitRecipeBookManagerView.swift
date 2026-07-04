//
//  CloudKitRecipeBookManagerView.swift
//  Reczipes2
//
//  Created on 1/18/26.
//

import SwiftUI
import SwiftData


struct CloudKitRecipeBookManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sharingService = CloudKitSharingService.shared
    
    @State private var managerData: CloudKitRecipeBookManagerData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentSharingError: SharingError?
    @State private var searchText = ""
    @State private var showingDeleteAllConfirmation = false
    @State private var showingOnboarding = false
    
    var filteredBooks: [CloudKitRecipeBookStatus] {
        guard let data = managerData else { return [] }
        if searchText.isEmpty {
            return data.books
        }
        return data.books.filter { $0.book.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        contentView
            .navigationTitle("My CloudKit Recipe Books")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await loadBooks() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .overlay {
                if isLoading && managerData != nil {
                    loadingOverlay
                }
            }
            .refreshable {
                await loadBooks()
            }
            .alert("Delete All Orphaned Recipe Books?", isPresented: $showingDeleteAllConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task { await deleteAllOrphaned() }
                }
            } message: {
                if let data = managerData {
                    Text("This will permanently delete \(data.orphanedCount) orphaned recipe books from CloudKit. This cannot be undone.")
                }
            }
            .sheet(isPresented: $showingOnboarding) {
                CloudKitOnboardingView()
            }
            .task {
                await loadBooks()
            }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var contentView: some View {
        if isLoading && managerData == nil {
            // Initial loading state
            ProgressView("Loading...")
        } else if let error = currentSharingError {
            // Error state with SharingError
            sharingErrorView(error)
        } else if let error = errorMessage {
            // Error state with generic error
            genericErrorView(error)
        } else if let data = managerData {
            if data.totalCount == 0 {
                emptyStateView
            } else {
                booksList
            }
        } else {
            fallbackView
        }
    }
    
    private var loadingOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ProgressView()
                    .padding()
                    .background(Color.appSystemBackground)
                    .cornerRadius(8)
                    .shadow(radius: 4)
                Spacer()
            }
            Spacer()
        }
    }
    
    private func sharingErrorView(_ error: SharingError) -> some View {
        ContentUnavailableView {
            Label("Failed to Load", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(error.errorDescription ?? "An unknown error occurred")
        } actions: {
            if error.canOpenOnboarding {
                Button("Open Setup & Diagnostics") {
                    showingOnboarding = true
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Try Again") {
                Task { await loadBooks() }
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func genericErrorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Failed to Load", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(error)
        } actions: {
            Button("Try Again") {
                Task { await loadBooks() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Recipe Books in CloudKit",
            systemImage: "books.vertical",
            description: Text("You haven't shared any recipe books yet.")
        )
    }
    
    private var fallbackView: some View {
        ContentUnavailableView(
            "No Data",
            systemImage: "books.vertical",
            description: Text("Unable to load recipe books. Pull to refresh.")
        )
    }
    
    private var booksList: some View {
        List {
            // Status Section
            Section("Status") {
                if let data = managerData {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                        Text("\(data.trackedCount) tracked recipe books")
                    }
                    
                    if data.orphanedCount > 0 {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.appWarning)
                            Text("\(data.orphanedCount) orphaned recipe books")
                        }
                    }
                    
                    HStack {
                        Image(systemName: "cloud.fill")
                            .foregroundStyle(Color.appInfo)
                        Text("\(data.totalCount) total in CloudKit")
                    }
                }
            }
            
            // Tracked Recipe Books
            if let data = managerData, !data.trackedBooks.isEmpty {
                Section {
                    ForEach(data.trackedBooks.filter { book in
                        searchText.isEmpty || book.book.name.localizedCaseInsensitiveContains(searchText)
                    }) { status in
                        RecipeBookStatusRow(
                            status: status,
                            onDelete: { deleteBook(status) },
                            onReTrack: nil
                        )
                    }
                } header: {
                    Label("Tracked Recipe Books", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.appSuccess)
                }
            }
            
            // Orphaned Recipe Books
            if let data = managerData, !data.orphanedBooks.isEmpty {
                Section {
                    ForEach(data.orphanedBooks.filter { book in
                        searchText.isEmpty || book.book.name.localizedCaseInsensitiveContains(searchText)
                    }) { status in
                        RecipeBookStatusRow(
                            status: status,
                            onDelete: { deleteBook(status) },
                            onReTrack: { reTrackBook(status) }
                        )
                    }
                } header: {
                    Label("Orphaned Recipe Books", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.appWarning)
                } footer: {
                    Text("These recipe books exist in CloudKit but aren't tracked locally. They may be from a previous device or installation.")
                }
            }
            
            // Actions
            Section {
                Button {
                    Task { await loadBooks() }
                } label: {
                    Label("Refresh from CloudKit", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
                
                if let data = managerData, data.orphanedCount > 0 {
                    Button(role: .destructive) {
                        showingDeleteAllConfirmation = true
                    } label: {
                        Label("Delete All Orphaned (\(data.orphanedCount))", systemImage: "trash")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search recipe books")
    }
    
    // MARK: - Actions
    
    private func loadBooks() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            currentSharingError = nil
        }
        
        do {
            let data = try await sharingService.fetchMyCloudKitRecipeBooksWithStatus(modelContext: modelContext)
            await MainActor.run {
                managerData = data
                isLoading = false
            }
            print("✅ Successfully loaded \(data.totalCount) recipe books")
        } catch let error as SharingError {
            print("❌ SharingError: \(error)")
            await MainActor.run {
                currentSharingError = error
                isLoading = false
            }
        } catch {
            print("❌ Generic Error: \(error)")
            print("❌ Error type: \(type(of: error))")
            await MainActor.run {
                errorMessage = "Failed to load recipe books: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func deleteBook(_ status: CloudKitRecipeBookStatus) {
        Task {
            await MainActor.run {
                isLoading = true
            }
            
            do {
                try await sharingService.deleteRecipeBookFromCloudKit(cloudRecordID: status.cloudRecordID)
                
                // If there's a tracking record, mark it inactive
                if let tracking = status.localTrackingRecord {
                    await MainActor.run {
                        tracking.isActive = false
                        try? modelContext.save()
                    }
                }
                
                await loadBooks()
            } catch let error as SharingError {
                await MainActor.run {
                    currentSharingError = error
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to delete recipe book: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func reTrackBook(_ status: CloudKitRecipeBookStatus) {
        Task {
            await MainActor.run {
                isLoading = true
            }
            
            do {
                try await MainActor.run {
                    try sharingService.reTrackRecipeBook(
                        book: status.book,
                        cloudRecordID: status.cloudRecordID,
                        modelContext: modelContext
                    )
                }
                await loadBooks()
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to re-track recipe book: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func deleteAllOrphaned() async {
        guard let data = managerData else { return }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            try await sharingService.deleteAllOrphanedRecipeBooks(orphanedStatuses: data.orphanedBooks)
            await loadBooks()
        } catch let error as SharingError {
            await MainActor.run {
                currentSharingError = error
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to delete orphaned recipe books: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

// MARK: - Supporting Views

struct RecipeBookStatusRow: View {
    let status: CloudKitRecipeBookStatus
    let onDelete: () -> Void
    let onReTrack: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: status.statusIcon)
                    .foregroundColor(status.statusColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.book.name)
                        .font(.headline)
                    
                    if let description = status.book.bookDescription, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Text("Delete")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            
            HStack {
                Label("\(status.book.recipeIDs.count) recipes", systemImage: "book.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Shared: \(status.sharedDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Status:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(status.statusDescription)
                    .font(.caption)
                    .foregroundColor(status.statusColor)
            }
            
            if let onReTrack = onReTrack {
                Button {
                    onReTrack()
                } label: {
                    Label("Re-Track This Recipe Book", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        CloudKitRecipeBookManagerView()
    }
}
