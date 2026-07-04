//
//  UserFODMAPSettings.swift
//  Reczipes2
//
//  User preferences for FODMAP features
//  Created on 12/20/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - FODMAP User Settings

/// User preferences for FODMAP functionality
class UserFODMAPSettings: ObservableObject {
    static let shared = UserFODMAPSettings()
    
    @AppStorage("fodmapEnabled") var isFODMAPEnabled: Bool = false
    @AppStorage("fodmapShowInlineIndicators") var showInlineIndicators: Bool = true
    @AppStorage("fodmapAutoExpandSubstitutions") var autoExpandSubstitutions: Bool = false
    
    private init() {}
    
    /// Enable FODMAP sensitivity mode
    func enableFODMAPMode() {
        isFODMAPEnabled = true
    }
    
    /// Disable FODMAP sensitivity mode
    func disableFODMAPMode() {
        isFODMAPEnabled = false
    }
}

// MARK: - FODMAP Settings View

struct FODMAPSettingsView: View {
    @StateObject private var settings = UserFODMAPSettings.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable FODMAP Features", isOn: $settings.isFODMAPEnabled)
            } header: {
                Text("FODMAP Sensitivity")
            } footer: {
                Text("When enabled, recipes will show FODMAP ingredient analysis and low FODMAP substitution suggestions based on Monash University guidelines.")
            }
            
            if settings.isFODMAPEnabled {
                Section {
                    Toggle("Show inline FODMAP indicators", isOn: $settings.showInlineIndicators)
                    Toggle("Auto-expand substitutions", isOn: $settings.autoExpandSubstitutions)
                } header: {
                    Text("Display Options")
                } footer: {
                    Text("Inline indicators show a warning next to high FODMAP ingredients. Auto-expand shows all substitution details by default.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About FODMAP")
                            .font(.headline)
                        
                        Text("FODMAPs are types of carbohydrates that can trigger digestive symptoms in sensitive individuals:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            FODMAPCategoryInfo(category: .oligosaccharides)
                            FODMAPCategoryInfo(category: .disaccharides)
                            FODMAPCategoryInfo(category: .monosaccharides)
                            FODMAPCategoryInfo(category: .polyols)
                        }
                        .padding(.vertical, 4)
                        
                        Text("This app uses guidelines from Monash University, the leading FODMAP research institution.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .navigationTitle("FODMAP Settings")
    }
}

struct FODMAPCategoryInfo: View {
    let category: FODMAPCategory
    
    var body: some View {
        HStack(spacing: 8) {
            Text(category.icon)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(category.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.appSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Environment Key for Settings

struct FODMAPSettingsKey: EnvironmentKey {
    static let defaultValue = UserFODMAPSettings.shared
}

extension EnvironmentValues {
    var fodmapSettings: UserFODMAPSettings {
        get { self[FODMAPSettingsKey.self] }
        set { self[FODMAPSettingsKey.self] = newValue }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FODMAPSettingsView()
    }
}
