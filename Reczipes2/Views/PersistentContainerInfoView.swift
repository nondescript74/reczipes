//
//  PersistentContainerInfoView.swift
//  Reczipes2
//
//  Shows detailed information about the ModelContainer configuration
//

import SwiftUI
import SwiftData

struct PersistentContainerInfoView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var containerInfo: ContainerInfo?
    @State private var isLoading = true
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading container info...")
                        .foregroundColor(.secondary)
                }
            } else if let info = containerInfo {
                // Warning if CloudKit is not enabled
                if !info.cloudKitEnabled {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.appWarning)
                                Text("CloudKit Not Active")
                                    .font(.headline)
                            }
                            
                            Text("Your app is configured to use CloudKit sync (iCloud.com.headydiscy.reczipes), but the container is currently running in local-only mode.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("Possible reasons:")
                                .font(.subheadline)
                                .bold()
                                .padding(.top, 4)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Not signed into iCloud")
                                Text("• iCloud Drive disabled")
                                Text("• CloudKit container not set up in developer portal")
                                Text("• Network connectivity issues")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section("Container Configuration") {
                    InfoRow(label: "Container Type", value: info.containerType)
                    InfoRow(label: "CloudKit Enabled", value: info.cloudKitEnabled ? "Yes" : "No")
                    
                    if info.cloudKitEnabled {
                        InfoRow(label: "Container ID", value: info.containerIdentifier)
                        InfoRow(label: "Database Type", value: info.databaseType)
                    } else {
                        InfoRow(label: "Status", value: "Local-only (Fallback)")
                        InfoRow(label: "Intended Container", value: "iCloud.com.headydiscy.reczipes")
                    }
                }
                
                Section("Schema") {
                    ForEach(info.modelTypes, id: \.self) { modelType in
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(Color.appInfo)
                            Text(modelType)
                        }
                    }
                }
                
                Section("Storage") {
                    InfoRow(label: "Stored in Memory", value: info.isStoredInMemory ? "Yes" : "No")
                    InfoRow(label: "Allows Save", value: info.allowsSave ? "Yes" : "No")
                    
                    if let url = info.storageURL {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Storage Location")
                                .font(.headline)
                            Text(url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                
                Section("Statistics") {
                    InfoRow(label: "Total Recipes", value: "\(info.recipeCount)")
                    InfoRow(label: "Recipe Books", value: "\(info.recipeBookCount)")
                    InfoRow(label: "Saved Links", value: "\(info.savedLinkCount)")
                }
                
                Section("Actions") {
                    Button("Refresh Info") {
                        Task {
                            await loadContainerInfo()
                        }
                    }
                    
                    Button("Copy Configuration") {
                        copyConfiguration()
                    }
                }
            } else {
                Section {
                    Text("Could not load container information")
                        .foregroundStyle(Color.appCritical)
                }
            }
        }
        .navigationTitle("Container Details")
        .platformNavigationBarTitleDisplayMode(.inline)
        .task {
            await loadContainerInfo()
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadContainerInfo() async {
        isLoading = true
        defer { isLoading = false }
        
        // Get the container from the model context
        let container = modelContext.container
        
        // Gather information
        var info = ContainerInfo()
        
        // Check configurations
        if let firstConfig = container.configurations.first {
            info.containerType = "ModelContainer (SwiftData)"
            
            // CloudKit configuration analysis
            // Since CloudKitDatabase doesn't conform to Equatable, we use the description string
            let cloudKitDB = firstConfig.cloudKitDatabase
            let cloudKitDescription = String(describing: cloudKitDB)
            
            // Debug: Print the actual description to console
            print("🔍 CloudKit Database Description: '\(cloudKitDescription)'")
            
            // Parse the description to determine CloudKit configuration
            // The description format is: CloudKitDatabase(_automatic: bool, _none: bool, _privateDBName: Optional("container.id"))
            if cloudKitDescription.contains("_none: true") {
                info.cloudKitEnabled = false
                info.databaseType = "Local Only"
                info.containerIdentifier = "None"
            } else if cloudKitDescription.contains("_automatic: true") {
                info.cloudKitEnabled = true
                info.databaseType = "CloudKit (Private - Automatic)"
                info.containerIdentifier = "Default Container"
            } else if cloudKitDescription.contains("_privateDBName") {
                info.cloudKitEnabled = true
                info.databaseType = "CloudKit (Private)"
                // Extract container ID from description
                // Format: _privateDBName: Optional("iCloud.com.example.container")
                if let startIdx = cloudKitDescription.range(of: "_privateDBName: Optional(\"")?.upperBound,
                   let endIdx = cloudKitDescription[startIdx...].firstIndex(of: "\"") {
                    let containerID = String(cloudKitDescription[startIdx..<endIdx])
                    info.containerIdentifier = containerID
                } else {
                    info.containerIdentifier = "Private Container (ID not parsed)"
                }
            } else {
                // Unknown CloudKit configuration
                print("⚠️ Unknown CloudKit configuration format")
                info.cloudKitEnabled = false
                info.databaseType = "Unknown: \(cloudKitDescription)"
                info.containerIdentifier = "Unknown"
            }
            
            info.isStoredInMemory = firstConfig.isStoredInMemoryOnly
            info.allowsSave = firstConfig.allowsSave
            info.storageURL = firstConfig.url.path
        }
        
        // Get schema information
        info.modelTypes = container.schema.entities.map { $0.name }.sorted()
        
        // Get counts
        info.recipeCount = (try? modelContext.fetchCount(FetchDescriptor<RecipeX>())) ?? 0
        info.recipeBookCount = (try? modelContext.fetchCount(FetchDescriptor<Book>())) ?? 0
        info.savedLinkCount = (try? modelContext.fetchCount(FetchDescriptor<SavedLink>())) ?? 0
        
        containerInfo = info
        
        // Print to console
        printContainerInfo(info)
    }
    
    private func printContainerInfo(_ info: ContainerInfo) {
        print("\n" + String(repeating: "=", count: 60))
        print("📦 PERSISTENT CONTAINER INFORMATION")
        print(String(repeating: "=", count: 60))
        
        print("\n🏗️  CONFIGURATION:")
        print("   Type: \(info.containerType)")
        print("   CloudKit: \(info.cloudKitEnabled ? "✅ Enabled" : "❌ Disabled")")
        
        if info.cloudKitEnabled {
            print("   Container ID: \(info.containerIdentifier)")
            print("   Database: \(info.databaseType)")
        }
        
        print("\n💾 STORAGE:")
        print("   In Memory: \(info.isStoredInMemory ? "Yes" : "No")")
        print("   Allows Save: \(info.allowsSave ? "Yes" : "No")")
        if let url = info.storageURL {
            print("   Location: \(url)")
        }
        
        print("\n📋 SCHEMA:")
        for modelType in info.modelTypes {
            print("   • \(modelType)")
        }
        
        print("\n📊 DATA:")
        print("   Recipes: \(info.recipeCount)")
        print("   Recipe Books: \(info.recipeBookCount)")
        print("   Saved Links: \(info.savedLinkCount)")
        
        print("\n" + String(repeating: "=", count: 60) + "\n")
    }
    
    private func copyConfiguration() {
        guard let info = containerInfo else { return }
        
        var text = "=== Persistent Container Configuration ===\n\n"
        
        text += "Type: \(info.containerType)\n"
        text += "CloudKit: \(info.cloudKitEnabled ? "Enabled" : "Disabled")\n"
        
        if info.cloudKitEnabled {
            text += "Container ID: \(info.containerIdentifier)\n"
            text += "Database: \(info.databaseType)\n"
        }
        
        text += "\nStorage:\n"
        text += "  In Memory: \(info.isStoredInMemory ? "Yes" : "No")\n"
        text += "  Allows Save: \(info.allowsSave ? "Yes" : "No")\n"
        
        if let url = info.storageURL {
            text += "  Location: \(url)\n"
        }
        
        text += "\nSchema Models:\n"
        for modelType in info.modelTypes {
            text += "  • \(modelType)\n"
        }
        
        text += "\nData Counts:\n"
        text += "  Recipes: \(info.recipeCount)\n"
        text += "  Recipe Books: \(info.recipeBookCount)\n"
        text += "  Saved Links: \(info.savedLinkCount)\n"
        
        PlatformPasteboard.copy(text)
        print("📋 Configuration copied to clipboard")
    }
}

// MARK: - Supporting Types

struct ContainerInfo {
    var containerType: String = "Unknown"
    var cloudKitEnabled: Bool = false
    var containerIdentifier: String = "Unknown"
    var databaseType: String = "Unknown"
    var isStoredInMemory: Bool = false
    var allowsSave: Bool = true
    var storageURL: String?
    var modelTypes: [String] = []
    var recipeCount: Int = 0
    var recipeBookCount: Int = 0
    var savedLinkCount: Int = 0
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        PersistentContainerInfoView()
    }
}
