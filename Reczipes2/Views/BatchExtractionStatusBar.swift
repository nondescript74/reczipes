//
//  BatchExtractionStatusBar.swift
//  Reczipes2
//
//  Created for global batch extraction status display
//

import SwiftUI

/// Global status bar that appears at the top of any view during batch extraction
struct BatchExtractionStatusBar: View {
    @ObservedObject var manager: BatchExtractionManager
    @State private var keepAwakeManager = KeepAwakeManager.shared
    @State private var showingDetails = false
    @State private var showingCancelConfirmation = false
    
    var body: some View {
        if manager.isExtracting {
            VStack(spacing: 0) {
                Button {
                    showingDetails = true
                } label: {
                    HStack(spacing: 12) {
                        // Animated progress indicator
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 20, height: 20)
                        
                        // Status text
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Extracting Recipes")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                // Keep awake indicator
                                if keepAwakeManager.isKeepAwakeEnabled {
                                    Image(systemName: "moon.zzz.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color.appInfo)
                                }
                            }
                            
                            if let status = manager.currentStatus {
                                HStack(spacing: 4) {
                                    Text("\(status.currentIndex)/\(status.totalCount)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text("\(manager.successCount) succeeded")
                                        .font(.caption)
                                        .foregroundStyle(Color.appSuccess)
                                    
                                    if manager.failureCount > 0 {
                                        Text("•")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Text("\(manager.failureCount) failed")
                                            .font(.caption)
                                            .foregroundStyle(Color.appCritical)
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Progress percentage
                        if let status = manager.currentStatus {
                            let percentage = Int((Double(status.currentIndex) / Double(status.totalCount)) * 100)
                            Text("\(percentage)%")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appInfo)
                                .frame(width: 40, alignment: .trailing)
                        }
                        
                        // Cancel button
                        Button {
                            showingCancelConfirmation = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.appSystemBackground)
                }
                .buttonStyle(.plain)
                
                // Progress bar
                if let status = manager.currentStatus {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * (Double(status.currentIndex) / Double(status.totalCount)))
                            .frame(height: 3)
                    }
                    .frame(height: 3)
                }
            }
            .background(
                Color.appSystemBackground
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .sheet(isPresented: $showingDetails) {
                BatchExtractionDetailsSheet(manager: manager)
            }
            .alert("Cancel Extraction?", isPresented: $showingCancelConfirmation) {
                Button("Continue", role: .cancel) { }
                Button("Stop Extraction", role: .destructive) {
                    manager.stop()
                }
            } message: {
                Text("This will stop the batch extraction. Progress will be saved, but unprocessed links will remain.")
            }
        }
    }
}

/// Detailed extraction sheet shown when tapping the status bar
struct BatchExtractionDetailsSheet: View {
    @ObservedObject var manager: BatchExtractionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingStopConfirmation = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Overall Progress
                    if let status = manager.currentStatus {
                        overallProgressSection(status: status)
                    }
                    
                    // Current Recipe
                    if let recipe = manager.currentRecipe {
                        currentRecipeSection(recipe: recipe)
                    }
                    
                    // Recently Extracted
                    if !manager.recentlyExtracted.isEmpty {
                        recentlyExtractedSection
                    }
                    
                    // Statistics
                    statisticsSection
                    
                    // Error Log
                    if !manager.errorLog.isEmpty {
                        errorLogSection
                    }
                }
                .padding()
            }
            .navigationTitle("Batch Extraction Progress")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if manager.isPaused {
                        Button("Resume") {
                            manager.resume()
                        }
                    } else {
                        Button("Pause") {
                            manager.pause()
                        }
                    }
                }
                
                ToolbarItem(placement: .destructiveAction) {
                    Button("Stop", role: .destructive) {
                        showingStopConfirmation = true
                    }
                }
            }
            .alert("Stop Extraction?", isPresented: $showingStopConfirmation) {
                Button("Continue", role: .cancel) { }
                Button("Stop", role: .destructive) {
                    manager.stop()
                    dismiss()
                }
            } message: {
                Text("This will stop the batch extraction. Progress will be saved, but unprocessed links will remain.")
            }
        }
    }
    
    private func overallProgressSection(status: ExtractionStatus) -> some View {
        VStack(spacing: 12) {
            // Progress bar
            HStack {
                Text("Progress")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(status.currentIndex) of \(status.totalCount)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: Double(status.currentIndex), total: Double(status.totalCount))
                .tint(.blue)
            
            // Current step
            HStack {
                Image(systemName: stepIcon(for: status.currentStep))
                    .foregroundColor(stepColor(for: status.currentStep))
                Text(status.currentStep.rawValue)
                    .font(.caption)
                Spacer()
            }
            
            // Time info
            if status.currentIndex > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Elapsed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatTime(status.timeElapsed))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    if let remaining = status.estimatedTimeRemaining {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Remaining")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("~\(formatTime(remaining))")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.appGray6)
        .cornerRadius(12)
    }
    
    private func currentRecipeSection(recipe: RecipeX) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Recipe")
                .font(.headline)
            
            HStack {
                Image(systemName: "book.fill")
                    .foregroundStyle(Color.appInfo)
                Text(recipe.title ?? "untitled")
                    .font(.subheadline)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var recentlyExtractedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Extracted")
                .font(.headline)
            
            ForEach(manager.recentlyExtracted.prefix(5), id: \.id) { recipe in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appSuccess)
                    Text(recipe.title ?? "untitled")
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.appGray6)
        .cornerRadius(12)
    }
    
    private var statisticsSection: some View {
        HStack(spacing: 16) {
            StatCard(
                icon: "checkmark.circle.fill",
                color: .green,
                value: manager.successCount,
                label: "Succeeded"
            )
            
            if manager.failureCount > 0 {
                StatCard(
                    icon: "xmark.circle.fill",
                    color: .red,
                    value: manager.failureCount,
                    label: "Failed"
                )
            }
        }
        .padding()
        .background(Color.appGray6)
        .cornerRadius(12)
    }
    
    private var errorLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.appCritical)
                Text("Errors (\(manager.errorLog.count))")
                    .font(.headline)
            }
            
            ForEach(Array(manager.errorLog.prefix(3).enumerated()), id: \.offset) { _, error in
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.link)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(error.error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
            
            if manager.errorLog.count > 3 {
                Text("...and \(manager.errorLog.count - 3) more")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .adaptiveToneBackground(.critical, baseOpacity: 0.1)
        .cornerRadius(12)
    }
    
    // Helper functions
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
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}

/// Small stat card for displaying counts
struct StatCard: View {
    let icon: String
    let color: Color
    let value: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text("\(value)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - View Modifier for Easy Integration

/// View modifier to add the batch extraction status bar to any view
struct BatchExtractionStatusBarModifier: ViewModifier {
    @StateObject private var manager = BatchExtractionManager.shared
    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            BatchExtractionStatusBar(manager: manager)
            content
        }
    }
}

extension View {
    /// Adds a batch extraction status bar to the top of the view
    func batchExtractionStatusBar() -> some View {
        modifier(BatchExtractionStatusBarModifier())
    }
}

// MARK: - Preview

#Preview("Status Bar Active") {
    VStack {
        BatchExtractionStatusBar(manager: {
            let manager = BatchExtractionManager.shared
            // Simulate active extraction for preview
            return manager
        }())
        
        Spacer()
        
        Text("Main Content")
            .font(.title)
    }
}

#Preview("Details Sheet") {
    BatchExtractionDetailsSheet(manager: BatchExtractionManager.shared)
}
