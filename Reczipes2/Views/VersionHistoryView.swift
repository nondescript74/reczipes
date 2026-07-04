//
//  VersionHistoryView.swift
//  Reczipes2
//
//  Created on 02/01/26.
//

import SwiftUI
import SwiftData

// MARK: - Version History View

struct VersionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VersionHistoryRecord.releaseDate, order: .reverse)
    private var historyRecords: [VersionHistoryRecord]
    
    @State private var expandedVersions: Set<String> = []
    @State private var showShareSheet = false
    @State private var shareText = ""
    
    var body: some View {
        List {
            if historyRecords.isEmpty {
                ContentUnavailableView(
                    "No Version History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Version history will appear here once entries are added.")
                )
            } else {
                ForEach(historyRecords) { record in
                    versionSection(for: record)
                }
            }
        }
        .navigationTitle("Version History")
        .platformNavigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    generateShareText()
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(historyRecords.isEmpty)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
    }
    
    // MARK: - Version Section
    
    private func versionSection(for record: VersionHistoryRecord) -> some View {
        let isExpanded = expandedVersions.contains(record.versionString)
        
        return Section {
            // Version Header
            Button {
                withAnimation {
                    if isExpanded {
                        expandedVersions.remove(record.versionString)
                    } else {
                        expandedVersions.insert(record.versionString)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version \(record.versionString)")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Text(formatDate(record.releaseDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            
            // Changes List (when expanded)
            if isExpanded {
                ForEach(record.changes, id: \.self) { change in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        
                        Text(change)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            if record.versionString == VersionHistoryService.shared.currentVersionString {
                Label("Current Version", systemImage: "star.fill")
                    .foregroundStyle(Color.appWarning)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func generateShareText() {
        var text = "Reczipes Version History\n\n"
        
        for record in historyRecords {
            text += "Version \(record.versionString)\n"
            text += "Released: \(formatDate(record.releaseDate))\n\n"
            
            for change in record.changes {
                text += "• \(change)\n"
            }
            
            text += "\n---\n\n"
        }
        
        shareText = text
    }
}


// MARK: - Preview

#Preview {
    NavigationStack {
        VersionHistoryView()
    }
    .modelContainer(for: [VersionHistoryRecord.self], inMemory: true)
}
