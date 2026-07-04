//
//  SettingsView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/8/25.
//

import SwiftUI
import OSLog

private let settingsLog = Logger(subsystem: "com.headydiscy.Reczipes2", category: "SettingsView")

private enum SettingsDestination: String, Identifiable {
    case systemHealth, quickSync, syncMonitor, iCloudSettings, backupRestore
    case advancedDiagnostics, containerDetails, validateCloudKit
    case databaseDiagnostics, loggingSettings
    case communityRecipes, communityBooks, sharingSettings, fixSharingIssues
    case fodmapSettings, diabeticSettings
    case recipeDataDiagnostics, deleteEmptyRecipes, databaseMaintenance
    case duplicateDetector, databaseInvestigation, removeDuplicates, databaseRecovery
    case versionHistory, versionDebug

    var id: String { rawValue }
}

struct SettingsView: View {
    @State private var activeDestination: SettingsDestination?
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
                .foregroundStyle(Color.appSuccess)
        case .checking:
            ProgressView()
        default:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.appWarning)
        }
    }

    private func navigate(to destination: SettingsDestination) {
        settingsLog.info("Settings: navigating to \(destination.rawValue, privacy: .public)")
        activeDestination = destination
    }

    var body: some View {
        VStack(spacing: 0) {
            BatchExtractionStatusBar(manager: BatchExtractionManager.shared)

            Form {
                Section("Recipe Extraction") {
                    HStack {
                        Text("API Key Status")
                        Spacer()
                        if isAPIKeyConfigured {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.appSuccess)
                        } else {
                            Label("Not Set", systemImage: "xmark.circle.fill")
                                .foregroundStyle(Color.appCritical)
                        }
                    }

                    HStack {
                        Text("Recipe API Key Status")
                        Spacer()
                        if isRecipeAPIConfigured {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.appSuccess)
                        } else {
                            Label("Not Set", systemImage: "xmark.circle.fill")
                                .foregroundStyle(Color.appCritical)
                        }
                    }

                    Button("Manage API Key") {
                        settingsLog.info("Settings: Manage API Key tapped")
                        showAPIKeyManager = true
                    }

                    Button("Recipe API Setup & Test") {
                        settingsLog.info("Settings: Recipe API Setup tapped")
                        showRecipeAPIIntegration = true
                    }

                    Button(action: {
                        settingsLog.info("Settings: Setup & Diagnostics tapped")
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
                    Button {
                        navigate(to: .systemHealth)
                    } label: {
                        HStack {
                            Label("System Health", systemImage: "heart.text.square")
                            Spacer()
                            SystemHealthBadge()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section("Data & Sync") {
                    Button {
                        navigate(to: .quickSync)
                    } label: {
                        HStack {
                            Label("Quick Sync Check", systemImage: "checkmark.circle")
                            Spacer()
                            Image(systemName: "star.fill").foregroundColor(.yellow).font(.caption)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .syncMonitor)
                    } label: {
                        HStack {
                            Label("Sync Monitor", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .iCloudSettings)
                    } label: {
                        HStack {
                            Label("iCloud Sync Settings", systemImage: "icloud.fill")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .backupRestore)
                    } label: {
                        HStack {
                            Label("User Content Import/Export", systemImage: "arrow.up.arrow.down.circle")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .advancedDiagnostics)
                    } label: {
                        HStack {
                            Label("Advanced Diagnostics", systemImage: "stethoscope")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .containerDetails)
                    } label: {
                        HStack {
                            Label("Container Details", systemImage: "cylinder.split.1x2")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .validateCloudKit)
                    } label: {
                        HStack {
                            Label("Validate CloudKit Container", systemImage: "checkmark.seal.fill")
                            Spacer()
                            Image(systemName: "star.fill").foregroundStyle(Color.appInfo).font(.caption)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section("Diagnostics") {
                    Button {
                        navigate(to: .databaseDiagnostics)
                    } label: {
                        HStack {
                            Label("Database Diagnostics", systemImage: "stethoscope")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .loggingSettings)
                    } label: {
                        HStack {
                            Label("Logging Settings", systemImage: "text.alignleft")
                            Spacer()
                            LoggingStatusBadge()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        settingsLog.info("Settings: Export Diagnostic Logs tapped")
                        Task {
                            await ModelContainerManager.shared.logDiagnosticInfo()
                            DatabaseRecoveryLogger.shared.logRecoveryStatistics()
                        }
                    } label: {
                        Label("Export Diagnostic Logs", systemImage: "doc.text")
                    }
                }

                Section {
                    Button {
                        navigate(to: .communityRecipes)
                    } label: {
                        HStack {
                            Label("Browse Community Recipes", systemImage: "tray.full.fill")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .communityBooks)
                    } label: {
                        HStack {
                            Label("Browse Community Books", systemImage: "books.vertical.circle.fill")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .sharingSettings)
                    } label: {
                        HStack {
                            Label("Public Sharing Settings", systemImage: "person.3.fill")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .fixSharingIssues)
                    } label: {
                        HStack {
                            Label("Fix Sharing Issues", systemImage: "wrench.and.screwdriver.fill")
                            Spacer()
                            Image(systemName: "star.fill").foregroundStyle(Color.appWarning).font(.caption)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Community")
                } footer: {
                    Text("Your recipes and books are automatically synced to iCloud across your devices. Use Public Sharing to share specific content with the wider community.")
                        .font(.caption)
                }

                Section {
                    Button {
                        navigate(to: .fodmapSettings)
                    } label: {
                        HStack {
                            Label("FODMAP Settings", systemImage: "leaf.circle")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .diabeticSettings)
                    } label: {
                        HStack {
                            Label("Diabetic-Friendly Analysis", systemImage: "heart.text.square")
                            Spacer()
                            if UserDiabeticSettings.shared.isDiabeticEnabled {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.appSuccess).font(.caption)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Dietary Preferences")
                } footer: {
                    if UserDiabeticSettings.shared.isDiabeticEnabled {
                        Text("Diabetic-friendly analysis is enabled. Recipes can show glycemic load, carb counts, and substitution suggestions.")
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        navigate(to: .recipeDataDiagnostics)
                    } label: {
                        HStack {
                            Label("Recipe Data Diagnostics", systemImage: "cross.case.fill")
                            Spacer()
                            Image(systemName: "star.fill").foregroundStyle(Color.appSuccess).font(.caption)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .deleteEmptyRecipes)
                    } label: {
                        HStack {
                            Label("Delete Empty Recipes", systemImage: "trash.square.fill")
                            Spacer()
                            Image(systemName: "star.fill").foregroundStyle(Color.appCritical).font(.caption)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .databaseMaintenance)
                    } label: {
                        HStack {
                            Label("Database Maintenance", systemImage: "wrench.and.screwdriver.fill")
                            Spacer()
                            Image(systemName: "star.fill").foregroundStyle(Color.appInfo).font(.caption)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .duplicateDetector)
                    } label: {
                        HStack {
                            Label("Duplicate Recipe Detector", systemImage: "doc.on.doc.fill")
                            Spacer()
                            Image(systemName: "star.fill").foregroundStyle(Color.appWarning).font(.caption)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .databaseInvestigation)
                    } label: {
                        HStack {
                            Label("Database Investigation", systemImage: "magnifyingglass.circle.fill")
                            Spacer()
                            Image(systemName: "star.fill").foregroundStyle(Color.appWarning).font(.caption)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .removeDuplicates)
                    } label: {
                        HStack {
                            Label("Remove Duplicate Recipes", systemImage: "trash.circle.fill")
                            Spacer()
                            Image(systemName: "star.fill").foregroundStyle(Color.appCritical).font(.caption)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        navigate(to: .databaseRecovery)
                    } label: {
                        HStack {
                            Label("Database Recovery", systemImage: "externaldrive.badge.exclamationmark")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Developer Tools")
                } footer: {
                    Text("Recipe Data Diagnostics: Check for recipes with missing ingredients, instructions, or notes. Delete Empty Recipes: Remove recipes with no ingredients and no instructions. Database Maintenance: Comprehensive cleanup tools. Duplicate Detector: Find and remove duplicate recipes.")
                        .font(.caption)
                }

                Section("Legal") {
                    Button {
                        settingsLog.info("Settings: View License Agreement tapped")
                        showLicenseAgreement = true
                    } label: {
                        HStack {
                            Label("View License Agreement", systemImage: "doc.text")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    if let acceptanceDate = LicenseHelper.acceptanceDate {
                        HStack {
                            Text("Accepted On").foregroundColor(.secondary)
                            Spacer()
                            Text(acceptanceDate, style: .date).foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                }

                Section {
                    Button {
                        settingsLog.info("Settings: Browse Help Topics tapped")
                        showHelpBrowser = true
                    } label: {
                        HStack {
                            Label("Browse Help Topics", systemImage: "questionmark.circle")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    DiagnosticMenuItem()

                    Button {
                        settingsLog.info("Settings: Diagnostic Log tapped")
                        showDiagnosticLog = true
                    } label: {
                        HStack {
                            Label("Diagnostic Log", systemImage: "doc.text")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Link(destination: URL(string: "https://www.monashfodmap.com")!) {
                        HStack {
                            Label("Monash FODMAP Research", systemImage: "link")
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://diabetes.org")!) {
                        HStack {
                            Label("American Diabetes Association", systemImage: "link")
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://console.anthropic.com")!) {
                        HStack {
                            Label("Get Claude API Key", systemImage: "link")
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Help & Support")
                } footer: {
                    Text("External resources for FODMAP information, diabetes management, and API access.")
                        .font(.caption)
                }

                Section("About") {
                    Button {
                        navigate(to: .versionHistory)
                    } label: {
                        HStack {
                            Label("Version History", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Text(versionString).foregroundColor(.secondary).font(.caption)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    HStack {
                        Text("Current Version")
                        Spacer()
                        Text(versionString).foregroundColor(.secondary)
                    }

#if DEBUG
                    Button {
                        navigate(to: .versionDebug)
                    } label: {
                        HStack {
                            Label("Version Debug Info", systemImage: "ant.circle")
                                .foregroundStyle(Color.appWarning)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }

                    Menu {
                        Button("Test Recovery Success") {
                            settingsLog.info("Settings DEBUG: Test Recovery Success tapped")
                            DatabaseRecoveryLogger.shared.beginRecoveryAttempt()
                            let testError = NSError(domain: "NSCocoaErrorDomain", code: 134504,
                                                    userInfo: [NSLocalizedDescriptionKey: "Test schema error"])
                            DatabaseRecoveryLogger.shared.logRecoverySuccess(
                                error: testError,
                                filesDeleted: ["CloudKitModel.sqlite", "CloudKitModel.sqlite-shm"],
                                cloudKitEnabled: true, databaseSizeMB: 10.5)
                        }

                        Button("Test Recovery Failure") {
                            settingsLog.info("Settings DEBUG: Test Recovery Failure tapped")
                            DatabaseRecoveryLogger.shared.beginRecoveryAttempt()
                            let testError = NSError(domain: "NSCocoaErrorDomain", code: 134504,
                                                    userInfo: [NSLocalizedDescriptionKey: "Test schema error"])
                            let secondaryError = NSError(domain: "SwiftData.SwiftDataError", code: 1,
                                                         userInfo: [NSLocalizedDescriptionKey: "Failed to recreate container"])
                            DatabaseRecoveryLogger.shared.logRecoveryFailure(
                                error: testError, filesDeleted: ["CloudKitModel.sqlite"],
                                cloudKitEnabled: true, secondaryError: secondaryError)
                        }

                        Button("View Recovery Stats") {
                            settingsLog.info("Settings DEBUG: View Recovery Stats tapped")
                            DatabaseRecoveryLogger.shared.logRecoveryStatistics()
                        }

                        Button("Clear Recovery History") {
                            settingsLog.info("Settings DEBUG: Clear Recovery History tapped")
                            DatabaseRecoveryLogger.shared.clearHistory()
                        }
                    } label: {
                        HStack {
                            Label("Recovery Logger Tests", systemImage: "ladybug")
                                .foregroundStyle(Color.appCritical)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }

                    Button {
                        settingsLog.info("Settings DEBUG: Reset Version Tracking tapped")
                        VersionHistoryService.shared.resetVersionTracking()
                    } label: {
                        HStack {
                            Label("Reset Version Tracking", systemImage: "arrow.counterclockwise")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
#endif

                    Link("Powered by Claude AI",
                         destination: URL(string: "https://www.anthropic.com")!)
                }
            }
            .navigationTitle("Settings")
            .sheet(item: $activeDestination) { destination in
                SettingsDetailSheet(destination: destination)
            }
            .platformFullScreenCover(isPresented: $showAPIKeyManager, onDismiss: {
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
                isAPIKeyConfigured = APIKeyHelper.isConfigured
                isRecipeAPIConfigured = APIKeyHelper.isRecipeAPIConfigured
            }
        }
    }
}

// MARK: - Settings Detail Sheet

private struct SettingsDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let destination: SettingsDestination

    var body: some View {
        NavigationStack {
            destinationContent
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch destination {
        case .systemHealth:          SystemHealthView()
        case .quickSync:             QuickSyncStatusView()
        case .syncMonitor:           CloudKitSyncStatusMonitorView()
        case .iCloudSettings:        CloudKitSettingsView()
        case .backupRestore:         UserContentBackupView()
        case .advancedDiagnostics:   CloudKitDiagnosticsView()
        case .containerDetails:      PersistentContainerInfoView()
        case .validateCloudKit:      CloudKitContainerValidationView()
        case .databaseDiagnostics:   DatabaseDiagnosticsView()
        case .loggingSettings:       LoggingSettingsView()
        case .communityRecipes:      SharedRecipesBrowserView()
        case .communityBooks:        SharedBooksBrowserView()
        case .sharingSettings:       SharingSettingsView()
        case .fixSharingIssues:      CommunitySharingCleanupView()
        case .fodmapSettings:        FODMAPSettingsView()
        case .diabeticSettings:      DiabeticSettingsView()
        case .recipeDataDiagnostics: RecipeDataDiagnosticView()
        case .deleteEmptyRecipes:    EmptyRecipeCleanupView()
        case .databaseMaintenance:   DatabaseMaintenanceView()
        case .duplicateDetector:     DuplicateRecipeDetectorView()
        case .databaseInvestigation: DatabaseInvestigationView()
        case .removeDuplicates:      DatabaseDuplicateCleanupView()
        case .databaseRecovery:      DatabaseRecoveryView()
        case .versionHistory:        VersionHistoryView()
        case .versionDebug:
#if DEBUG
            VersionDebugView()
#else
            EmptyView()
#endif
        }
    }
}

// MARK: - License Display View

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
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
        case .off:      return .gray
        case .errors:   return .green
        case .warnings: return .yellow
        case .info:     return .orange
        case .debug:    return .red
        }
    }

    private var statusText: String {
        switch settings.loggingLevel {
        case .off:      return "Off"
        case .errors:   return "Errors"
        case .warnings: return "Warnings"
        case .info:     return "Info"
        case .debug:    return "Debug"
        }
    }
}

#Preview {
    SettingsView()
}
