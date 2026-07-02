//
//  SettingsView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/8/25.
//

import SwiftUI

struct SettingsView: View {
    @State private var showAPIKeyManager = false
    @State private var isAPIKeyConfigured = APIKeyHelper.isConfigured
    @State private var showRecipeAPIIntegration = false
    @State private var isRecipeAPIConfigured = APIKeyHelper.isRecipeAPIConfigured
    @State private var showLicenseAgreement = false
    @State private var showHelpBrowser = false
    @State private var showDiagnosticLog = false
    @StateObject private var onboarding = CloudKitOnboardingService.shared
    @State private var showOnboarding = false
    
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        switch onboarding.onboardingState {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .checking:
            ProgressView()
        default:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Global batch extraction status bar
            BatchExtractionStatusBar(manager: BatchExtractionManager.shared)
            
            NavigationView {
                Form {
                    Section("Recipe Extraction") {
                        HStack {
                            Text("API Key Status")
                            Spacer()
                            if isAPIKeyConfigured {
                                Label("Configured", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Label("Not Set", systemImage: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }

                        HStack {
                            Text("Recipe API Key Status")
                            Spacer()
                            if isRecipeAPIConfigured {
                                Label("Configured", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Label("Not Set", systemImage: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Button("Manage API Key") {
                            showAPIKeyManager = true
                        }

                        Button("Recipe API Setup & Test") {
                            showRecipeAPIIntegration = true
                        }
                        // Onboarding button
                        Button(action: {
                            showOnboarding = true
                        }) {
                            Label("Setup & Diagnostics", systemImage: "gear.circle")
                        }
                        Toggle("Auto-Extract on Image Selection",
                               isOn: .constant(RecipeExtractorConfig.autoExtractOnImageSelection))
                        
                        Toggle("Enable Image Preprocessing",
                               isOn: .constant(RecipeExtractorConfig.defaultUsePreprocessing))
                    }
                    
                    Section("System Status") {
                        NavigationLink {
                            SystemHealthView()
                        } label: {
                            HStack {
                                Label("System Health", systemImage: "heart.text.square")
                                Spacer()
                                SystemHealthBadge()
                            }
                        }
                    }
                    
                    Section("Data & Sync") {
                        NavigationLink(destination: QuickSyncStatusView()) {
                            HStack {
                                Label("Quick Sync Check", systemImage: "checkmark.circle")
                                Spacer()
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                        }
                        
                        NavigationLink(destination: CloudKitSyncStatusMonitorView()) {
                            Label("Sync Monitor", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        
                        NavigationLink(destination: CloudKitSettingsView()) {
                            Label("iCloud Sync Settings", systemImage: "icloud.fill")
                        }
                        
                        NavigationLink(destination: UserContentBackupView()) {
                            Label("User Content Import/Export", systemImage: "arrow.up.arrow.down.circle")
                        }
                        
                        NavigationLink(destination: CloudKitDiagnosticsView()) {
                            Label("Advanced Diagnostics", systemImage: "stethoscope")
                        }
                        
                        NavigationLink(destination: PersistentContainerInfoView()) {
                            Label("Container Details", systemImage: "cylinder.split.1x2")
                        }
                        
                        NavigationLink(destination: CloudKitContainerValidationView()) {
                            HStack {
                                Label("Validate CloudKit Container", systemImage: "checkmark.seal.fill")
                                Spacer()
                                Image(systemName: "star.fill")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    Section("Diagnostics") {
                        NavigationLink {
                            DatabaseDiagnosticsView()
                        } label: {
                            Label("Database Diagnostics", systemImage: "stethoscope")
                        }
                        
                        NavigationLink {
                            LoggingSettingsView()
                        } label: {
                            HStack {
                                Label("Logging Settings", systemImage: "text.alignleft")
                                Spacer()
                                LoggingStatusBadge()
                            }
                        }
                        
                        Button {
                            Task {
                                await ModelContainerManager.shared.logDiagnosticInfo()
                                DatabaseRecoveryLogger.shared.logRecoveryStatistics()
                            }
                        } label: {
                            Label("Export Diagnostic Logs", systemImage: "doc.text")
                        }
                    }
                    
                    

                    Section {
                        NavigationLink(destination: SharedRecipesBrowserView()) {
                            Label("Browse Community Recipes", systemImage: "tray.full.fill")
                        }
                        
                        NavigationLink(destination: SharedBooksBrowserView()) {
                            Label("Browse Community Books", systemImage: "books.vertical.circle.fill")
                        }
                        
                        NavigationLink(destination: SharingSettingsView()) {
                            Label("Public Sharing Settings", systemImage: "person.3.fill")
                        }
                        
                        NavigationLink(destination: CommunitySharingCleanupView()) {
                            HStack {
                                Label("Fix Sharing Issues", systemImage: "wrench.and.screwdriver.fill")
                                Spacer()
                                Image(systemName: "star.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            }
                        }
                    } header: {
                        Text("Community")
                    } footer: {
                        Text("Your recipes and books are automatically synced to iCloud across your devices. Use Public Sharing to share specific content with the wider community.")
                            .font(.caption)
                    }
                    
                    Section {
                        NavigationLink {
                            FODMAPSettingsView()
                        } label: {
                            Label("FODMAP Settings", systemImage: "leaf.circle")
                        }
                        
                        NavigationLink {
                            DiabeticSettingsView()
                        } label: {
                            HStack {
                                Label("Diabetic-Friendly Analysis", systemImage: "heart.text.square")
                                Spacer()
                                if UserDiabeticSettings.shared.isDiabeticEnabled {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                }
                            }
                        }
                    } header: {
                        Text("Dietary Preferences")
                    } footer: {
                        if UserDiabeticSettings.shared.isDiabeticEnabled {
                            Text("Diabetic-friendly analysis is enabled. Recipes can show glycemic load, carb counts, and substitution suggestions.")
                                .font(.caption)
                        }
                    }
                    
                    Section {
                        NavigationLink {
                            RecipeDataDiagnosticView()
                        } label: {
                            HStack {
                                Label("Recipe Data Diagnostics", systemImage: "cross.case.fill")
                                Spacer()
                                Image(systemName: "star.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                        
                        NavigationLink {
                            EmptyRecipeCleanupView()
                        } label: {
                            HStack {
                                Label("Delete Empty Recipes", systemImage: "trash.square.fill")
                                Spacer()
                                Image(systemName: "star.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        
                        NavigationLink {
                            DatabaseMaintenanceView()
                        } label: {
                            HStack {
                                Label("Database Maintenance", systemImage: "wrench.and.screwdriver.fill")
                                Spacer()
                                Image(systemName: "star.fill")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                        }
                        
                        NavigationLink {
                            DuplicateRecipeDetectorView()
                        } label: {
                            HStack {
                                Label("Duplicate Recipe Detector", systemImage: "doc.on.doc.fill")
                                Spacer()
                                Image(systemName: "star.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            }
                        }
                        
                        NavigationLink {
                            DatabaseInvestigationView()
                        } label: {
                            HStack {
                                Label("Database Investigation", systemImage: "magnifyingglass.circle.fill")
                                Spacer()
                                Image(systemName: "star.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            }
                        }
                        
                        NavigationLink {
                            DatabaseDuplicateCleanupView()
                        } label: {
                            HStack {
                                Label("Remove Duplicate Recipes", systemImage: "trash.circle.fill")
                                Spacer()
                                Image(systemName: "star.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        
                        NavigationLink {
                            DatabaseRecoveryView()
                        } label: {
                            Label("Database Recovery", systemImage: "externaldrive.badge.exclamationmark")
                        }
                    } header: {
                        Text("Developer Tools")
                    } footer: {
                        Text("Recipe Data Diagnostics: Check for recipes with missing ingredients, instructions, or notes. Delete Empty Recipes: Remove recipes with no ingredients and no instructions. Database Maintenance: Comprehensive cleanup tools. Duplicate Detector: Find and remove duplicate recipes.")
                            .font(.caption)
                    }

                    
                    Section("Legal") {
                        Button {
                            showLicenseAgreement = true
                        } label: {
                            HStack {
                                Label("View License Agreement", systemImage: "doc.text")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let acceptanceDate = LicenseHelper.acceptanceDate {
                            HStack {
                                Text("Accepted On")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(acceptanceDate, style: .date)
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                    
                    Section {
                        Button {
                            showHelpBrowser = true
                        } label: {
                            HStack {
                                Label("Browse Help Topics", systemImage: "questionmark.circle")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        DiagnosticMenuItem()
                        
                        Button {
                            showDiagnosticLog = true
                        } label: {
                            HStack {
                                Label("Diagnostic Log", systemImage: "doc.text")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Link(destination: URL(string: "https://www.monashfodmap.com")!) {
                            HStack {
                                Label("Monash FODMAP Research", systemImage: "link")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Link(destination: URL(string: "https://diabetes.org")!) {
                            HStack {
                                Label("American Diabetes Association", systemImage: "link")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Link(destination: URL(string: "https://console.anthropic.com")!) {
                            HStack {
                                Label("Get Claude API Key", systemImage: "link")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } header: {
                        Text("Help & Support")
                    } footer: {
                        Text("External resources for FODMAP information, diabetes management, and API access.")
                            .font(.caption)
                    }
                    
                    Section("About") {
                        NavigationLink(destination: VersionHistoryView()) {
                            HStack {
                                Label("Version History", systemImage: "clock.arrow.circlepath")
                                Spacer()
                                Text(versionString)
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        
                        HStack {
                            Text("Current Version")
                            Spacer()
                            Text(versionString)
                                .foregroundColor(.secondary)
                        }
                        
#if DEBUG
                        Section("Debug Tools") {
                            NavigationLink {
                                DatabaseDiagnosticsView()
                            } label: {
                                Label("Database Diagnostics", systemImage: "stethoscope")
                            }
                            
                            NavigationLink(destination: VersionDebugView()) {
                                HStack {
                                    Label("Version Debug Info", systemImage: "ant.circle")
                                        .foregroundColor(.orange)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // Database Recovery Logger Test Menu
                            Menu {
                                Button("Test Recovery Success") {
                                    DatabaseRecoveryLogger.shared.beginRecoveryAttempt()
                                    
                                    let testError = NSError(
                                        domain: "NSCocoaErrorDomain",
                                        code: 134504,
                                        userInfo: [NSLocalizedDescriptionKey: "Test schema error"]
                                    )
                                    
                                    DatabaseRecoveryLogger.shared.logRecoverySuccess(
                                        error: testError,
                                        filesDeleted: ["CloudKitModel.sqlite", "CloudKitModel.sqlite-shm"],
                                        cloudKitEnabled: true,
                                        databaseSizeMB: 10.5
                                    )
                                }
                                
                                Button("Test Recovery Failure") {
                                    DatabaseRecoveryLogger.shared.beginRecoveryAttempt()
                                    
                                    let testError = NSError(
                                        domain: "NSCocoaErrorDomain",
                                        code: 134504,
                                        userInfo: [NSLocalizedDescriptionKey: "Test schema error"]
                                    )
                                    
                                    let secondaryError = NSError(
                                        domain: "SwiftData.SwiftDataError",
                                        code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Failed to recreate container"]
                                    )
                                    
                                    DatabaseRecoveryLogger.shared.logRecoveryFailure(
                                        error: testError,
                                        filesDeleted: ["CloudKitModel.sqlite"],
                                        cloudKitEnabled: true,
                                        secondaryError: secondaryError
                                    )
                                }
                                
                                Button("View Recovery Stats") {
                                    DatabaseRecoveryLogger.shared.logRecoveryStatistics()
                                }
                                
                                Button("Clear Recovery History") {
                                    DatabaseRecoveryLogger.shared.clearHistory()
                                }
                            } label: {
                                HStack {
                                    Label("Recovery Logger Tests", systemImage: "ladybug")
                                        .foregroundColor(.red)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Button {
                                VersionHistoryService.shared.resetVersionTracking()
                            } label: {
                                HStack {
                                    Label("Reset Version Tracking", systemImage: "arrow.counterclockwise")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
#endif
                        
                        Link("Powered by Claude AI",
                             destination: URL(string: "https://www.anthropic.com")!)
                    }
                }
                .navigationTitle("Settings")
                .fullScreenCover(isPresented: $showAPIKeyManager, onDismiss: {
                    // Refresh API key status when manager is dismissed
                    isAPIKeyConfigured = APIKeyHelper.isConfigured
                }) {
                    APIKeyManagerView()
                }
                .sheet(isPresented: $showRecipeAPIIntegration, onDismiss: {
                    isRecipeAPIConfigured = APIKeyHelper.isRecipeAPIConfigured
                }) {
                    RecipeAPIIntegrationView()
                }
                .sheet(isPresented: $showLicenseAgreement) {
                    LicenseDisplayView()
                }
                .sheet(isPresented: $showHelpBrowser) {
                    HelpBrowserView()
                }
                .sheet(isPresented: $showDiagnosticLog) {
                    DiagnosticLogView()
                }
                .sheet(isPresented: $showOnboarding) {
                    CloudKitOnboardingView()
                }
                .onAppear {
                    // Refresh API key status when view appears
                    isAPIKeyConfigured = APIKeyHelper.isConfigured
                    isRecipeAPIConfigured = APIKeyHelper.isRecipeAPIConfigured
                }
            }
        }
    }
}

// MARK: - License Display View (for viewing only, not for initial acceptance)

struct LicenseDisplayView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(LicenseHelper.licenseText)
                        .font(.system(.body, design: .default))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle("License Agreement")
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Logging Status Badge

struct LoggingStatusBadge: View {
    @State private var settings = LoggingSettings.shared
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var statusColor: Color {
        switch settings.loggingLevel {
        case .off:
            return .gray
        case .errors:
            return .green
        case .warnings:
            return .yellow
        case .info:
            return .orange
        case .debug:
            return .red
        }
    }
    
    private var statusText: String {
        switch settings.loggingLevel {
        case .off:
            return "Off"
        case .errors:
            return "Errors"
        case .warnings:
            return "Warnings"
        case .info:
            return "Info"
        case .debug:
            return "Debug"
        }
    }
}

#Preview {
    SettingsView()
}
