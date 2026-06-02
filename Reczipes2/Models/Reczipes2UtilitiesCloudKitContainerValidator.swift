//
//  CloudKitContainerValidator.swift
//  Reczipes2
//
//  Validates CloudKit container configuration
//

import Foundation
import CloudKit

/// Validates CloudKit container configuration and accessibility
actor CloudKitContainerValidator {
    
    /// Comprehensive validation of a specific CloudKit container
    static func validateContainer(identifier: String) async -> ValidationResult {
        var result = ValidationResult(containerIdentifier: identifier)
        
        // 1. Check if we can create a container reference
        let container = CKContainer(identifier: identifier)
        result.canCreateReference = true
        
        // 2. Check account status
        do {
            let status = try await container.accountStatus()
            result.accountStatus = status
            result.isAccountAvailable = (status == .available)
            
            switch status {
            case .available:
                result.accountStatusMessage = "✅ iCloud account available"
            case .noAccount:
                result.accountStatusMessage = "❌ Not signed into iCloud"
            case .restricted:
                result.accountStatusMessage = "🚫 iCloud access restricted"
            case .couldNotDetermine:
                result.accountStatusMessage = "❓ Could not determine account status"
            case .temporarilyUnavailable:
                result.accountStatusMessage = "⏳ Temporarily unavailable"
            @unknown default:
                result.accountStatusMessage = "❓ Unknown status"
            }
        } catch {
            result.accountStatusError = error.localizedDescription
            result.accountStatusMessage = "❌ Error checking account: \(error.localizedDescription)"
        }
        
        // 3. Try to access the container's database
        do {
            _ = container.privateCloudDatabase
            result.canAccessPrivateDatabase = true
            
            // Try to get user record ID (proves we can communicate with CloudKit)
            let userRecordID = try await container.userRecordID()
            result.userRecordID = userRecordID.recordName
            result.canFetchUserRecord = true
            result.containerAccessMessage = "✅ Container accessible"
        } catch {
            result.containerAccessError = error.localizedDescription
            result.containerAccessMessage = "❌ Cannot access container: \(error.localizedDescription)"
            
            // Parse specific errors
            let nsError = error as NSError
            if nsError.domain == CKErrorDomain {
                switch CKError.Code(rawValue: nsError.code) {
                case .notAuthenticated:
                    result.containerAccessMessage = "❌ Not authenticated to iCloud"
                case .networkUnavailable, .networkFailure:
                    result.containerAccessMessage = "❌ Network issue - check connection"
                case .serviceUnavailable:
                    result.containerAccessMessage = "❌ CloudKit service unavailable"
                case .badContainer:
                    result.containerAccessMessage = "❌ Container identifier is invalid or doesn't exist"
                case .permissionFailure:
                    result.containerAccessMessage = "❌ Permission denied - check entitlements"
                default:
                    break
                }
            }
        }
        
        // 4. Check bundle entitlements
        result.bundleID = Bundle.main.bundleIdentifier ?? "Unknown"
        result.entitlementsCheck = checkEntitlements(for: identifier)
        
        return result
    }
    
    /// Check if entitlements include the container
    private static func checkEntitlements(for containerID: String) -> EntitlementsCheck {
        var check = EntitlementsCheck()
        
        // IMPORTANT: Entitlements cannot be reliably read at runtime using Bundle APIs
        // They are embedded in the app's code signature, not in Info.plist
        // The only way to truly verify entitlements is:
        // 1. At build time using Xcode
        // 2. Using `codesign` command line tool
        // 3. By attempting actual CloudKit operations (which we do in validation)
        
        // Instead, we'll check if we can access CloudKit functionality
        // which indirectly proves entitlements are correct
        
        // NOTE: The old code was checking Bundle.main.object(forInfoDictionaryKey:)
        // which would never find entitlements because they're not in Info.plist
        
        // Mark as "cannot determine from runtime" - we rely on actual CloudKit access test
        check.hasICloudServices = true // Assumed if CloudKit access works
        check.iCloudServices = ["CloudKit"] // Assumed
        check.hasCloudKit = true // Assumed if container access succeeds
        check.hasContainerIdentifiers = true // Assumed
        check.containerIdentifiers = [containerID] // Assumed
        check.containsTargetContainer = true // Will be validated by actual container access
        
        // Set note for user
        check.runtimeCheckNote = "⚠️ Entitlements cannot be read at runtime. Validation is based on actual CloudKit access test."
        
        return check
    }
    
    /// Print detailed validation report
    @MainActor static func printValidationReport(_ result: ValidationResult) {
        AppLog.info("\n" + String(repeating: "=", count: 70), category: .storage)
        AppLog.info("☁️  CLOUDKIT CONTAINER VALIDATION REPORT", category: .storage)
        AppLog.info(String(repeating: "=", count: 70), category: .storage)
        
        AppLog.info("\n📦 CONTAINER INFORMATION:", category: .storage)
        AppLog.info("   Container ID: \(result.containerIdentifier)", category: .storage)
        AppLog.info("   Bundle ID: \(result.bundleID)", category: .storage)
        AppLog.info("   Can Create Reference: \(result.canCreateReference ? "✅" : "❌")", category: .storage)
        
        AppLog.info("\n👤 ICLOUD ACCOUNT:", category: .storage)
        AppLog.info("   \(result.accountStatusMessage)", category: .storage)
        if let error = result.accountStatusError {
            AppLog.info("   Error: \(error)", category: .storage)
        }
        
        AppLog.info("\n🗄️  CONTAINER ACCESS:", category: .storage)
        AppLog.info("   \(result.containerAccessMessage)", category: .storage)
        if result.canAccessPrivateDatabase {
            AppLog.info("   Private Database: ✅ Accessible", category: .storage)
        }
        if let userID = result.userRecordID {
            AppLog.info("   User Record ID: \(userID)", category: .storage)
        }
        if let error = result.containerAccessError {
            AppLog.info("   Error: \(error)", category: .storage)
        }
        
        AppLog.info("\n🔐 ENTITLEMENTS CHECK:", category: .storage)
        let entitlements = result.entitlementsCheck
        
        if let note = entitlements.runtimeCheckNote {
            AppLog.info("   \(note)", category: .storage)
            AppLog.info("", category: .storage)
            AppLog.info("   💡 Real test: Can we access CloudKit? (See Container Access above)", category: .storage)
            AppLog.info("      - If container access works → Entitlements are correct ✅", category: .storage)
            AppLog.info("      - If container access fails → Check entitlements in Xcode ❌", category: .storage)
        } else {
            // Old style reporting (won't happen with new code)
            AppLog.info("   iCloud Services: \(entitlements.hasICloudServices ? "✅" : "❌")", category: .storage)
            if entitlements.hasICloudServices {
                AppLog.info("      Services: \(entitlements.iCloudServices.joined(separator: ", "))", category: .storage)
            }
            AppLog.info("   CloudKit Enabled: \(entitlements.hasCloudKit ? "✅" : "❌")", category: .storage)
            AppLog.info("   Container Identifiers: \(entitlements.hasContainerIdentifiers ? "✅" : "❌")", category: .storage)
            if entitlements.hasContainerIdentifiers {
                AppLog.info("      Containers:", category: .storage)
                for container in entitlements.containerIdentifiers {
                    let marker = container == result.containerIdentifier ? "  ➜" : "   "
                    AppLog.info("\(marker) \(container)", category: .storage)
                }
            }
            AppLog.info("   Target Container Listed: \(entitlements.containsTargetContainer ? "✅" : "❌")", category: .storage)
        }
        
        AppLog.info("\n🔍 DIAGNOSIS:", category: .storage)
        let diagnosis = result.diagnose()
        AppLog.info("   \(diagnosis.emoji) \(diagnosis.summary)", category: .storage)
        
        if !diagnosis.issues.isEmpty {
            AppLog.info("\n⚠️  ISSUES FOUND:", category: .storage)
            for (index, issue) in diagnosis.issues.enumerated() {
                AppLog.info("   \(index + 1). \(issue)", category: .storage)
            }
        }
        
        if !diagnosis.recommendations.isEmpty {
            AppLog.info("\n💡 RECOMMENDATIONS:", category: .storage)
            for (index, recommendation) in diagnosis.recommendations.enumerated() {
                AppLog.info("   \(index + 1). \(recommendation)", category: .storage)
            }
        }
        
        AppLog.info("\n" + String(repeating: "=", count: 70) + "\n", category: .storage)
    }
}

// MARK: - Supporting Types

struct ValidationResult: Sendable {
    let containerIdentifier: String
    var bundleID: String = "Unknown"
    
    // Container reference
    var canCreateReference: Bool = false
    
    // Account status
    var accountStatus: CKAccountStatus?
    var isAccountAvailable: Bool = false
    var accountStatusMessage: String = ""
    var accountStatusError: String?
    
    // Container access
    var canAccessPrivateDatabase: Bool = false
    var canFetchUserRecord: Bool = false
    var userRecordID: String?
    var containerAccessMessage: String = ""
    var containerAccessError: String?
    
    // Entitlements
    var entitlementsCheck: EntitlementsCheck = EntitlementsCheck()
    
    func diagnose() -> Diagnosis {
        var issues: [String] = []
        var recommendations: [String] = []
        
        // Check account
        if !isAccountAvailable {
            issues.append("iCloud account not available")
            recommendations.append("Sign into iCloud in Settings app")
        }
        
        // IMPORTANT: Don't check entitlements directly as they can't be read at runtime
        // Instead, rely on the actual CloudKit access test
        // If we can access the container, entitlements are correct!
        
        // Check container access - this is the REAL test
        if !canAccessPrivateDatabase {
            issues.append("Cannot access container's private database")
            if let error = containerAccessError {
                if error.contains("bad container") || error.contains("badContainer") {
                    recommendations.append("Container may not exist in Apple Developer Portal - create it or use existing container")
                    recommendations.append("Or check that container identifier in entitlements matches exactly: '\(containerIdentifier)'")
                } else if error.contains("permission") {
                    recommendations.append("Check that app is properly signed and entitlements are correct")
                    recommendations.append("In Xcode: Signing & Capabilities → iCloud → Add container '\(containerIdentifier)'")
                } else {
                    recommendations.append("Check error: \(error)")
                }
            } else {
                // No specific error, give general guidance
                recommendations.append("Verify entitlements in Xcode: Signing & Capabilities → iCloud → CloudKit")
                recommendations.append("Add container '\(containerIdentifier)' to entitlements")
            }
        }
        
        // Generate summary
        let emoji: String
        let summary: String
        
        if issues.isEmpty {
            emoji = "✅"
            summary = "All checks passed - CloudKit should work!"
        } else if issues.count == 1 {
            emoji = "⚠️"
            summary = "1 issue found: \(issues[0])"
        } else {
            emoji = "❌"
            summary = "\(issues.count) issues found"
        }
        
        return Diagnosis(emoji: emoji, summary: summary, issues: issues, recommendations: recommendations)
    }
}

struct EntitlementsCheck: Sendable {
    var hasICloudServices: Bool = false
    var iCloudServices: [String] = []
    var hasCloudKit: Bool = false
    var hasContainerIdentifiers: Bool = false
    var containerIdentifiers: [String] = []
    var containsTargetContainer: Bool = false
    var ubiquityContainers: [String] = []
    var runtimeCheckNote: String?
}

struct Diagnosis: Sendable {
    let emoji: String
    let summary: String
    let issues: [String]
    let recommendations: [String]
}
