//
//  CloudKitContainerValidationView.swift
//  Reczipes2
//
//  View for validating CloudKit container configuration
//

import SwiftUI

struct CloudKitContainerValidationView: View {
    @State private var validationResult: ValidationResult?
    @State private var isValidating: Bool = false
    
    // The container we're checking
    private let targetContainer = "iCloud.com.headydiscy.reczipes"
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CloudKit Container Validator")
                        .font(.headline)
                    Text("This tool checks why CloudKit sync might not be working with container:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(targetContainer)
                        .font(.caption)
                        .foregroundStyle(Color.appInfo)
                        .monospaced()
                }
                .padding(.vertical, 4)
            }
            
            if isValidating {
                Section {
                    HStack {
                        ProgressView()
                        Text("Validating CloudKit configuration...")
                            .foregroundColor(.secondary)
                    }
                }
            } else if let result = validationResult {
                // Results sections
                resultsView(result)
            } else {
                Section {
                    Button(action: runValidation) {
                        Label("Run Validation", systemImage: "play.circle.fill")
                            .font(.headline)
                    }
                }
            }
        }
        .navigationTitle("Container Validation")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            if validationResult != nil {
                Button("Run Again") {
                    runValidation()
                }
            }
        }
    }
    
    @ViewBuilder
    private func resultsView(_ result: ValidationResult) -> some View {
        // Overall diagnosis
        Section("Diagnosis") {
            let diagnosis = result.diagnose()
            HStack {
                Text(diagnosis.emoji)
                    .font(.title)
                Text(diagnosis.summary)
                    .font(.headline)
            }
            .padding(.vertical, 4)
            
            if !diagnosis.issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Issues Found:")
                        .font(.subheadline)
                        .bold()
                    ForEach(Array(diagnosis.issues.enumerated()), id: \.offset) { index, issue in
                        HStack(alignment: .top) {
                            Text("\(index + 1).")
                                .foregroundColor(.secondary)
                            Text(issue)
                                .foregroundStyle(Color.appCritical)
                        }
                        .font(.caption)
                    }
                }
            }
            
            if !diagnosis.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommendations:")
                        .font(.subheadline)
                        .bold()
                        .padding(.top, 4)
                    ForEach(Array(diagnosis.recommendations.enumerated()), id: \.offset) { index, rec in
                        HStack(alignment: .top) {
                            Text("\(index + 1).")
                                .foregroundColor(.secondary)
                            Text(rec)
                                .foregroundStyle(Color.appWarning)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        
        // Account status
        Section("iCloud Account") {
            HStack {
                Text("Status")
                Spacer()
                Text(result.isAccountAvailable ? "✅ Available" : "❌ Not Available")
                    .foregroundColor(result.isAccountAvailable ? .green : .red)
            }
            
            VStack(alignment: .leading) {
                Text(result.accountStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        
        // Container access
        Section("Container Access") {
            HStack {
                Text("Container ID")
                Spacer()
                Text(targetContainer)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Can Access")
                Spacer()
                Text(result.canAccessPrivateDatabase ? "✅ Yes" : "❌ No")
                    .foregroundColor(result.canAccessPrivateDatabase ? .green : .red)
            }
            
            VStack(alignment: .leading) {
                Text(result.containerAccessMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let userID = result.userRecordID {
                HStack {
                    Text("User Record ID")
                    Spacer()
                    Text(userID)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        
        // Entitlements check
        Section("Entitlements") {
            let entitlements = result.entitlementsCheck
            
            HStack {
                Text("Bundle ID")
                Spacer()
                Text(result.bundleID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Show the note if present
            if let note = entitlements.runtimeCheckNote {
                VStack(alignment: .leading, spacing: 8) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Color.appWarning)
                        .padding(.vertical, 4)
                    
                    Text("The real test is whether we can access CloudKit (see Container Access above).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                    
                    if result.canAccessPrivateDatabase {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.appSuccess)
                            Text("Container access works → Entitlements are correct!")
                                .font(.caption)
                                .foregroundStyle(Color.appSuccess)
                        }
                        .padding(.top, 4)
                    } else {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.appCritical)
                            Text("Container access failed → Check entitlements in Xcode")
                                .font(.caption)
                                .foregroundStyle(Color.appCritical)
                        }
                        .padding(.top, 4)
                    }
                }
            } else {
                // Old style display (shouldn't happen with updated validator)
                HStack {
                    Text("CloudKit Enabled")
                    Spacer()
                    Text(entitlements.hasCloudKit ? "✅ Yes" : "❌ No")
                        .foregroundColor(entitlements.hasCloudKit ? .green : .red)
                }
                
                if entitlements.hasContainerIdentifiers {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Container Identifiers:")
                            .font(.caption)
                            .bold()
                        ForEach(entitlements.containerIdentifiers, id: \.self) { container in
                            HStack {
                                if container == targetContainer {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.appSuccess)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                }
                                Text(container)
                                    .font(.caption)
                                    .foregroundColor(container == targetContainer ? .green : .secondary)
                            }
                        }
                    }
                } else {
                    HStack {
                        Text("Container Identifiers")
                        Spacer()
                        Text("❌ None Found")
                            .foregroundStyle(Color.appCritical)
                    }
                }
                
                HStack {
                    Text("Target Container Listed")
                    Spacer()
                    Text(entitlements.containsTargetContainer ? "✅ Yes" : "❌ No")
                        .foregroundColor(entitlements.containsTargetContainer ? .green : .red)
                }
            }
        }
        
        // Actions
        Section("Actions") {
            Button("Copy Full Report") {
                copyReport(result)
            }
            
            if !result.diagnose().issues.isEmpty {
                Link("View CloudKit Setup Guide", destination: URL(string: "https://developer.apple.com/documentation/cloudkit/enabling_cloudkit_in_your_app")!)
            }
        }
    }
    
    private func runValidation() {
        isValidating = true
        validationResult = nil
        
        // Note: Entitlements cannot be read at runtime using Bundle.main.object(forInfoDictionaryKey:)
        // They are in the code signature, not Info.plist
        // The validator will test actual CloudKit access instead
        
        Task {
            let result = await CloudKitContainerValidator.validateContainer(identifier: targetContainer)
            
            // Print to console
            CloudKitContainerValidator.printValidationReport(result)
            
            await MainActor.run {
                validationResult = result
                isValidating = false
            }
        }
    }
    
    private func copyReport(_ result: ValidationResult) {
        let diagnosis = result.diagnose()
        var text = "=== CloudKit Container Validation Report ===\n\n"
        
        text += "Container: \(targetContainer)\n"
        text += "Bundle ID: \(result.bundleID)\n\n"
        
        text += "Diagnosis: \(diagnosis.emoji) \(diagnosis.summary)\n\n"
        
        if !diagnosis.issues.isEmpty {
            text += "Issues:\n"
            for (index, issue) in diagnosis.issues.enumerated() {
                text += "  \(index + 1). \(issue)\n"
            }
            text += "\n"
        }
        
        if !diagnosis.recommendations.isEmpty {
            text += "Recommendations:\n"
            for (index, rec) in diagnosis.recommendations.enumerated() {
                text += "  \(index + 1). \(rec)\n"
            }
            text += "\n"
        }
        
        text += "iCloud Account: \(result.accountStatusMessage)\n"
        text += "Container Access: \(result.containerAccessMessage)\n"
        text += "CloudKit Enabled: \(result.entitlementsCheck.hasCloudKit ? "Yes" : "No")\n"
        text += "Target Container Listed: \(result.entitlementsCheck.containsTargetContainer ? "Yes" : "No")\n"
        
        if result.entitlementsCheck.hasContainerIdentifiers {
            text += "\nContainer Identifiers in Entitlements:\n"
            for container in result.entitlementsCheck.containerIdentifiers {
                text += "  • \(container)\n"
            }
        }
        
        PlatformPasteboard.copy(text)
        print("📋 Validation report copied to clipboard")
    }
}

#Preview {
    NavigationStack {
        CloudKitContainerValidationView()
    }
}
