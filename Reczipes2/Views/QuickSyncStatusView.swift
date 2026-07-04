//
//  QuickSyncStatusView.swift
//  Reczipes2
//
//  Ultra-simple sync status for quick checks
//

import SwiftUI
import SwiftData
import CloudKit

/// Minimal sync status view for quick at-a-glance checking
struct QuickSyncStatusView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var monitor = CloudKitSyncMonitor.shared
    
    @State private var recipeCount: Int = 0
    @State private var userID: String = "..."
    @State private var isLoading: Bool = true
    
    var body: some View {
        VStack(spacing: 20) {
            // Big status indicator
            ZStack {
                Circle()
                    .fill(monitor.statusColor.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                VStack(spacing: 8) {
                    Image(systemName: monitor.statusIcon)
                        .font(.system(size: 50))
                        .foregroundColor(monitor.statusColor)
                    
                    Text(statusText)
                        .font(.caption)
                        .bold()
                }
            }
            
            // Key info
            VStack(spacing: 12) {
                InfoCard(title: "Recipes", value: "\(recipeCount)", icon: "book.fill")
                InfoCard(title: "User ID", value: userID, icon: "key.fill")
                InfoCard(title: "Account", value: accountStatus, icon: "person.circle.fill")
            }
            .padding(.horizontal)
            
            // Action button
            Button {
                Task {
                    await refresh()
                }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isLoading ? "Checking..." : "Refresh Status")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(Color.onTint)
                .cornerRadius(12)
            }
            .disabled(isLoading)
            .padding(.horizontal)
            
            // Tips
            VStack(alignment: .leading, spacing: 8) {
                Text("For Sync to Work:")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                TipItem(text: "Same User ID on both devices")
                TipItem(text: "Keep app open for 20-30 min")
                TipItem(text: "Stay connected to Wi-Fi")
            }
            .padding()
            .background(Color.appSecondaryBackground)
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.top, 40)
        .navigationTitle("Quick Sync Check")
        .platformNavigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
        }
    }
    
    private var statusText: String {
        monitor.isSyncEnabled ? "Ready" : "Not Ready"
    }
    
    private var accountStatus: String {
        switch monitor.accountStatus {
        case .available: return "✅ Signed In"
        case .noAccount: return "❌ Not Signed In"
        default: return "⚠️ \(monitor.accountStatus)"
        }
    }
    
    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        
        // Check account
        await monitor.checkAccountStatus()
        
        // Count recipes
        let descriptor = FetchDescriptor<RecipeX>()
        if let recipes = try? modelContext.fetch(descriptor) {
            recipeCount = recipes.count
        }
        
        // Get user ID
        do {
            let container = CKContainer(identifier: "iCloud.com.headydiscy.reczipes")
            let recordID = try await container.userRecordID()
            userID = String(recordID.recordName.prefix(12)) + "..."
        } catch {
            userID = "Unable to fetch"
        }
    }
}

struct InfoCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.appSecondaryBackground)
        .cornerRadius(10)
    }
}

struct TipItem: View {
    let text: String
    
    var body: some View {
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
    NavigationStack {
        QuickSyncStatusView()
    }
}
