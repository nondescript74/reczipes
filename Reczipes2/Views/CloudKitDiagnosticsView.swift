//
//  CloudKitDiagnosticsView.swift
//  Reczipes2
//
//  CloudKit debugging and diagnostics view
//

import SwiftUI
import CloudKit
import SwiftData

struct CloudKitDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var monitor = CloudKitSyncMonitor.shared
    
    @State private var recipeCount: Int = 0
    @State private var containerInfo: String = "Checking..."
    @State private var syncStatus: String = "Unknown"
    @State private var isRunningDiagnostics: Bool = false
    @State private var diagnosticResults: [DiagnosticResult] = []
    
    var body: some View {
        List {
            // CloudKit Account Section
            Section("iCloud Account Status") {
                HStack {
                    Image(systemName: monitor.statusIcon)
                        .foregroundColor(monitor.statusColor)
                    Text(monitor.statusMessage)
                }
                
                if let error = monitor.lastSyncError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.appCritical)
                }
                
                Button("Refresh Account Status") {
                    Task {
                        await monitor.checkAccountStatus()
                    }
                }
            }
            
            // Local Data Section
            Section("Local Data") {
                HStack {
                    Text("Recipes on this device")
                    Spacer()
                    Text("\(recipeCount)")
                        .foregroundColor(.secondary)
                }
                
                Button("Refresh Count") {
                    refreshRecipeCount()
                }
            }
            
            // Container Configuration
            Section("CloudKit Container") {
                Text(containerInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Diagnostics
            Section("Diagnostics") {
                if isRunningDiagnostics {
                    HStack {
                        ProgressView()
                        Text("Running diagnostics...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button("Run Full Diagnostics") {
                        Task {
                            await runDiagnostics()
                        }
                    }
                }
                
                ForEach(diagnosticResults) { result in
                    HStack {
                        Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.passed ? .green : .red)
                        
                        VStack(alignment: .leading) {
                            Text(result.test)
                                .font(.headline)
                            Text(result.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Actions
            Section("Actions") {
                Button("Force Sync Check") {
                    Task {
                        await forceSyncCheck()
                    }
                }
                
                Button("Open CloudKit Dashboard") {
                    if let url = URL(string: "https://icloud.developer.apple.com/dashboard/") {
                        PlatformURLOpener.open(url)
                    }
                }
                
                Button("Copy Diagnostics to Clipboard") {
                    copyDiagnosticsToClipboard()
                }
                .disabled(diagnosticResults.isEmpty)
            }
        }
        .navigationTitle("CloudKit Diagnostics")
        .onAppear {
            refreshRecipeCount()
            updateContainerInfo()
        }
    }
    
    // MARK: - Helper Functions
    
    private func refreshRecipeCount() {
        let descriptor = FetchDescriptor<RecipeX>()
        if let recipes = try? modelContext.fetch(descriptor) {
            recipeCount = recipes.count
            print("📊 Local recipe count: \(recipeCount)")
        }
    }
    
    private func updateContainerInfo() {
        containerInfo = """
        Container: iCloud.com.headydiscy.reczipes
        Type: Private Database
        Sync: \(monitor.isSyncEnabled ? "Enabled" : "Disabled")
        """
    }
    
    private func runDiagnostics() async {
        isRunningDiagnostics = true
        diagnosticResults.removeAll()
        
        // Test 1: iCloud Account
        await monitor.checkAccountStatus()
        let accountTest = DiagnosticResult(
            test: "iCloud Account",
            passed: monitor.accountStatus == .available,
            message: monitor.accountStatus == .available ? "Signed in and available" : monitor.statusMessage
        )
        diagnosticResults.append(accountTest)
        
        // Test 2: Local Data
        refreshRecipeCount()
        let localDataTest = DiagnosticResult(
            test: "Local Data",
            passed: true,
            message: "\(recipeCount) recipes stored locally"
        )
        diagnosticResults.append(localDataTest)
        
        // Test 3: CloudKit Container Access
        do {
            let container = CKContainer(identifier: "iCloud.com.headydiscy.reczipes")
            let status = try await container.accountStatus()
            
            let containerTest = DiagnosticResult(
                test: "CloudKit Container Access",
                passed: status == .available,
                message: status == .available ? "Container accessible" : "Container not accessible: \(status)"
            )
            diagnosticResults.append(containerTest)
        } catch {
            let containerTest = DiagnosticResult(
                test: "CloudKit Container Access",
                passed: false,
                message: "Error: \(error.localizedDescription)"
            )
            diagnosticResults.append(containerTest)
        }
        
        // Test 4: Network Connectivity
        let networkTest = await checkNetworkConnectivity()
        diagnosticResults.append(networkTest)
        
        isRunningDiagnostics = false
        
        // Print summary
        print("\n=== CloudKit Diagnostics Summary ===")
        for result in diagnosticResults {
            print("\(result.passed ? "✅" : "❌") \(result.test): \(result.message)")
        }
        print("=====================================\n")
    }
    
    private func checkNetworkConnectivity() async -> DiagnosticResult {
        do {
            // Try to fetch user record to verify connectivity
            let container = CKContainer(identifier: "iCloud.com.headydiscy.reczipes")
            _ = try await container.userRecordID()
            
            return DiagnosticResult(
                test: "Network Connectivity",
                passed: true,
                message: "Connected to iCloud servers"
            )
        } catch {
            return DiagnosticResult(
                test: "Network Connectivity",
                passed: false,
                message: "Cannot reach iCloud: \(error.localizedDescription)"
            )
        }
    }
    
    private func forceSyncCheck() async {
        print("🔄 Forcing sync check...")
        
        // Refresh account status
        await monitor.checkAccountStatus()
        
        // Refresh local count
        refreshRecipeCount()
        
        print("✅ Sync check complete")
        print("   Account Status: \(monitor.accountStatus)")
        print("   Local Recipes: \(recipeCount)")
    }
    
    private func copyDiagnosticsToClipboard() {
        var text = "=== CloudKit Diagnostics ===\n\n"
        
        text += "iCloud Account: \(monitor.statusMessage)\n"
        text += "Local Recipes: \(recipeCount)\n"
        text += "Container: iCloud.com.headydiscy.reczipes\n\n"
        
        text += "Test Results:\n"
        for result in diagnosticResults {
            text += "\(result.passed ? "✅" : "❌") \(result.test)\n"
            text += "   \(result.message)\n"
        }
        
        PlatformPasteboard.copy(text)
        print("📋 Diagnostics copied to clipboard")
    }
}

// MARK: - Supporting Types

struct DiagnosticResult: Identifiable {
    let id = UUID()
    let test: String
    let passed: Bool
    let message: String
}

#Preview {
    NavigationStack {
        CloudKitDiagnosticsView()
    }
}
