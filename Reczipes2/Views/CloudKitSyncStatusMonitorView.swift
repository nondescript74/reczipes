//
//  CloudKitSyncStatusMonitorView.swift
//  Reczipes2
//
//  Real-time sync status monitor for users and debugging
//

import SwiftUI
import SwiftData
import CloudKit
import Combine

/// Comprehensive sync status view that shows everything needed to debug sync issues
struct CloudKitSyncStatusMonitorView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var monitor = CloudKitSyncMonitor.shared
    @StateObject private var syncLogger = SyncStatusLogger()
    
    @State private var recipeCount: Int = 0
    @State private var recipeXCount: Int = 0
    @State private var bookCount: Int = 0
    @State private var totalRecipeCount: Int = 0
    @State private var userRecordID: String = "Checking..."
    @State private var isRefreshing: Bool = false
    @State private var lastRefreshTime: Date?
    @State private var accountChangedTask: Task<Void, Never>?
    @State private var remoteChangeTask: Task<Void, Never>?
    
    var body: some View {
        List {
            // Overall Status
            Section {
                StatusRow(
                    title: "Sync Status",
                    value: monitor.isSyncEnabled ? "Active" : "Inactive",
                    icon: monitor.statusIcon,
                    color: monitor.statusColor
                )
                
                StatusRow(
                    title: "iCloud Account",
                    value: accountStatusText,
                    icon: "person.circle.fill",
                    color: monitor.statusColor
                )
                
                StatusRow(
                    title: "User ID",
                    value: userRecordID,
                    icon: "key.fill",
                    color: .blue
                )
                .font(.system(.body, design: .monospaced))
            } header: {
                Text("Connection Status")
            } footer: {
                if let lastRefresh = lastRefreshTime {
                    Text("Last updated: \(lastRefresh, style: .relative) ago")
                        .font(.caption)
                }
            }
            
            // Data Status
            Section("Local Data") {
                HStack {
                    Label("\(totalRecipeCount)", systemImage: "book.fill")
                        .font(.title2.bold())
                    Spacer()
                    Text("Total Recipes")
                        .foregroundColor(.secondary)
                }
                
                // Show breakdown if both model types exist
                if recipeCount > 0 || recipeXCount > 0 {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.secondary)
                        Text("Legacy Recipe")
                        Spacer()
                        Text("\(recipeCount)")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    
                    HStack {
                        Image(systemName: "doc.badge.gearshape")
                            .foregroundStyle(Color.appSuccess)
                        Text("RecipeX (CloudKit)")
                        Spacer()
                        Text("\(recipeXCount)")
                            .foregroundStyle(Color.appSuccess)
                    }
                    .font(.caption)
                }
                
                HStack {
                    Label("\(bookCount)", systemImage: "books.vertical.fill")
                        .font(.title3.bold())
                    Spacer()
                    Text("Books")
                        .foregroundColor(.secondary)
                }
                
                if totalRecipeCount > 0 || bookCount > 0 {
                    HStack {
                        Image(systemName: "icloud.and.arrow.up")
                        Text("Ready to sync to other devices")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Activity Log
            Section {
                if syncLogger.events.isEmpty {
                    HStack {
                        Image(systemName: "hourglass")
                        Text("Monitoring sync activity...")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(syncLogger.events.reversed()) { event in
                        SyncEventRow(event: event)
                    }
                }
            } header: {
                HStack {
                    Text("Sync Activity Log")
                    Spacer()
                    if !syncLogger.events.isEmpty {
                        Button("Clear") {
                            syncLogger.clearEvents()
                        }
                        .font(.caption)
                    }
                }
            } footer: {
                Text("Shows real-time sync activity. Keep this screen open to monitor sync progress.")
                    .font(.caption)
            }
            
            // Actions
            Section("Actions") {
                Button {
                    Task {
                        await refreshStatus()
                    }
                } label: {
                    HStack {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh Status")
                    }
                }
                .disabled(isRefreshing)
                
                Button {
                    Task {
                        await copyAllInfoToClipboard()
                    }
                } label: {
                    Label("Copy Status to Clipboard", systemImage: "doc.on.doc")
                }
                
                NavigationLink {
                    CloudKitDiagnosticsView()
                } label: {
                    Label("Advanced Diagnostics", systemImage: "stethoscope")
                }
            }
            
            // Troubleshooting Tips
            Section {
                SyncTipRow(icon: "wifi", tip: "Keep device connected to Wi-Fi")
                SyncTipRow(icon: "app.fill", tip: "Keep app open in foreground")
                SyncTipRow(icon: "bolt.fill", tip: "Plug device into power")
                SyncTipRow(icon: "clock.fill", tip: "Initial sync can take 20-30 minutes")
            } header: {
                Text("Tips for Best Sync Performance")
            }
        }
        .navigationTitle("Sync Monitor")
        .platformNavigationBarTitleDisplayMode(.inline)
        .task {
            await initialSetup()
        }
        .task {
            await monitorAccountChanges()
        }
        .task {
            await monitorRemoteChanges()
        }
        .refreshable {
            await refreshStatus()
        }
        .onDisappear {
            // Clean up tasks
            accountChangedTask?.cancel()
            remoteChangeTask?.cancel()
        }
    }
    
    // MARK: - Computed Properties
    
    private var accountStatusText: String {
        switch monitor.accountStatus {
        case .available:
            return "Signed In"
        case .noAccount:
            return "Not Signed In"
        case .restricted:
            return "Restricted"
        case .couldNotDetermine:
            return "Unknown"
        case .temporarilyUnavailable:
            return "Temporarily Unavailable"
        @unknown default:
            return "Unknown"
        }
    }
    
    // MARK: - Helper Functions
    
    private func initialSetup() async {
        await refreshStatus()
        syncLogger.addEvent("Monitor started")
    }
    
    private func refreshStatus() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        // Refresh account status
        await monitor.checkAccountStatus()
        
        // Count recipes (legacy model)
        let recipeDescriptor = FetchDescriptor<RecipeX>()
        if let recipes = try? modelContext.fetch(recipeDescriptor) {
            recipeCount = recipes.count
        }
        
        // Count RecipeX (new unified model)
        let recipeXDescriptor = FetchDescriptor<RecipeX>()
        if let recipesX = try? modelContext.fetch(recipeXDescriptor) {
            recipeXCount = recipesX.count
        }
        
        // Count Books (new unified model)
        let bookDescriptor = FetchDescriptor<Book>()
        if let booksArray = try? modelContext.fetch(bookDescriptor) {
            bookCount = booksArray.count
        }
        
        totalRecipeCount = recipeCount + recipeXCount
        
        // Get user record ID
        do {
            let container = CKContainer(identifier: "iCloud.com.headydiscy.reczipes")
            let recordID = try await container.userRecordID()
            // Show first 12 characters for identification without exposing full ID
            let idPrefix = String(recordID.recordName.prefix(12))
            userRecordID = "\(idPrefix)..."
            
            syncLogger.addEvent("Status refreshed: \(totalRecipeCount) recipes (\(recipeCount) legacy + \(recipeXCount) RecipeX), \(bookCount) books")
        } catch {
            userRecordID = "Unable to fetch"
            syncLogger.addEvent("Error fetching user ID: \(error.localizedDescription)", type: .error)
        }
        
        lastRefreshTime = Date()
    }
    
    private func monitorAccountChanges() async {
        let notifications = NotificationCenter.default.notifications(named: .CKAccountChanged)
        
        for await _ in notifications {
            syncLogger.addEvent("iCloud account changed", type: .warning)
            await refreshStatus()
        }
    }
    
    private func monitorRemoteChanges() async {
        let notificationName = Notification.Name("NSPersistentStoreRemoteChangeNotification")
        let notifications = NotificationCenter.default.notifications(named: notificationName)
        
        for await _ in notifications {
            syncLogger.addEvent("Remote data change detected", type: .sync)
            
            // Store old counts
            let oldRecipeCount = recipeCount
            let oldRecipeXCount = recipeXCount
            let oldBookCount = bookCount
            
            // Refresh all counts
            let recipeDescriptor = FetchDescriptor<RecipeX>()
            if let recipes = try? modelContext.fetch(recipeDescriptor) {
                recipeCount = recipes.count
            }
            
            let recipeXDescriptor = FetchDescriptor<RecipeX>()
            if let recipesX = try? modelContext.fetch(recipeXDescriptor) {
                recipeXCount = recipesX.count
            }
            
            let bookDescriptor = FetchDescriptor<Book>()
            if let booksArray = try? modelContext.fetch(bookDescriptor) {
                bookCount = booksArray.count
            }
            
            totalRecipeCount = recipeCount + recipeXCount
            
            // Log changes for each model type
            if recipeCount != oldRecipeCount {
                let diff = recipeCount - oldRecipeCount
                if diff > 0 {
                    syncLogger.addEvent("Downloaded \(diff) new Recipe(s) (legacy)", type: .success)
                } else {
                    syncLogger.addEvent("Removed \(abs(diff)) Recipe(s) (legacy)", type: .info)
                }
            }
            
            if recipeXCount != oldRecipeXCount {
                let diff = recipeXCount - oldRecipeXCount
                if diff > 0 {
                    syncLogger.addEvent("Downloaded \(diff) new RecipeX(s)", type: .success)
                } else {
                    syncLogger.addEvent("Removed \(abs(diff)) RecipeX(s)", type: .info)
                }
            }
            
            if bookCount != oldBookCount {
                let diff = bookCount - oldBookCount
                if diff > 0 {
                    syncLogger.addEvent("Downloaded \(diff) new Book(s)", type: .success)
                } else {
                    syncLogger.addEvent("Removed \(abs(diff)) Book(s)", type: .info)
                }
            }
        }
    }
    
    private func copyAllInfoToClipboard() async {
        var text = "=== CloudKit Sync Status ===\n\n"
        text += "Date: \(Date())\n"
        text += "Sync Status: \(monitor.isSyncEnabled ? "Active" : "Inactive")\n"
        text += "iCloud Account: \(accountStatusText)\n"
        text += "User ID: \(userRecordID)\n\n"
        
        text += "=== Local Data ===\n"
        text += "Total Recipes: \(totalRecipeCount)\n"
        text += "  - Legacy Recipe: \(recipeCount)\n"
        text += "  - RecipeX (new): \(recipeXCount)\n"
        text += "Books: \(bookCount)\n\n"
        
        text += "=== Activity Log ===\n"
        for event in syncLogger.events.reversed() {
            text += "[\(event.timestamp.formatted(date: .omitted, time: .standard))] \(event.icon) \(event.message)\n"
        }
        
        PlatformPasteboard.copy(text)
        
        syncLogger.addEvent("Status copied to clipboard", type: .info)
    }
}

// MARK: - Supporting Views

struct StatusRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct SyncEventRow: View {
    let event: SyncEvent
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(event.icon)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.caption)
                    .foregroundColor(event.type.color)
                
                Text(event.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct SyncTipRow: View {
    let icon: String
    let tip: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.appInfo)
                .frame(width: 24)
            
            Text(tip)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Sync Status Logger

@MainActor
class SyncStatusLogger: ObservableObject {
    @Published var events: [SyncEvent] = []
    private let maxEvents = 50
    
    func addEvent(_ message: String, type: SyncEventType = .info) {
        let event = SyncEvent(message: message, type: type)
        
        events.append(event)
        
        // Keep only recent events
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        
        // Also log to console for Xcode debugging
        print("\(event.icon) \(message)")
    }
    
    func clearEvents() {
        events.removeAll()
    }
}

// MARK: - Supporting Types

struct SyncEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: SyncEventType
    
    init(message: String, type: SyncEventType = .info) {
        self.timestamp = Date()
        self.message = message
        self.type = type
    }
    
    var icon: String {
        type.icon
    }
}

enum SyncEventType {
    case info
    case success
    case warning
    case error
    case sync
    
    var icon: String {
        switch self {
        case .info: return "ℹ️"
        case .success: return "✅"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .sync: return "🔄"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .sync: return .blue
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CloudKitSyncStatusMonitorView()
    }
}
