//
//  DiabeticSettingsView.swift
//  Reczipes2
//
//  Created on 12/24/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Diabetic Settings View

struct DiabeticSettingsView: View {
    @StateObject private var settings = UserDiabeticSettings.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Diabetic-Friendly Analysis", isOn: $settings.isDiabeticEnabled)
            } header: {
                Text("Diabetic-Friendly Features")
            } footer: {
                Text("When enabled, recipes will show glycemic load estimates, carbohydrate counts, and diabetic-friendly substitution suggestions based on evidence-based dietary guidelines from reputable medical sources including the American Diabetes Association (ADA), Mayo Clinic, CDC, and NIH.")
            }
            
            if settings.isDiabeticEnabled {
                Section {
                    Toggle("Show glycemic load indicators", isOn: $settings.showGlycemicLoad)
                    Toggle("Highlight high GI ingredients", isOn: $settings.highlightHighGI)
                    Toggle("Auto-expand guidance", isOn: $settings.autoExpandGuidance)
                } header: {
                    Text("Display Options")
                } footer: {
                    Text("Glycemic load indicators help assess blood sugar impact. High GI highlights warn about ingredients that may cause rapid glucose spikes. Auto-expand shows all guidance details by default.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About Diabetic-Friendly Analysis")
                            .font(.headline)
                        
                        Text("This feature provides evidence-based analysis to help manage blood sugar levels through informed food choices:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            DiabeticInfoRow(
                                icon: "chart.line.uptrend.xyaxis",
                                title: "Glycemic Load",
                                description: "Estimates impact on blood sugar levels using the formula: GL = (GI × net carbs) / 100"
                            )
                            
                            DiabeticInfoRow(
                                icon: "leaf",
                                title: "Carbohydrate Counting",
                                description: "Total carbs, fiber, and net carbs for meal planning"
                            )
                            
                            DiabeticInfoRow(
                                icon: "cube.transparent",
                                title: "Sugar Breakdown",
                                description: "Added vs. natural sugars analysis"
                            )
                            
                            DiabeticInfoRow(
                                icon: "arrow.triangle.2.circlepath",
                                title: "Substitutions",
                                description: "Lower glycemic index alternatives based on medical guidelines"
                            )
                            
                            DiabeticInfoRow(
                                icon: "doc.text.magnifyingglass",
                                title: "Source Verification",
                                description: "Cites ADA, Mayo Clinic, CDC, NIH, and peer-reviewed journals"
                            )
                            
                            DiabeticInfoRow(
                                icon: "clock",
                                title: "Data Freshness",
                                description: "Analysis cached for 30 days, shows last updated date"
                            )
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Color.appInfo)
                                Text("How It Works")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            
                            Text("When you request analysis for a recipe:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("1.")
                                        .fontWeight(.semibold)
                                    Text("Recipe ingredients and instructions are sent to Claude AI for analysis")
                                }
                                .font(.caption)
                                
                                HStack(alignment: .top, spacing: 8) {
                                    Text("2.")
                                        .fontWeight(.semibold)
                                    Text("AI searches medical sources published 2023-2025 for current guidelines")
                                }
                                .font(.caption)
                                
                                HStack(alignment: .top, spacing: 8) {
                                    Text("3.")
                                        .fontWeight(.semibold)
                                    Text("Results include source URLs for transparency and verification")
                                }
                                .font(.caption)
                                
                                HStack(alignment: .top, spacing: 8) {
                                    Text("4.")
                                        .fontWeight(.semibold)
                                    Text("Analysis is cached locally for 30 days to improve performance")
                                }
                                .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.appSecondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(Color.appSuccess)
                                Text("Privacy Protection")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.appSuccess)
                                        .font(.caption)
                                    Text("No personal health data or diabetic status stored")
                                        .font(.caption)
                                }
                                
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.appSuccess)
                                        .font(.caption)
                                    Text("No tracking of which recipes you analyze")
                                        .font(.caption)
                                }
                                
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.appSuccess)
                                        .font(.caption)
                                    Text("All caching is local to your device only")
                                        .font(.caption)
                                }
                                
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.appSuccess)
                                        .font(.caption)
                                    Text("Feature is completely opt-in")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Medical Disclaimer", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appWarning)
                            
                            Text("This analysis is for informational purposes only and is not medical, dietary, or nutritional advice. The information provided:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• May contain errors or inaccuracies from AI analysis")
                                Text("• Uses estimates that may not reflect your individual metabolic response")
                                Text("• Is not a substitute for blood glucose monitoring or medical guidance")
                                Text("• Should not replace advice from your healthcare provider, registered dietitian, or certified diabetes educator")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                            
                            Text("Always consult with your healthcare provider or registered dietitian for personalized dietary guidance. Individual responses to foods vary based on overall health, medications, activity level, and metabolism.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .adaptiveToneBackground(.warning, baseOpacity: 0.1)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundStyle(Color.appInfo)
                                Text("Recommended Resources")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            
                            Link(destination: URL(string: "https://diabetes.org")!) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("American Diabetes Association")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        Text("diabetes.org")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                }
                                .padding(8)
                                .background(Color.appSecondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            
                            Link(destination: URL(string: "https://www.mayoclinic.org/diseases-conditions/diabetes")!) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Mayo Clinic - Diabetes")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        Text("mayoclinic.org")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                }
                                .padding(8)
                                .background(Color.appSecondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            
                            Link(destination: URL(string: "https://www.cdc.gov/diabetes")!) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("CDC - Diabetes")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        Text("cdc.gov")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                }
                                .padding(8)
                                .background(Color.appSecondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.appTertiaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                } header: {
                    Text("Information & Guidelines")
                }
            }
        }
        .navigationTitle("Diabetic-Friendly Analysis")
    }
}

// MARK: - Supporting Views

struct DiabeticInfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.appInfo)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Environment Key for Settings

struct DiabeticSettingsKey: EnvironmentKey {
    static let defaultValue = UserDiabeticSettings.shared
}

extension EnvironmentValues {
    var diabeticSettings: UserDiabeticSettings {
        get { self[DiabeticSettingsKey.self] }
        set { self[DiabeticSettingsKey.self] = newValue }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DiabeticSettingsView()
    }
}
