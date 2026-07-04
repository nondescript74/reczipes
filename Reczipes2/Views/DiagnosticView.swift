//
//  DiagnosticView.swift
//  Reczipes2
//
//  Created on 1/19/26.
//  User-facing diagnostic view with filtering and actionable next steps
//

import SwiftUI

/// Main diagnostic view accessible from anywhere in the app
struct DiagnosticView: View {
    @StateObject private var diagnosticManager = DiagnosticManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedFilter: EventFilter = .failures
    @State private var selectedCategory: DiagnosticCategory?
    @State private var searchText = ""
    @State private var showingExportSheet = false
    @State private var exportText = ""
    
    enum EventFilter: String, CaseIterable {
        case failures = "Issues"
        case all = "All Events"
        case unresolved = "Active"
        
        var icon: String {
            switch self {
            case .failures: return "exclamationmark.triangle"
            case .all: return "list.bullet"
            case .unresolved: return "clock"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(EventFilter.allCases, id: \.self) { filter in
                        Label(filter.rawValue, systemImage: filter.icon)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Category Filter
                if !filteredEvents.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            CategoryFilterButton(
                                category: nil,
                                isSelected: selectedCategory == nil,
                                action: { selectedCategory = nil }
                            )
                            
                            ForEach(DiagnosticCategory.allCases, id: \.self) { category in
                                if hasEvents(inCategory: category) {
                                    CategoryFilterButton(
                                        category: category,
                                        isSelected: selectedCategory == category,
                                        action: { selectedCategory = category }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                }
                
                // Events List
                if filteredEvents.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredEvents) { event in
                            DiagnosticEventRow(event: event)
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search diagnostics")
                }
            }
            .navigationTitle("Diagnostics")
            .platformNavigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .platformNavBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .platformNavBarTrailing) {
                    Menu {
                        Button(action: { exportDiagnostics() }) {
                            Label("Export Report", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(action: { diagnosticManager.clearResolvedEvents() }) {
                            Label("Clear Resolved", systemImage: "checkmark.circle")
                        }
                        
                        Button(role: .destructive, action: { diagnosticManager.clearAllEvents() }) {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportSheet(text: exportText)
            }
        }
    }
    
    // MARK: - Filtered Events
    
    private var filteredEvents: [DiagnosticEvent] {
        var events: [DiagnosticEvent]
        
        // Apply primary filter
        switch selectedFilter {
        case .failures:
            events = diagnosticManager.failureEvents
        case .all:
            events = diagnosticManager.events
        case .unresolved:
            events = diagnosticManager.unresolvedEvents
        }
        
        // Apply category filter
        if let category = selectedCategory {
            events = events.filter { $0.category == category }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            events = events.filter { event in
                event.title.localizedCaseInsensitiveContains(searchText) ||
                event.message.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return events
    }
    
    private func hasEvents(inCategory category: DiagnosticCategory) -> Bool {
        switch selectedFilter {
        case .failures:
            return diagnosticManager.failureEvents.contains { $0.category == category }
        case .all:
            return diagnosticManager.events.contains { $0.category == category }
        case .unresolved:
            return diagnosticManager.unresolvedEvents.contains { $0.category == category }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text(emptyStateTitle)
            } icon: {
                Image(systemName: emptyStateIcon)
                    .foregroundStyle(Color.appSuccess)
            }
        } description: {
            Text(emptyStateMessage)
        }
    }
    
    private var emptyStateTitle: String {
        switch selectedFilter {
        case .failures:
            return "No Issues Found"
        case .all:
            return "No Diagnostic Events"
        case .unresolved:
            return "Everything Resolved"
        }
    }
    
    private var emptyStateIcon: String {
        switch selectedFilter {
        case .failures:
            return "checkmark.circle.fill"
        case .all:
            return "tray"
        case .unresolved:
            return "checkmark.circle.fill"
        }
    }
    
    private var emptyStateMessage: String {
        switch selectedFilter {
        case .failures:
            return "Your app is running smoothly with no errors or critical issues."
        case .all:
            return "No diagnostic events have been recorded yet."
        case .unresolved:
            return "All diagnostic issues have been resolved."
        }
    }
    
    // MARK: - Export
    
    private func exportDiagnostics() {
        exportText = diagnosticManager.exportAsText()
        showingExportSheet = true
    }
}

// MARK: - Category Filter Button

private struct CategoryFilterButton: View {
    let category: DiagnosticCategory?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let category {
                    Image(systemName: category.icon)
                        .font(.caption)
                    Text(category.rawValue)
                        .font(.subheadline)
                } else {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                    Text("All")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Diagnostic Event Row

private struct DiagnosticEventRow: View {
    let event: DiagnosticEvent
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: event.severity.icon)
                    .font(.title3)
                    .foregroundStyle(event.severity.color)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.headline)
                    
                    Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if event.isResolved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appSuccess)
                }
                
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }
            
            // Message
            Text(event.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Expanded Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Technical Details
                    if let technical = event.technicalDetails {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Technical Details", systemImage: "info.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            
                            Text(technical)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    
                    // Suggested Actions
                    if !event.suggestedActions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Suggested Actions", systemImage: "lightbulb")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            
                            ForEach(event.suggestedActions) { action in
                                DiagnosticActionButton(action: action, eventId: event.id)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Diagnostic Action Button

private struct DiagnosticActionButton: View {
    let action: DiagnosticAction
    let eventId: UUID
    
    @StateObject private var diagnosticManager = DiagnosticManager.shared
    @StateObject private var containerManager = ModelContainerManager.shared
    
    var body: some View {
        Button(action: performAction) {
            HStack(spacing: 12) {
                Image(systemName: action.actionType.icon)
                    .font(.body)
                    .foregroundStyle(Color.onTint)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    
                    Text(action.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    private func performAction() {
        Task { @MainActor in
            switch action.actionType {
            case .openSettings(let destination):
                openSystemSettings(destination)
                diagnosticManager.markResolved(eventId: eventId)
                
            case .recreateContainer:
                await containerManager.manuallyRecreateContainer()
                diagnosticManager.markResolved(eventId: eventId)
                
            case .checkCloudKitStatus:
                // Navigate to CloudKit status or trigger check
                await containerManager.recreateContainer()
                diagnosticManager.markResolved(eventId: eventId)
                
            case .checkNetworkConnection:
                openSystemSettings(.wifi)
                diagnosticManager.markResolved(eventId: eventId)
                
            case .contactSupport:
                openSupportEmail()
                
            case .deleteAndReinstall:
                // Just mark as resolved, user will do this manually
                showDeleteInstructions()
                
            case .retryOperation:
                // Mark as resolved, user will retry
                diagnosticManager.markResolved(eventId: eventId)
                
            case .clearCache:
                // Implement cache clearing
                diagnosticManager.markResolved(eventId: eventId)
                
            case .custom(let identifier):
                // Handle custom actions
                handleCustomAction(identifier)
            }
        }
    }
    
    private func openSystemSettings(_ destination: DiagnosticAction.SettingsDestination) {
        var urlString = "App-Prefs:"
        
        switch destination {
        case .icloud:
            urlString = "App-Prefs:CASTLE" // iCloud settings
        case .cellular:
            urlString = "App-Prefs:MOBILE_DATA"
        case .wifi:
            urlString = "App-Prefs:WIFI"
        case .general:
            urlString = PlatformURLOpener.settingsURLString
        }
        
        if let url = URL(string: urlString) {
            PlatformURLOpener.open(url)
        } else if let settingsUrl = URL(string: PlatformURLOpener.settingsURLString) {
            PlatformURLOpener.open(settingsUrl)
        }
    }
    
    private func openSupportEmail() {
        let email = "support@reczipes.com"
        let subject = "Reczipes Support Request"
        let body = """
        
        
        ---
        Diagnostic Information:
        \(diagnosticManager.exportAsText())
        """
        
        let encoded = "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: encoded) {
            PlatformURLOpener.open(url)
        }
    }
    
    private func showDeleteInstructions() {
        // This would typically show an alert with instructions
        // For now, just mark as handled
        diagnosticManager.markResolved(eventId: eventId)
    }
    
    private func handleCustomAction(_ identifier: String) {
        // Handle custom action identifiers
        diagnosticManager.markResolved(eventId: eventId)
    }
}

// MARK: - Export Sheet

private struct ExportSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Diagnostic Report")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .platformNavBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .platformNavBarTrailing) {
                    ShareLink(item: text) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DiagnosticView()
        .onAppear {
            // Add some sample events for preview
            let manager = DiagnosticManager.shared
            manager.addEvent(.containerCreated(cloudKitEnabled: true))
            manager.addEvent(.cloudKitAvailable())
            manager.addEvent(.containerHealthCheckFailed(error: "Sample error"))
            manager.addEvent(.networkError(operation: "recipe extraction", error: "Connection timeout"))
        }
}
