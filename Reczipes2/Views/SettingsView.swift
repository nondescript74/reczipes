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

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case extraction, sync, community, dietary, maintenance, helpAbout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extraction:  return "Extraction"
        case .sync:        return "iCloud & Sync"
        case .community:   return "Community"
        case .dietary:     return "Dietary"
        case .maintenance: return "Maintenance"
        case .helpAbout:   return "Help & About"
        }
    }

    var icon: String {
        switch self {
        case .extraction:  return "wand.and.stars"
        case .sync:        return "icloud"
        case .community:   return "person.3.fill"
        case .dietary:     return "leaf"
        case .maintenance: return "wrench.and.screwdriver"
        case .helpAbout:   return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .extraction:  return Color.appInfo
        case .sync:        return Color.appSuccess
        case .community:   return .purple
        case .dietary:     return .green
        case .maintenance: return Color.appWarning
        case .helpAbout:   return .gray
        }
    }

    var description: String {
        switch self {
        case .extraction:  return "API keys, auto-extract & image settings"
        case .sync:        return "iCloud sync, health checks & diagnostics"
        case .community:   return "Browse & share community content"
        case .dietary:     return "FODMAP and diabetic preferences"
        case .maintenance: return "Database tools & logging"
        case .helpAbout:   return "Help, legal & app information"
        }
    }
}

struct SettingsView: View {
    @State private var activeCategory: SettingsCategory?
    @StateObject private var onboarding = CloudKitOnboardingService.shared
    @State private var isAPIKeyConfigured = APIKeyHelper.isConfigured
    @State private var isRecipeAPIConfigured = APIKeyHelper.isRecipeAPIConfigured

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            BatchExtractionStatusBar(manager: BatchExtractionManager.shared)

            Form {
                statusSection
                categoriesSection
            }
            .navigationTitle("Settings")
            .sheet(item: $activeCategory) { category in
                SettingsCategorySheet(category: category)
            }
            .onAppear {
                isAPIKeyConfigured = APIKeyHelper.isConfigured
                isRecipeAPIConfigured = APIKeyHelper.isRecipeAPIConfigured
            }
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section("Status") {
            HStack {
                Label("Claude API Key", systemImage: "key.fill")
                Spacer()
                if isAPIKeyConfigured {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.appSuccess)
                } else {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.appCritical)
                }
            }

            HStack {
                Label("Recipe API Key", systemImage: "key")
                Spacer()
                if isRecipeAPIConfigured {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.appSuccess)
                } else {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.appCritical)
                }
            }

            HStack {
                Label("iCloud", systemImage: "icloud")
                Spacer()
                switch onboarding.onboardingState {
                case .ready:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.appSuccess)
                case .checking:
                    ProgressView()
                default:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.appWarning)
                }
            }

            HStack {
                Text("Version")
                Spacer()
                Text(versionString).foregroundStyle(.secondary).font(.callout)
            }
        }
    }

    private var categoriesSection: some View {
        Section("Settings") {
            ForEach(SettingsCategory.allCases) { category in
                Button {
                    activeCategory = category
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(category.color)
                                .frame(width: 32, height: 32)
                            Image(systemName: category.icon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(category.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(category.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Category Sheet

private struct SettingsCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let category: SettingsCategory

    @State private var activeDestination: SettingsDestination?
    @State private var showAPIKeyManager = false
    @State private var isAPIKeyConfigured = APIKeyHelper.isConfigured
    @State private var showRecipeAPIIntegration = false
    @State private var isRecipeAPIConfigured = APIKeyHelper.isRecipeAPIConfigured
    @State private var showLicenseAgreement = false
    @State private var showHelpBrowser = false
    @State private var showDiagnosticLog = false
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            List {
                categoryContent
            }
            .navigationTitle(category.title)
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
        }
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch category {
        case .extraction:  extractionContent
        case .sync:        syncContent
        case .community:   communityContent
        case .dietary:     dietaryContent
        case .maintenance: maintenanceContent
        case .helpAbout:   helpAboutContent
        }
    }

    // MARK: - Extraction

    private var extractionContent: some View {
        Group {
            Section("API Keys") {
                HStack {
                    Text("Claude API Key")
                    Spacer()
                    if isAPIKeyConfigured {
                        Label("Configured", systemImage: "checkmark.circle.fill").foregroundStyle(Color.appSuccess)
                    } else {
                        Label("Not Set", systemImage: "xmark.circle.fill").foregroundStyle(Color.appCritical)
                    }
                }

                HStack {
                    Text("Recipe API Key")
                    Spacer()
                    if isRecipeAPIConfigured {
                        Label("Configured", systemImage: "checkmark.circle.fill").foregroundStyle(Color.appSuccess)
                    } else {
                        Label("Not Set", systemImage: "xmark.circle.fill").foregroundStyle(Color.appCritical)
                    }
                }

                Button("Manage Claude API Key") {
                    settingsLog.info("Settings: Manage API Key tapped")
                    showAPIKeyManager = true
                }

                Button("Recipe API Setup & Test") {
                    settingsLog.info("Settings: Recipe API Setup tapped")
                    showRecipeAPIIntegration = true
                }

                Button {
                    settingsLog.info("Settings: Setup & Diagnostics tapped")
                    showOnboarding = true
                } label: {
                    Label("Setup & Diagnostics", systemImage: "gear.circle")
                }
            }

            Section("Behavior") {
                Toggle("Auto-Extract on Image Selection",
                       isOn: .constant(RecipeExtractorConfig.autoExtractOnImageSelection))
                Toggle("Enable Image Preprocessing",
                       isOn: .constant(RecipeExtractorConfig.defaultUsePreprocessing))
            }
        }
    }

    // MARK: - iCloud & Sync

    private var syncContent: some View {
        Group {
            Section("iCloud") {
                Button {
                    settingsLog.info("Settings: navigating to systemHealth")
                    activeDestination = .systemHealth
                } label: {
                    HStack {
                        Label("System Health", systemImage: "heart.text.square")
                        Spacer()
                        SystemHealthBadge()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)

                navRow("Quick Sync Check", icon: "checkmark.circle", starColor: .yellow, destination: .quickSync)
                navRow("Sync Monitor", icon: "antenna.radiowaves.left.and.right", destination: .syncMonitor)
                navRow("iCloud Sync Settings", icon: "icloud.fill", destination: .iCloudSettings)
            }

            Section("Import / Export") {
                navRow("User Content Import/Export", icon: "arrow.up.arrow.down.circle", destination: .backupRestore)
            }

            Section("Advanced") {
                navRow("Advanced Diagnostics", icon: "stethoscope", destination: .advancedDiagnostics)
                navRow("Container Details", icon: "cylinder.split.1x2", destination: .containerDetails)
                navRow("Validate CloudKit Container", icon: "checkmark.seal.fill", starColor: Color.appInfo, destination: .validateCloudKit)
            }
        }
    }

    // MARK: - Community

    private var communityContent: some View {
        Section {
            navRow("Browse Community Recipes", icon: "tray.full.fill", destination: .communityRecipes)
            navRow("Browse Community Books", icon: "books.vertical.circle.fill", destination: .communityBooks)
            navRow("Public Sharing Settings", icon: "person.3.fill", destination: .sharingSettings)
            navRow("Fix Sharing Issues", icon: "wrench.and.screwdriver.fill", starColor: Color.appWarning, destination: .fixSharingIssues)
        } footer: {
            Text("Your recipes and books are automatically synced to iCloud across your devices. Use Public Sharing to share content with the wider community.")
                .font(.caption)
        }
    }

    // MARK: - Dietary

    private var dietaryContent: some View {
        Section {
            navRow("FODMAP Settings", icon: "leaf.circle", destination: .fodmapSettings)

            Button {
                settingsLog.info("Settings: navigating to diabeticSettings")
                activeDestination = .diabeticSettings
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
        } footer: {
            if UserDiabeticSettings.shared.isDiabeticEnabled {
                Text("Diabetic-friendly analysis is enabled. Recipes can show glycemic load, carb counts, and substitution suggestions.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Maintenance

    private var maintenanceContent: some View {
        Group {
            Section("Diagnostics") {
                navRow("Database Diagnostics", icon: "stethoscope", destination: .databaseDiagnostics)

                Button {
                    settingsLog.info("Settings: navigating to loggingSettings")
                    activeDestination = .loggingSettings
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
                navRow("Recipe Data Diagnostics", icon: "cross.case.fill", starColor: Color.appSuccess, destination: .recipeDataDiagnostics)
                navRow("Delete Empty Recipes", icon: "trash.square.fill", starColor: Color.appCritical, destination: .deleteEmptyRecipes)
                navRow("Database Maintenance", icon: "wrench.and.screwdriver.fill", starColor: Color.appInfo, destination: .databaseMaintenance)
                navRow("Duplicate Recipe Detector", icon: "doc.on.doc.fill", starColor: Color.appWarning, destination: .duplicateDetector)
                navRow("Database Investigation", icon: "magnifyingglass.circle.fill", starColor: Color.appWarning, destination: .databaseInvestigation)
                navRow("Remove Duplicate Recipes", icon: "trash.circle.fill", starColor: Color.appCritical, destination: .removeDuplicates)
                navRow("Database Recovery", icon: "externaldrive.badge.exclamationmark", destination: .databaseRecovery)
            } header: {
                Text("Developer Tools")
            } footer: {
                Text("Recipe Data Diagnostics checks for recipes with missing ingredients or instructions. Delete Empty Recipes removes recipes with no content. Database Maintenance provides comprehensive cleanup tools.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Help & About

    private var helpAboutContent: some View {
        Group {
            Section("Help") {
                Button {
                    settingsLog.info("Settings: Browse Help Topics tapped")
                    showHelpBrowser = true
                } label: {
                    Label("Browse Help Topics", systemImage: "questionmark.circle")
                }
                .foregroundStyle(.primary)

                DiagnosticMenuItem()

                Button {
                    settingsLog.info("Settings: Diagnostic Log tapped")
                    showDiagnosticLog = true
                } label: {
                    Label("Diagnostic Log", systemImage: "doc.text")
                }
                .foregroundStyle(.primary)
            }

            Section("Resources") {
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

            Section("About") {
                Button {
                    settingsLog.info("Settings: navigating to versionHistory")
                    activeDestination = .versionHistory
                } label: {
                    HStack {
                        Label("Version History", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)

                Link("Powered by Claude AI", destination: URL(string: "https://www.anthropic.com")!)

#if DEBUG
                Button {
                    settingsLog.info("Settings: navigating to versionDebug")
                    activeDestination = .versionDebug
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
            }
        }
    }

    // MARK: - Row Helpers

    private func navRow(_ title: String, icon: String, destination: SettingsDestination) -> some View {
        Button {
            settingsLog.info("Settings: navigating to \(destination.rawValue, privacy: .public)")
            activeDestination = destination
        } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
    }

    private func navRow(_ title: String, icon: String, starColor: Color, destination: SettingsDestination) -> some View {
        Button {
            settingsLog.info("Settings: navigating to \(destination.rawValue, privacy: .public)")
            activeDestination = destination
        } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "star.fill").foregroundStyle(starColor).font(.caption)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
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
