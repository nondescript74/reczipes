//
//  CloudKitSettingsView.swift
//  Reczipes2
//
//  Created for CloudKit sync settings
//

import SwiftUI

/// Settings view for CloudKit sync
struct CloudKitSettingsView: View {
    @StateObject private var monitor = CloudKitSyncMonitor.shared
    @State private var showingInfo = false
    
    var body: some View {
        Form {
            Section {
                CloudKitSyncStatusView()
            } header: {
                Text("Sync Status")
            } footer: {
                Text("Your recipes, notes, and settings are automatically synced across all your devices signed in with the same iCloud account.")
            }
            
            Section {
                Button {
                    showingInfo = true
                } label: {
                    Label("How Sync Works", systemImage: "info.circle")
                }
            } header: {
                Text("Information")
            }
        }
        .navigationTitle("iCloud Sync")
        .sheet(isPresented: $showingInfo) {
            NavigationView {
                CloudKitInfoView()
            }
        }
    }
}

// MARK: - Info View

struct CloudKitInfoView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.appInfo)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top)
                
                Text("How iCloud Sync Works")
                    .font(.title)
                    .bold()
                
                infoSection(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Automatic Syncing",
                    description: "All your recipes, notes, and settings are automatically synced across all your devices. Changes on one device appear on all others within seconds."
                )
                
                infoSection(
                    icon: "lock.shield.fill",
                    title: "Private & Secure",
                    description: "Your data is stored in your personal iCloud account and encrypted in transit. Only you can access your recipes."
                )
                
                infoSection(
                    icon: "network",
                    title: "Works Offline",
                    description: "You can add and edit recipes even without an internet connection. They'll sync automatically when you're back online."
                )
                
                infoSection(
                    icon: "photo.stack.fill",
                    title: "Images Included",
                    description: "Recipe images are synced along with your data. Make sure you have enough iCloud storage for your photo library."
                )
                
                infoSection(
                    icon: "exclamationmark.triangle.fill",
                    title: "Conflict Resolution",
                    description: "If you edit the same recipe on two devices while offline, iCloud will keep the most recent change when syncing."
                )
                
                Divider()
                    .padding(.vertical)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Requirements")
                        .font(.headline)
                    
                    requirementRow(text: "iOS 17 or later (macOS 14 or later for Mac)")
                    requirementRow(text: "Signed in to iCloud")
                    requirementRow(text: "iCloud Drive enabled")
                    requirementRow(text: "Sufficient iCloud storage")
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("About Sync")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
    
    private func infoSection(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.appInfo)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func requirementRow(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.appSuccess)
                .font(.caption)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationView {
        CloudKitSettingsView()
    }
}

#Preview("Info") {
    NavigationView {
        CloudKitInfoView()
    }
}
