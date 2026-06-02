//
//  BatchRecipeExtractorView.swift
//  Reczipes2
//
//  Created for batch recipe extraction UI
//

import SwiftUI
import SwiftData

/// UI for managing batch recipe extraction from saved links
struct BatchRecipeExtractorView: View {
    @StateObject private var viewModel: BatchRecipeExtractorViewModel
    @State private var keepAwakeManager = KeepAwakeManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedLink.dateAdded, order: .reverse) private var allLinks: [SavedLink]
    
    @State private var showingCompletionAlert = false
    @State private var showingImportSheet = false
    @State private var importResultMessage: String?
    @State private var showingImportResult = false
    
    init(apiKey: String, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: BatchRecipeExtractorViewModel(apiKey: apiKey, modelContext: modelContext))
    }
    
    var unprocessedLinks: [SavedLink] {
        allLinks.filter { !$0.isProcessed }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if unprocessedLinks.isEmpty {
                    emptyStateView
                } else {
                    mainContentView
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
            .alert("Import Complete", isPresented: $showingImportResult) {
                Button("OK") { }
            } message: {
                if let message = importResultMessage {
                    Text(message)
                }
            }
            .navigationTitle("Batch Extract")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if viewModel.isExtracting {
                            viewModel.stop()
                        }
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImportSheet = true
                    } label: {
                        Label("Import Links", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .alert("Batch Extraction Complete", isPresented: $showingCompletionAlert) {
                Button("View Recipes") {
                    dismiss()
                }
                Button("OK", role: .cancel) {
                    viewModel.reset()
                }
            } message: {
                Text("Extracted \(viewModel.successCount) recipe\(viewModel.successCount == 1 ? "" : "s") successfully\(viewModel.failureCount > 0 ? " with \(viewModel.failureCount) failure\(viewModel.failureCount == 1 ? "" : "s")" : "").")
            }
            .onChange(of: viewModel.isExtracting) { oldValue, newValue in
                // Automatically enable keep awake during batch extraction
                if newValue {
                    AppLog.info("Batch URL extraction started - enabling keep awake", category: .batch)
                    keepAwakeManager.enable()
                } else if oldValue {
                    AppLog.info("Batch URL extraction ended - disabling keep awake", category: .batch)
                    keepAwakeManager.disable()
                }
            }
            .onDisappear {
                // Disable keep awake when view disappears if extraction is not running
                if !viewModel.isExtracting {
                    keepAwakeManager.disable()
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("No Saved Links")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Import recipe links from your JSON file, then extract them all at once.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Import button
            Button {
                showingImportSheet = true
            } label: {
                Label("Import Links from JSON", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
        }
        .padding()
    }
    
    // MARK: - Main Content
    
    private var mainContentView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Status Overview Card
                statusOverviewCard
                
                // Current Extraction Progress (when extracting)
                if viewModel.isExtracting {
                    currentExtractionCard
                }
                
                // Control Buttons
                if !viewModel.isExtracting {
                    startButton
                } else {
                    controlButtons
                }
                
                // Links Preview
                linksPreviewSection
                
                // Error Log (if any errors)
                if !viewModel.errorLog.isEmpty {
                    errorLogSection
                }
            }
            .padding()
        }
        .onChange(of: viewModel.isExtracting) { _, isExtracting in
            // Show completion alert when extraction finishes
            if !isExtracting && viewModel.currentProgress > 0 {
                showingCompletionAlert = true
            }
        }
    }
    
    // MARK: - Status Overview
    
    private var statusOverviewCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.title)
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Batch Extraction")
                        .font(.headline)
                    Text("\(unprocessedLinks.count) link\(unprocessedLinks.count == 1 ? "" : "s") ready to extract")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if viewModel.isExtracting {
                Divider()
                
                // Progress stats
                HStack(spacing: 20) {
                    statItem(
                        label: "Progress",
                        value: "\(viewModel.currentProgress)/\(viewModel.totalToExtract)",
                        color: .blue
                    )
                    
                    statItem(
                        label: "Success",
                        value: "\(viewModel.successCount)",
                        color: .green
                    )
                    
                    if viewModel.failureCount > 0 {
                        statItem(
                            label: "Failed",
                            value: "\(viewModel.failureCount)",
                            color: .red
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
    
    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Current Extraction
    
    private var currentExtractionCard: some View {
        VStack(spacing: 12) {
            if let link = viewModel.currentLink {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extracting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(link.title)
                            .font(.headline)
                            .lineLimit(2)
                        
                        Text(link.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
            }
            
            // Progress bar
            ProgressView(value: Double(viewModel.currentProgress), total: Double(viewModel.totalToExtract))
                .progressViewStyle(.linear)
                .tint(.purple)
            
            // Status text
            Text(viewModel.currentStatus)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Current recipe preview (if available)
            if let recipe = viewModel.currentRecipe {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Extracted: \(String(describing: recipe.title))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    if !recipe.ingredientSections.isEmpty {
                        Text("✓ \(recipe.ingredientSections.count) ingredient section\(recipe.ingredientSections.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if !recipe.instructionSections.isEmpty {
                        Text("✓ \(recipe.instructionSections.count) instruction section\(recipe.instructionSections.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Control Buttons
    
    private var startButton: some View {
        Button {
            viewModel.startBatchExtraction(links: allLinks)
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("Start Batch Extraction")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.purple)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(unprocessedLinks.isEmpty)
    }
    
    private var controlButtons: some View {
        HStack(spacing: 12) {
            // Pause/Resume button
            Button {
                if viewModel.isPaused {
                    viewModel.resume()
                } else {
                    viewModel.pause()
                }
            } label: {
                HStack {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                    Text(viewModel.isPaused ? "Resume" : "Pause")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.isPaused ? Color.green : Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            // Stop button
            Button {
                viewModel.stop()
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Links Preview
    
    private var linksPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved Links (\(unprocessedLinks.count) unprocessed)")
                .font(.headline)
            
            if unprocessedLinks.isEmpty {
                Text("All links have been processed!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(unprocessedLinks.prefix(5)) { link in
                        linkPreviewRow(link: link)
                    }
                    
                    if unprocessedLinks.count > 5 {
                        Text("... and \(unprocessedLinks.count - 5) more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
    
    private func linkPreviewRow(link: SavedLink) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "link.circle.fill")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(link.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Processing indicator
            if link.id == viewModel.currentLink?.id && viewModel.isExtracting {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(8)
        .background(link.id == viewModel.currentLink?.id ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - Error Log
    
    private var errorLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Errors (\(viewModel.errorLog.count))")
                    .font(.headline)
            }
            
            VStack(spacing: 8) {
                ForEach(viewModel.errorLog.indices, id: \.self) { index in
                    let error = viewModel.errorLog[index]
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error.link)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text(error.error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BatchRecipeExtractorView(
            apiKey: "test-api-key",
            modelContext: ModelContext(try! ModelContainer(for: SavedLink.self, RecipeX.self, VersionHistoryRecord.self))
        )
    }
}
