//
//  SavedLinksView.swift
//  Reczipes2
//
//  Created for managing and extracting recipes from saved links
//

import SwiftUI
import SwiftData
import Combine

struct SavedLinksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedLink.dateAdded, order: .reverse) private var savedLinks: [SavedLink]
    
    @State private var showingImportSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var importResultMessage: String?
    @State private var showingImportResult = false
    @State private var selectedLink: SavedLink?
    @State private var showingExtractor = false
    @State private var showingBatchExtractor = false
    @State private var searchText = ""
    @State private var filterOption: FilterOption = .all
    #if DEBUG
    @State private var showingValidationDebug = false
    #endif
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case unprocessed = "To Extract"
        case processed = "Extracted"
        case failed = "Failed"
    }
    
    private var filteredLinks: [SavedLink] {
        var links = savedLinks
        
        // Apply search filter
        if !searchText.isEmpty {
            links = links.filter { link in
                link.title.localizedCaseInsensitiveContains(searchText) ||
                link.url.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply status filter
        switch filterOption {
        case .all:
            break
        case .unprocessed:
            links = links.filter { !$0.isProcessed }
        case .processed:
            links = links.filter { $0.isProcessed && $0.extractedRecipeID != nil }
        case .failed:
            links = links.filter { $0.isProcessed && $0.processingError != nil }
        }
        
        return links
    }
    
    private var stats: (total: Int, unprocessed: Int, processed: Int, failed: Int) {
        let total = savedLinks.count
        let unprocessed = savedLinks.filter { !$0.isProcessed }.count
        let processed = savedLinks.filter { $0.isProcessed && $0.extractedRecipeID != nil }.count
        let failed = savedLinks.filter { $0.isProcessed && $0.processingError != nil }.count
        return (total, unprocessed, processed, failed)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Stats bar
                statsBar
                
                // Filter picker
                Picker("Filter", selection: $filterOption) {
                    ForEach(FilterOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                if filteredLinks.isEmpty {
                    emptyStateView
                } else {
                    linksList
                }
            }
            .navigationTitle("Saved Recipe Links")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search links")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    CloudKitSyncBadge()
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingImportSheet = true
                        } label: {
                            Label("Import from JSON", systemImage: "square.and.arrow.down")
                        }
                        
                        Divider()
                        
                        Button {
                            showingBatchExtractor = true
                        } label: {
                            Label("Batch Extract All Unprocessed", systemImage: "arrow.down.circle.fill")
                        }
                        .disabled(stats.unprocessed == 0 || APIKeyHelper.getAPIKey() == nil)
                        
                        Button {
                            extractAllUnprocessed()
                        } label: {
                            Label("Extract All (Legacy)", systemImage: "arrow.down.circle")
                        }
                        .disabled(true)  // Not implemented - grayed out
                        
                        #if DEBUG
                        Divider()
                        
                        Button {
                            showingValidationDebug = true
                        } label: {
                            Label("Validation Tools", systemImage: "hammer.fill")
                        }
                        #endif
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Clear All Links", systemImage: "trash")
                        }
                        .disabled(savedLinks.isEmpty)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportLinksSheet(
                    onImportComplete: { count in
                        importResultMessage = "Successfully imported \(count) new link(s)"
                        showingImportResult = true
                    }
                )
            }
            #if DEBUG
            .sheet(isPresented: $showingValidationDebug) {
                LinkValidationDebugView()
            }
            #endif
            .sheet(item: $selectedLink) { link in
                if let apiKey = APIKeyHelper.getAPIKey() {
                    LinkExtractionView(
                        link: link,
                        apiKey: apiKey,
                        onExtractionComplete: { success, error in
                            handleExtractionComplete(for: link, success: success, error: error)
                        }
                    )
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "key.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("API Key Required")
                            .font(.headline)
                        Text("Please configure your Claude API key in Settings")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Dismiss") {
                            selectedLink = nil
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showingBatchExtractor) {
                if let apiKey = APIKeyHelper.getAPIKey() {
                    BatchExtractionView(
                        links: savedLinks,
                        apiKey: apiKey,
                        onComplete: {
                            // Refresh or show completion message
                            importResultMessage = "Batch extraction completed"
                            showingImportResult = true
                        }
                    )
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "key.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("API Key Required")
                            .font(.headline)
                        Text("Please configure your Claude API key in Settings to use batch extraction")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Dismiss") {
                            showingBatchExtractor = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .alert("Import Complete", isPresented: $showingImportResult) {
                Button("OK") { }
            } message: {
                if let message = importResultMessage {
                    Text(message)
                }
            }
            .alert("Clear All Links?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    clearAllLinks()
                }
            } message: {
                Text("This will delete all \(savedLinks.count) saved links. Extracted recipes will not be affected.")
            }
        }
    }
    
    // MARK: - View Components
    
    private var statsBar: some View {
        HStack(spacing: 20) {
            LinkStatBadge(label: "Total", value: stats.total, color: .blue)
            LinkStatBadge(label: "To Extract", value: stats.unprocessed, color: .orange)
            LinkStatBadge(label: "Extracted", value: stats.processed, color: .green)
            if stats.failed > 0 {
                LinkStatBadge(label: "Failed", value: stats.failed, color: .red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Links", systemImage: "link.circle")
        } description: {
            if searchText.isEmpty && filterOption == .all {
                Text("Import recipe links from your JSON file to get started")
            } else {
                Text("No links match your search or filter")
            }
        } actions: {
            if searchText.isEmpty && filterOption == .all {
                Button {
                    showingImportSheet = true
                } label: {
                    Label("Import Links", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var linksList: some View {
        List {
            ForEach(filteredLinks) { link in
                LinkRow(link: link)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedLink = link
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteLink(link)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if !link.isProcessed {
                            Button {
                                selectedLink = link
                            } label: {
                                Label("Extract", systemImage: "arrow.down.circle")
                            }
                            .tint(.blue)
                        }
                    }
                    .contextMenu {
                        Button {
                            selectedLink = link
                        } label: {
                            Label("Extract Recipe", systemImage: "arrow.down.circle")
                        }
                        
                        Button {
                            if let url = URL(string: link.url) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open in Browser", systemImage: "safari")
                        }
                        
                        Button {
                            UIPasteboard.general.string = link.url
                        } label: {
                            Label("Copy URL", systemImage: "doc.on.doc")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            deleteLink(link)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }
    
    // MARK: - Actions
    
    private func deleteLink(_ link: SavedLink) {
        withAnimation {
            modelContext.delete(link)
            do {
                try modelContext.save()
            } catch {
                AppLog.error("Failed to delete link: \(error)", category: .storage)
            }
        }
    }
    
    private func clearAllLinks() {
        do {
            try LinkImportService.clearAllLinks(from: modelContext)
        } catch {
            AppLog.error("Failed to clear links: \(error)", category: .storage)
        }
    }
    
    private func extractAllUnprocessed() {
        // TODO: Implement batch extraction
        // This would process all unprocessed links sequentially
        AppLog.info("Batch extraction not yet implemented", category: .extraction)
    }
    
    private func handleExtractionComplete(for link: SavedLink, success: Bool, error: String?) {
        link.isProcessed = true
        if let error = error {
            link.processingError = error
        }
        
        do {
            try modelContext.save()
        } catch {
            AppLog.error("Failed to save link status: \(error)", category: .storage)
        }
    }
}

// MARK: - Supporting Views

struct LinkStatBadge: View {
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LinkRow: View {
    let link: SavedLink
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(link.title)
                    .font(.headline)
                    .lineLimit(2)
                
                Spacer()
                
                statusBadge
            }
            
            Text(link.url)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            if let error = link.processingError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if link.isProcessed {
            if link.extractedRecipeID != nil {
                Label("Extracted", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else if link.processingError != nil {
                Label("Failed", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        } else {
            Label("To Extract", systemImage: "clock")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }
}

struct ImportLinksSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let onImportComplete: (Int) -> Void
    
    @State private var isImporting = false
    @State private var isValidating = false
    @State private var importError: String?
    @State private var validationResult: JSONLinkValidator.ValidationResult?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    VStack(spacing: 8) {
                        Text("Import Recipe Links")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Import links from 'links_from_notes.json' in your app bundle")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Validation results
                    if let result = validationResult {
                        validationSummaryView(result)
                    }
                    
                    if let error = importError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    // Action button
                    Button {
                        if validationResult == nil {
                            performValidation()
                        } else {
                            performImport()
                        }
                    } label: {
                        if isValidating {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                Text("Validating...")
                            }
                        } else if isImporting {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                Text("Importing...")
                            }
                        } else {
                            Label(
                                validationResult == nil ? "Validate File" : "Import Links",
                                systemImage: validationResult == nil ? "checkmark.shield" : "square.and.arrow.down"
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isImporting || isValidating || (validationResult != nil && !validationResult!.isValid))
                    .controlSize(.large)
                    
                    if validationResult == nil {
                        Text("First, we'll validate the file for errors")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if validationResult?.isValid == true {
                        Text("Duplicate links will be skipped automatically")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Import Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isImporting || isValidating)
                }
            }
        }
    }
    
    // MARK: - Validation Summary View
    
    @ViewBuilder
    private func validationSummaryView(_ result: JSONLinkValidator.ValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.isValid ? .green : .red)
                    .font(.title3)
                Text(result.isValid ? "File Validated Successfully" : "Validation Failed")
                    .font(.headline)
            }
            
            HStack {
                Label("\(result.linkCount) link(s)", systemImage: "link")
                    .font(.subheadline)
                
                if !result.duplicateURLs.isEmpty {
                    Spacer()
                    Label("\(result.duplicateURLs.count) duplicate(s)", systemImage: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            if !result.warnings.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(result.warnings.count) Warning(s)", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    
                    ForEach(result.warnings.prefix(3), id: \.self) { warning in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                            Text(warning)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if result.warnings.count > 3 {
                        Text("... and \(result.warnings.count - 3) more warning(s)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
            
            if !result.errors.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(result.errors.count) Error(s)", systemImage: "xmark.octagon")
                        .font(.subheadline)
                        .foregroundColor(.red)
                    
                    ForEach(result.errors.prefix(3), id: \.self) { error in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if result.errors.count > 3 {
                        Text("... and \(result.errors.count - 3) more error(s)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            result.isValid ? Color.green.opacity(0.1) : Color.red.opacity(0.1)
        )
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func performValidation() {
        isValidating = true
        importError = nil
        
        Task {
            do {
                guard let url = Bundle.main.url(
                    forResource: "links_from_notes",
                    withExtension: "json"
                ) else {
                    throw LinkImportError.fileNotFound
                }
                
                // Read and sanitize before validating (strips trailing commas etc.)
                let rawData = try Data(contentsOf: url)
                let sanitizedData = LinkImportService.sanitizeJSON(rawData)
                let result = JSONLinkValidator.validate(data: sanitizedData)
                
                await MainActor.run {
                    validationResult = result
                    isValidating = false
                    
                    if !result.isValid {
                        importError = "Cannot import: file has \(result.errors.count) error(s)"
                    }
                    
                    AppLog.info("Validation complete: \(result.linkCount) links, \(result.errors.count) errors, \(result.warnings.count) warnings", category: .batch)
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    importError = error.localizedDescription
                    AppLog.error("Validation failed: \(error)", category: .batch)
                }
            }
        }
    }
    
    private func performImport() {
        isImporting = true
        importError = nil
        
        Task {
            do {
                let count = try await LinkImportService.importLinksFromBundle(
                    filename: "links_from_notes.json",
                    into: modelContext,
                    validate: true  // Use validation during import
                )
                
                await MainActor.run {
                    dismiss()
                    onImportComplete(count)
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importError = error.localizedDescription
                    AppLog.error("Import failed: \(error)", category: .batch)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SavedLinksView()
        .modelContainer(for: [SavedLink.self, RecipeX.self], inMemory: true)
}
