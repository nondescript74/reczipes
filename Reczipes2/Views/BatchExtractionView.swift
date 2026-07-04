//
//  BatchExtractionView.swift
//  Reczipes2
//
//  Created for automated batch recipe extraction UI
//

import SwiftUI
import SwiftData

struct BatchExtractionView: View {
    let links: [SavedLink]
    let apiKey: String
    let onComplete: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var manager = BatchExtractionManager.shared
    @State private var showingStopConfirmation = false
    @State private var showingErrorLog = false
    
    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("Batch Extract Recipes")
                .platformNavigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(manager.isExtracting ? "Close" : "Done") {
                            if manager.isExtracting {
                                // Just dismiss - extraction continues in background
                                dismiss()
                                onComplete()
                            } else {
                                dismiss()
                                onComplete()
                            }
                        }
                    }
                }
                .onAppear {
                    // Configure the manager
                    manager.configure(apiKey: apiKey, modelContext: modelContext)
                }
                .alert("Stop Extraction?", isPresented: $showingStopConfirmation) {
                    Button("Continue", role: .cancel) { }
                    Button("Stop", role: .destructive) {
                        manager.stop()
                    }
                } message: {
                    Text("This will stop the batch extraction. Progress will be saved, but unprocessed links will remain.")
                }
                .sheet(isPresented: $showingErrorLog) {
                    errorLogSheet
                }
        }
    }
    
    // MARK: - Main Content View
    
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                if !manager.isExtracting {
                    headerSection
                }
                
                // Detailed Progress Section
                if manager.isExtracting, let status = manager.currentStatus {
                    detailedProgressSection(status: status)
                }
                
                // Current Recipe Preview
                if let recipe = manager.currentRecipe {
                    currentRecipePreview(recipe)
                }
                
                // Recently Extracted Recipes
                if !manager.recentlyExtracted.isEmpty {
                    recentlyExtractedSection
                }
                
                // Stats Section
                statsSection
                
                // Control Buttons
                controlButtonsSection
                
                // Error Log Button
                if !manager.errorLog.isEmpty {
                    errorLogButton
                }
            }
            .padding()
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.appInfo)
            
            Text("Automated Recipe Extraction")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Recipes will be extracted automatically with a 5-second interval between each extraction")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Show batch limit info
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                Text("Maximum 50 recipes per batch")
                    .font(.caption)
            }
            .foregroundStyle(Color.appWarning)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .adaptiveToneBackground(.warning, baseOpacity: 0.15)
            .clipShape(Capsule())
        }
    }
    
    private func detailedProgressSection(status: ExtractionStatus) -> some View {
        VStack(spacing: 16) {
            // Main Progress Bar
            VStack(spacing: 8) {
                HStack {
                    Text("Overall Progress")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(status.currentIndex) of \(status.totalCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                ProgressView(
                    value: Double(status.currentIndex),
                    total: Double(status.totalCount)
                )
                .progressViewStyle(.linear)
                .tint(.blue)
                
                HStack {
                    Text("\(Int((Double(status.currentIndex) / Double(status.totalCount)) * 100))%")
                        .font(.caption)
                        .foregroundStyle(Color.appInfo)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    if let estimatedTime = status.estimatedTimeRemaining {
                        Text("~\(formatTimeRemaining(estimatedTime)) remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Divider()
            
            // Current Step Progress
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: stepIcon(for: status.currentStep))
                        .foregroundStyle(stepColor(for: status.currentStep))
                    Text(status.currentStep.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
                
                if status.totalImages > 0 {
                    HStack {
                        Image(systemName: "photo.stack")
                            .font(.caption)
                        Text("Images: \(status.imagesDownloaded)/\(status.totalImages)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                ProgressView(value: status.stepProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(stepColor(for: status.currentStep))
            }
            
            Divider()
            
            // Current Link Info
            if let currentLink = status.currentLink {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Currently Extracting:", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(currentLink.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    
                    Text(currentLink.url)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Time Stats
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Elapsed Time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatTimeElapsed(status.timeElapsed))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Avg. per Recipe")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if status.currentIndex > 0 {
                        Text(formatTimeElapsed(status.timeElapsed / Double(status.currentIndex)))
                            .font(.caption)
                            .fontWeight(.semibold)
                    } else {
                        Text("--")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color.appGray6)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var recentlyExtractedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Extracted")
                .font(.headline)
            
            ForEach(manager.recentlyExtracted.prefix(5), id: \.id) { recipe in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appSuccess)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.title ?? "Unknown Recipe")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        if let yield = recipe.yield {
                            Text(yield)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color.green.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color.appGray6)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func currentRecipePreview(_ recipe: RecipeX) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appSuccess)
                Text("Recipe Extracted")
                    .font(.headline)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.title ?? "untitled")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                if let yield = recipe.recipeYield {
                    HStack {
                        Image(systemName: "person.2")
                            .font(.caption)
                        Text(yield)
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 16) {
                    if !recipe.ingredientSections.isEmpty {
                        Label("\(recipe.ingredientSections.count) section(s)", systemImage: "list.bullet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if recipe.imageCount > 0 {
                        Label("\(recipe.imageCount) image(s)", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var statsSection: some View {
        HStack(spacing: 20) {
            if manager.isExtracting, let status = manager.currentStatus {
                BatchStatBadge(
                    label: "Remaining",
                    value: status.totalCount - status.currentIndex,
                    color: .blue,
                    icon: "clock"
                )
            }
            
            BatchStatBadge(
                label: "Success",
                value: manager.successCount,
                color: .green,
                icon: "checkmark.circle"
            )
            
            if manager.failureCount > 0 {
                BatchStatBadge(
                    label: "Failed",
                    value: manager.failureCount,
                    color: .red,
                    icon: "xmark.circle"
                )
            }
        }
        .padding()
        .background(Color.appGray6)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var controlButtonsSection: some View {
        VStack(spacing: 12) {
            if !manager.isExtracting {
                // Show count info
                let unprocessedCount = links.filter { !$0.isProcessed }.count
                let willProcess = min(unprocessedCount, 50)
                
                if unprocessedCount > 50 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                        Text("Will extract \(willProcess) of \(unprocessedCount) unprocessed recipes")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.appWarning)
                    .padding(.vertical, 8)
                }
                
                // Start Button
                Button {
                    manager.startBatchExtraction(links: links)
                    // Dismiss the sheet when extraction starts
                    dismiss()
                } label: {
                    Label("Start Batch Extraction", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AdaptiveToneSolidFill(tone: .info))
                        .foregroundStyle(Color.onTint)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(links.filter { !$0.isProcessed }.isEmpty)
            } else {
                // Pause/Resume Button
                Button {
                    if manager.isPaused {
                        manager.resume()
                    } else {
                        manager.pause()
                    }
                } label: {
                    Label(
                        manager.isPaused ? "Resume" : "Pause",
                        systemImage: manager.isPaused ? "play.fill" : "pause.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(manager.isPaused ? Color.green : Color.orange)
                    .foregroundStyle(Color.onTint)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                
                // Stop Button
                Button {
                    showingStopConfirmation = true
                } label: {
                    Label("Stop Extraction", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AdaptiveToneSolidFill(tone: .critical))
                        .foregroundStyle(Color.onTint)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var errorLogButton: some View {
        Button {
            showingErrorLog = true
        } label: {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.appCritical)
                Text("View Error Log (\(manager.errorLog.count))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .adaptiveToneBackground(.critical, baseOpacity: 0.1)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    private var errorLogSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(manager.errorLog.enumerated()), id: \.offset) { _, error in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error.link)
                            .font(.headline)
                        Text(error.error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(error.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Extraction Errors")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingErrorLog = false
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func stepIcon(for step: ExtractionStep) -> String {
        switch step {
        case .fetching: return "network"
        case .analyzing: return "brain"
        case .downloadingImages: return "arrow.down.circle"
        case .savingRecipe: return "square.and.arrow.down"
        case .waiting: return "clock"
        case .complete: return "checkmark.circle"
        case .failed: return "xmark.circle"
        }
    }
    
    private func stepColor(for step: ExtractionStep) -> Color {
        switch step {
        case .fetching, .analyzing: return .blue
        case .downloadingImages: return .purple
        case .savingRecipe: return .green
        case .waiting: return .orange
        case .complete: return .green
        case .failed: return .red
        }
    }
    
    private func formatTimeElapsed(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        } else {
            return "\(remainingSeconds)s"
        }
    }
    
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        } else {
            return "\(remainingSeconds)s"
        }
    }
}

// MARK: - Batch Stat Badge Component

struct BatchStatBadge: View {
    let label: String
    let value: Int
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text("\(value)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(color)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SavedLink.self, configurations: config)
    let context = ModelContext(container)
    
    // Create sample links
    let link1 = SavedLink(title: "Chocolate Chip Cookies", url: "https://example.com/recipe1")
    let link2 = SavedLink(title: "Banana Bread", url: "https://example.com/recipe2")
    let link3 = SavedLink(title: "Apple Pie", url: "https://example.com/recipe3")
    
    context.insert(link1)
    context.insert(link2)
    context.insert(link3)
    
    return BatchExtractionView(
        links: [link1, link2, link3],
        apiKey: "test-key",
        onComplete: {}
    )
    .modelContainer(container)
}
