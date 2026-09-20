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

    var summaryGroups: [SettingsSummaryGroup] {
        switch self {
        case .extraction:
            return [
                SettingsSummaryGroup(title: "API Keys", items: [
                    "Claude API Key", "Recipe API Key", "Setup & Diagnostics"
                ]),
                SettingsSummaryGroup(title: "Behavior", items: [
                    "Auto-Extract on Image Selection", "Image Preprocessing"
                ])
            ]
        case .sync:
            return [
                SettingsSummaryGroup(title: "iCloud", items: [
                    "System Health", "Quick Sync Check", "Sync Monitor", "iCloud Sync Settings"
                ]),
                SettingsSummaryGroup(title: "Import / Export", items: [
                    "User Content Import/Export"
                ]),
                SettingsSummaryGroup(title: "Advanced", items: [
                    "Advanced Diagnostics", "Container Details", "Validate CloudKit Container"
                ])
            ]
        case .community:
            return [
                SettingsSummaryGroup(title: nil, items: [
                    "Browse Community Recipes", "Browse Community Books",
                    "Public Sharing Settings", "Fix Sharing Issues"
                ])
            ]
        case .dietary:
            return [
                SettingsSummaryGroup(title: nil, items: [
                    "FODMAP Settings", "Diabetic-Friendly Analysis"
                ])
            ]
        case .maintenance:
            return [
                SettingsSummaryGroup(title: "Diagnostics", items: [
                    "Database Diagnostics", "Logging Settings", "Export Diagnostic Logs"
                ]),
                SettingsSummaryGroup(title: "Developer Tools", items: [
                    "Recipe Data Diagnostics", "Delete Empty Recipes", "Database Maintenance",
                    "Duplicate Detection & Cleanup", "Database Recovery"
                ])
            ]
        case .helpAbout:
            return [
                SettingsSummaryGroup(title: "Help", items: [
                    "Browse Help Topics", "Diagnostic Log"
                ]),
                SettingsSummaryGroup(title: "Resources", items: [
                    "Monash FODMAP Research", "American Diabetes Association", "Get Claude API Key"
                ]),
                SettingsSummaryGroup(title: "Legal & About", items: [
                    "License Agreement", "Version History"
                ])
            ]
        }
    }
}

private struct SettingsSummaryGroup: Identifiable {
    let title: String?
    let items: [String]
    var id: String { title ?? items.first ?? "" }
}

struct SettingsView: View {
    @State private var activeCategory: SettingsCategory?
    @StateObject private var onboarding = CloudKitOnboardingService.shared
    @State private var isAPIKeyConfigured = APIKeyHelper.isConfigured
    @State private var isRecipeAPIConfigured = APIKeyHelper.isRecipeAPIConfigured
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    /// Roomy layouts (Mac, iPad) get cards with content summaries; compact iPhone keeps simple square cards.
    private var showsExpandedCards: Bool {
#if os(iOS)
        return horizontalSizeClass == .regular
#else
        return true
#endif
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            BatchExtractionStatusBar(manager: BatchExtractionManager.shared)

            ScrollView {
                VStack(spacing: 28) {
                    statusHeader
                    categoryGrid
                }
                .frame(maxWidth: showsExpandedCards ? 1060 : 720)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Settings")
            .sheet(item: $activeCategory) { category in
                SettingsCategorySheet(category: category)
                    .macOSSheetFrame()
            }
            .onAppear {
                isAPIKeyConfigured = APIKeyHelper.isConfigured
                isRecipeAPIConfigured = APIKeyHelper.isRecipeAPIConfigured
            }
        }
    }

    // MARK: - Sections

    private var statusHeader: some View {
        VStack(spacing: 14) {
            Text("Status")
                .font(.title3.weight(.semibold))

            ViewThatFits {
                HStack(spacing: 12) {
                    statusPills
                }
                VStack(spacing: 8) {
                    statusPills
                }
            }

            Text("Version \(versionString)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 28)
        .background(Color.appSecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    @ViewBuilder
    private var statusPills: some View {
        statusPill("Claude API Key", icon: "key.fill", isConfigured: isAPIKeyConfigured)
        statusPill("Recipe API Key", icon: "key", isConfigured: isRecipeAPIConfigured)
        iCloudStatusPill
    }

    private func statusPill(_ title: String, icon: String, isConfigured: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
            if isConfigured {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.appSuccess)
            } else {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.appCritical)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Color.appGroupedBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    private var iCloudStatusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "icloud")
                .foregroundStyle(.secondary)
            Text("iCloud")
                .font(.subheadline.weight(.medium))
            switch onboarding.onboardingState {
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.appSuccess)
            case .checking:
                ProgressView()
                    .controlSize(.small)
            default:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.appWarning)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Color.appGroupedBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: showsExpandedCards ? 280 : 150,
                                               maximum: showsExpandedCards ? 360 : 210),
                                     spacing: 16, alignment: .top)],
                  spacing: 16) {
            ForEach(SettingsCategory.allCases) { category in
                Button {
                    activeCategory = category
                } label: {
                    if showsExpandedCards {
                        expandedCategoryCard(category)
                    } else {
                        categoryCard(category)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func expandedCategoryCard(_ category: SettingsCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(category.color)
                        .frame(width: 36, height: 36)
                    Image(systemName: category.icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                }
                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(category.summaryGroups) { group in
                VStack(alignment: .leading, spacing: 5) {
                    if let title = group.title {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    ForEach(group.items, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(category.color)
                            Text(item)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.appSecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func categoryCard(_ category: SettingsCategory) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(category.color)
                    .frame(width: 52, height: 52)
                Image(systemName: category.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text(category.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(category.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(Color.appSecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    .macOSSheetFrame()
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
                    .macOSSheetFrame()
            }
            .sheet(isPresented: $showLicenseAgreement) {
                LicenseDisplayView()
                    .macOSSheetFrame()
            }
            .sheet(isPresented: $showHelpBrowser) {
                HelpBrowserView()
                    .macOSSheetFrame()
            }
            .sheet(isPresented: $showDiagnosticLog) {
                DiagnosticLogView()
                    .macOSSheetFrame()
            }
            .sheet(isPresented: $showOnboarding) {
                CloudKitOnboardingView()
                    .macOSSheetFrame()
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
