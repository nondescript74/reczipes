//
//  VersionDebugView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/30/24.
//

import SwiftUI

/// Debug view to check version detection and Info.plist values
struct VersionDebugView: View {
    
    private var bundleVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    private var bundleBuild: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
    
    @State private var currentEntry: VersionHistoryRecord?
    @State private var allEntries: [VersionHistoryRecord] = []
    
    var body: some View {
        NavigationView {
            Form {
                Section("Bundle Info (from Info.plist)") {
                    HStack {
                        Text("CFBundleShortVersionString")
                            .font(.caption)
                        Spacer()
                        if let version = bundleVersion {
                            Text(version)
                                .foregroundStyle(Color.appSuccess)
                                .bold()
                        } else {
                            Text("❌ NOT FOUND")
                                .foregroundStyle(Color.appCritical)
                        }
                    }
                    
                    HStack {
                        Text("CFBundleVersion")
                            .font(.caption)
                        Spacer()
                        if let build = bundleBuild {
                            Text(build)
                                .foregroundStyle(Color.appSuccess)
                                .bold()
                        } else {
                            Text("❌ NOT FOUND")
                                .foregroundStyle(Color.appCritical)
                        }
                    }
                }
                
                Section("VersionHistoryService Detection") {
                    HStack {
                        Text("Detected Version")
                        Spacer()
                        Text(VersionHistoryService.shared.currentVersion)
                            .foregroundStyle(Color.appInfo)
                            .bold()
                    }
                    
                    HStack {
                        Text("Detected Build")
                        Spacer()
                        Text(VersionHistoryService.shared.currentBuildNumber)
                            .foregroundStyle(Color.appInfo)
                            .bold()
                    }
                    
                    HStack {
                        Text("Full String")
                        Spacer()
                        Text(VersionHistoryService.shared.currentVersionString)
                            .foregroundColor(.purple)
                            .bold()
                    }
                }
                
                Section("Current Version Entry Match") {
                    if let entry = currentEntry {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.appSuccess)
                            VStack(alignment: .leading) {
                                Text("Match Found!")
                                    .font(.headline)
                                Text("Version \(entry.version) (\(entry.buildNumber))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Changes (\(entry.changes.count)):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(Array(entry.changes.prefix(3)), id: \.self) { change in
                                Text(change)
                                    .font(.caption)
                            }
                            
                            if entry.changes.count > 3 {
                                Text("+ \(entry.changes.count - 3) more...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.appCritical)
                            Text("No Match Found!")
                                .font(.headline)
                        }
                        
                        Text("The current version/build from Info.plist doesn't match any entry in VersionHistory.swift")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("All Version History Entries (\(allEntries.count))") {
                    ForEach(allEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Version \(entry.version) (\(entry.buildNumber))")
                                    .font(.subheadline)
                                    .bold()
                                
                                if entry.version == VersionHistoryService.shared.currentVersion &&
                                   entry.buildNumber == VersionHistoryService.shared.currentBuildNumber {
                                    Spacer()
                                    Text("CURRENT")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green)
                                        .foregroundStyle(Color.onTint)
                                        .cornerRadius(4)
                                }
                            }
                            
                            Text("\(entry.changes.count) changes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section("What's New (from getWhatsNew())") {
                    if let whatsNew = try? VersionHistoryService.shared.getWhatsNew() {
                        Text("Returns \(whatsNew.count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(whatsNew, id: \.self) { change in
                            Text(change)
                                .font(.caption)
                        }
                    } else {
                        Text("Unable to fetch what's new")
                            .foregroundStyle(Color.appCritical)
                    }
                }
                
                Section("Actions") {
                    Button {
                        VersionHistoryService.shared.resetVersionTracking()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset Version Tracking")
                        }
                    }
                    
                    Button {
                        // Print to console for debugging
                        print("🐛 VERSION DEBUG INFO")
                        print("Bundle Version: \(bundleVersion ?? "nil")")
                        print("Bundle Build: \(bundleBuild ?? "nil")")
                        print("Manager Version: \(VersionHistoryService.shared.currentVersion)")
                        print("Manager Build: \(VersionHistoryService.shared.currentBuildNumber)")
                        print("Manager String: \(VersionHistoryService.shared.currentVersionString)")
                        print("Current Entry: \(currentEntry?.versionString ?? "nil")")
                        print("Should Show What's New: \(VersionHistoryService.shared.shouldShowWhatsNew())")
                    } label: {
                        HStack {
                            Image(systemName: "ant.circle")
                            Text("Print Debug Info to Console")
                        }
                    }
                }
            }
            .navigationTitle("Version Debug")
            .platformNavigationBarTitleDisplayMode(.inline)
            .task {
                await loadData()
            }
        }
    }
    
    @MainActor
    private func loadData() async {
        do {
            currentEntry = try VersionHistoryService.shared.getCurrentVersionEntry()
            allEntries = try VersionHistoryService.shared.getAllHistory()
        } catch {
            print("Error loading version history: \(error)")
        }
    }
}

#Preview {
    VersionDebugView()
}
