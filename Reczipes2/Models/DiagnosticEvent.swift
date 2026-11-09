//
//  DiagnosticEvent.swift
//  Reczipes2
//
//  Created on 1/19/26.
//  Structured diagnostic event system for user-facing diagnostics
//

import Foundation
import SwiftUI

/// Severity level for diagnostic events
enum DiagnosticSeverity: String, Codable, CaseIterable {
    case info = "Info"
    case warning = "Warning"
    case error = "Error"
    case critical = "Critical"
    
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .critical: return .purple
        }
    }
}

/// Category of diagnostic event for filtering and organization
enum DiagnosticCategory: String, Codable, CaseIterable {
    case storage = "Storage"
    case cloudKit = "CloudKit"
    case network = "Network"
    case extraction = "Recipe Extraction"
    case image = "Images"
    case allergen = "Allergens"
    case sharing = "Sharing"
    case general = "General"
    
    var icon: String {
        switch self {
        case .storage: return "internaldrive"
        case .cloudKit: return "icloud"
        case .network: return "network"
        case .extraction: return "text.viewfinder"
        case .image: return "photo"
        case .allergen: return "leaf"
        case .sharing: return "square.and.arrow.up"
        case .general: return "app"
        }
    }
}

/// Represents a user action they can take to resolve an issue
struct DiagnosticAction: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let actionType: ActionType
    
    enum ActionType: Codable {
        case openSettings(SettingsDestination)
        case recreateContainer
        case checkCloudKitStatus
        case checkNetworkConnection
        case contactSupport
        case deleteAndReinstall
        case retryOperation
        case clearCache
        case custom(String) // For custom actions with identifiers
        
        var icon: String {
            switch self {
            case .openSettings: return "gear"
            case .recreateContainer: return "arrow.clockwise"
            case .checkCloudKitStatus: return "icloud"
            case .checkNetworkConnection: return "wifi"
            case .contactSupport: return "envelope"
            case .deleteAndReinstall: return "trash"
            case .retryOperation: return "arrow.clockwise"
            case .clearCache: return "trash.circle"
            case .custom: return "hand.tap"
            }
        }
    }
    
    enum SettingsDestination: String, Codable {
        case icloud = "iCloud"
        case cellular = "Cellular"
        case wifi = "Wi-Fi"
        case general = "General"
    }
    
    init(id: UUID = UUID(), title: String, description: String, actionType: ActionType) {
        self.id = id
        self.title = title
        self.description = description
        self.actionType = actionType
    }
}

/// A structured diagnostic event that can be displayed to the user
struct DiagnosticEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let severity: DiagnosticSeverity
    let category: DiagnosticCategory
    let title: String
    let message: String
    let technicalDetails: String?
    let suggestedActions: [DiagnosticAction]
    let isResolved: Bool
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        severity: DiagnosticSeverity,
        category: DiagnosticCategory,
        title: String,
        message: String,
        technicalDetails: String? = nil,
        suggestedActions: [DiagnosticAction] = [],
        isResolved: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.severity = severity
        self.category = category
        self.title = title
        self.message = message
        self.technicalDetails = technicalDetails
        self.suggestedActions = suggestedActions
        self.isResolved = isResolved
    }
    
    /// Create a resolved copy of this event
    func resolved() -> DiagnosticEvent {
        DiagnosticEvent(
            id: id,
            timestamp: timestamp,
            severity: severity,
            category: category,
            title: title,
            message: message,
            technicalDetails: technicalDetails,
            suggestedActions: suggestedActions,
            isResolved: true
        )
    }
}

// MARK: - Common Diagnostic Events

extension DiagnosticEvent {
    
    // MARK: Storage Events
    
    static func containerCreated(cloudKitEnabled: Bool) -> DiagnosticEvent {
        DiagnosticEvent(
            severity: .info,
            category: .storage,
            title: "Storage Initialized",
            message: cloudKitEnabled 
                ? "Your recipe data is syncing with iCloud."
                : "Your recipe data is stored locally on this device.",
            technicalDetails: "ModelContainer created with CloudKit: \(cloudKitEnabled)"
        )
    }
    
    static func containerRecreated(reason: String, cloudKitEnabled: Bool) -> DiagnosticEvent {
        DiagnosticEvent(
            severity: .warning,
            category: .storage,
            title: "Storage Reinitialized",
            message: "Your storage was reset to fix an issue. Your data is safe.",
            technicalDetails: "Container recreated due to: \(reason). CloudKit enabled: \(cloudKitEnabled)",
            suggestedActions: [
                DiagnosticAction(
                    title: "Verify Your Data",
                    description: "Check that your recipes and recipe books appear correctly",
                    actionType: .retryOperation
                )
            ]
        )
    }
    
    static func containerHealthCheckFailed(error: String) -> DiagnosticEvent {
        DiagnosticEvent(
            severity: .error,
            category: .storage,
            title: "Storage Health Check Failed",
            message: "There was a problem accessing your recipe data.",
            technicalDetails: "Health check error: \(error)",
            suggestedActions: [
                DiagnosticAction(
                    title: "Restart the App",
                    description: "Close and reopen Reczipes to attempt automatic recovery",
                    actionType: .retryOperation
                ),
                DiagnosticAction(
                    title: "Check Available Storage",
                    description: "Make sure your device has enough free storage space",
                    actionType: .openSettings(.general)
                )
            ]
        )
    }
    
    static func containerRecoveryFailed() -> DiagnosticEvent {
        DiagnosticEvent(
            severity: .critical,
            category: .storage,
            title: "Storage Recovery Failed",
            message: "Automatic recovery couldn't fix the storage issue. Your data may be in iCloud.",
            technicalDetails: "All recovery attempts exhausted",
            suggestedActions: [
                DiagnosticAction(
                    title: "Check iCloud Status",
                    description: "Verify you're signed into iCloud and have sync enabled",
                    actionType: .checkCloudKitStatus
                ),
                DiagnosticAction(
                    title: "Reinstall Reczipes",
                    description: "Delete the app and reinstall it. Your iCloud data will sync back automatically.",
                    actionType: .deleteAndReinstall
                ),
                DiagnosticAction(
                    title: "Contact Support",
                    description: "If the problem persists, reach out for help",
                    actionType: .contactSupport
                )
            ]
        )
    }
    
    // MARK: CloudKit Events
    
    static func cloudKitAvailable() -> DiagnosticEvent {
        DiagnosticEvent(
            severity: .info,
            category: .cloudKit,
            title: "iCloud Sync Active",
            message: "Your recipes are syncing across all your devices.",
            technicalDetails: "CloudKit account status: available"
        )
    }
    
    static func cloudKitUnavailable(reason: String) -> DiagnosticEvent {
        let message: String
        let actions: [DiagnosticAction]
        
        switch reason.lowercased() {
        case let r where r.contains("no account"):
            message = "You're not signed into iCloud. Your recipes are saved locally."
            actions = [
                DiagnosticAction(
                    title: "Sign Into iCloud",
                    description: "Go to Settings > [Your Name] to sign in",
                    actionType: .openSettings(.icloud)
                )
            ]
        case let r where r.contains("restricted"):
            message = String(localized: "iCloud is restricted on this device. Your recipes are saved locally.", bundle: .appLanguage)
            actions = [
                DiagnosticAction(
                    title: "Check Restrictions",
                    description: "Go to Settings > Screen Time > Content & Privacy Restrictions",
                    actionType: .openSettings(.general)
                )
            ]
        default:
            message = String(localized: "iCloud sync is temporarily unavailable. Your recipes are saved locally.", bundle: .appLanguage)
            actions = [
                DiagnosticAction(
                    title: "Check iCloud Settings",
                    description: "Verify iCloud is enabled for Reczipes",
                    actionType: .openSettings(.icloud)
                ),
                DiagnosticAction(
                    title: "Check Internet Connection",
                    description: "Make sure you're connected to the internet",
                    actionType: .checkNetworkConnection
                )
            ]
        }
        
        return DiagnosticEvent(
            severity: .warning,
            category: .cloudKit,
            title: "iCloud Sync Unavailable",
            message: message,
            technicalDetails: "CloudKit status: \(reason)",
            suggestedActions: actions
        )
    }
    
    static func cloudKitAccountChanged(nowAvailable: Bool) -> DiagnosticEvent {
        if nowAvailable {
            return DiagnosticEvent(
                severity: .info,
                category: .cloudKit,
                title: "iCloud Sync Enabled",
                message: "Your recipes will now sync across all your devices.",
                technicalDetails: "CloudKit account became available",
                suggestedActions: [
                    DiagnosticAction(
                        title: "Wait for Sync",
                        description: "It may take a few moments for all your data to sync",
                        actionType: .retryOperation
                    )
                ]
            )
        } else {
            return DiagnosticEvent(
                severity: .warning,
                category: .cloudKit,
                title: "iCloud Sync Disabled",
                message: "Your recipes are now saved locally only.",
                technicalDetails: "CloudKit account became unavailable",
                suggestedActions: [
                    DiagnosticAction(
                        title: "Check iCloud Status",
                        description: "Verify you're signed into iCloud",
                        actionType: .openSettings(.icloud)
                    )
                ]
            )
        }
    }
    
    // MARK: Network Events
    
    static func networkError(operation: String, error: String) -> DiagnosticEvent {
        DiagnosticEvent(
            severity: .error,
            category: .network,
            title: "Network Error",
            message: "Couldn't complete \(operation) due to a network issue.",
            technicalDetails: error,
            suggestedActions: [
                DiagnosticAction(
                    title: "Check Your Connection",
                    description: "Make sure you're connected to Wi-Fi or cellular",
                    actionType: .checkNetworkConnection
                ),
                DiagnosticAction(
                    title: "Try Again",
                    description: "Retry the operation once you're back online",
                    actionType: .retryOperation
                )
            ]
        )
    }
    
    // MARK: Recipe Extraction Events
    
    static func extractionSuccess(source: String) -> DiagnosticEvent {
        DiagnosticEvent(
            severity: .info,
            category: .extraction,
            title: "Recipe Extracted",
            message: "Successfully extracted recipe from \(source).",
            technicalDetails: "Source: \(source)"
        )
    }
    
    static func extractionFailed(source: String, error: String) -> DiagnosticEvent {
        DiagnosticEvent(
            severity: .error,
            category: .extraction,
            title: "Extraction Failed",
            message: "Couldn't extract recipe from \(source).",
            technicalDetails: error,
            suggestedActions: [
                DiagnosticAction(
                    title: "Try a Different URL",
                    description: "Some websites don't support recipe extraction",
                    actionType: .retryOperation
                ),
                DiagnosticAction(
                    title: "Copy and Paste",
                    description: "Manually copy the recipe content instead",
                    actionType: .retryOperation
                )
            ]
        )
    }
}
