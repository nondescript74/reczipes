//
//  RecipeAllergenBadge.swift
//  Reczipes2
//
//  Created on 12/17/25.
//

import SwiftUI

// MARK: - Recipe Allergen Badge (for list views)

struct RecipeAllergenBadge: View {
    let score: RecipeAllergenScore
    let compact: Bool
    
    init(score: RecipeAllergenScore, compact: Bool = false) {
        self.score = score
        self.compact = compact
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if score.isSafe {
                if !compact {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("Safe")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(severityColor)
                
                if !compact {
                    Text(score.scoreLabel)
                        .font(.caption)
                        .foregroundStyle(severityColor)
                }
            }
        }
    }
    
    private var severityColor: Color {
        guard let severity = score.severityLevel else { return .yellow }
        switch severity.color {
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Detailed Allergen Analysis View

struct RecipeAllergenDetailView: View {
    let recipe: RecipeX
    let score: RecipeAllergenScore
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // Overall Safety Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Safety Score")
                                .font(.headline)
                            Text(score.scoreLabel)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(overallColor)
                        }
                        
                        Spacer()
                        
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .trim(from: 0, to: scorePercentage)
                                .stroke(overallColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .frame(width: 80, height: 80)
                                .rotationEffect(.degrees(-90))
                            
                            Text(String(format: "%.0f", score.score))
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Overall Assessment")
                }
                
                // Detected Allergens Section
                if !score.detectedAllergens.isEmpty {
                    Section {
                        ForEach(score.detectedAllergens) { detected in
                            DetectedAllergenRow(detected: detected)
                        }
                    } header: {
                        Text("Detected Allergens (\(score.detectedAllergens.count))")
                    }
                } else {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title2)
                            Text("No allergens detected based on your profile")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Recommendation Section
                Section {
                    Text(recommendationText)
                        .font(.body)
                } header: {
                    Text("Recommendation")
                }
            }
            .navigationTitle(recipe.title ?? "Untitled Recipe")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .platformNavBarTrailing) {
                    CloudKitSyncBadge()
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var scorePercentage: CGFloat {
        min(score.score / 20.0, 1.0) // Cap at 20 for display
    }
    
    private var overallColor: Color {
        if score.isSafe { return .green }
        if score.score < 5 { return .yellow }
        if score.score < 10 { return .orange }
        return .red
    }
    
    private var recommendationText: String {
        if score.isSafe {
            return "This recipe appears safe based on your allergen profile. Always check ingredient labels carefully."
        } else if score.score < 5 {
            return "This recipe contains minor allergens based on your profile. Consider substitutions or proceed with caution."
        } else if score.score < 10 {
            return "This recipe contains moderate allergens. We recommend finding alternatives or making significant substitutions."
        } else {
            return "This recipe contains severe allergens based on your profile. We strongly recommend avoiding this recipe."
        }
    }
}

// MARK: - Detected Allergen Row

struct DetectedAllergenRow: View {
    let detected: DetectedAllergen
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(detected.sensitivity.icon)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detected.sensitivity.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Text("\(detected.matchedIngredients.count) ingredient\(detected.matchedIngredients.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text(detected.sensitivity.severity.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(severityColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    Text("Found in:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(detected.matchedIngredients, id: \.self) { ingredient in
                        HStack {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundStyle(.secondary)
                            Text(ingredient)
                                .font(.callout)
                        }
                    }
                    
                    if !detected.matchedKeywords.isEmpty {
                        Text("Matched keywords: \(detected.matchedKeywords.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var severityColor: Color {
        switch detected.sensitivity.severity.color {
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Allergen Filter View (for ContentView)

struct AllergenFilterBar: View {
    @Binding var filterEnabled: Bool
    @Binding var showOnlySafe: Bool
    let activeProfile: UserAllergenProfile?
    let onProfileTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button {
                onProfileTap()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "allergens")
                    Text(activeProfile?.name ?? "No Profile")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
            }
            
            if activeProfile != nil {
                Toggle(isOn: $filterEnabled) {
                    Text("Filter")
                        .font(.subheadline)
                }
                .toggleStyle(.switch)
                .fixedSize()
                
                if filterEnabled {
                    Toggle(isOn: $showOnlySafe) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                            Text("Safe Only")
                                .font(.subheadline)
                        }
                    }
                    .toggleStyle(.button)
                    .tint(.green)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

#Preview("Safe Recipe") {
    RecipeAllergenBadge(
        score: RecipeAllergenScore(
            recipeID: UUID(),
            score: 0,
            detectedAllergens: [],
            isSafe: true,
            severityLevel: nil
        )
    )
}

#Preview("Risky Recipe") {
    RecipeAllergenBadge(
        score: RecipeAllergenScore(
            recipeID: UUID(),
            score: 8.5,
            detectedAllergens: [],
            isSafe: false,
            severityLevel: .severe
        )
    )
}
