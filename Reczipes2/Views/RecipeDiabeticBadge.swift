//
//  RecipeDiabeticBadge.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/28/25.
//

import SwiftUI

// MARK: - Recipe Diabetic Badge

struct RecipeDiabeticBadge: View {
    let info: DiabeticInfo?
    let isLoading: Bool
    let progress: Double
    let compact: Bool
    
    init(info: DiabeticInfo?, isLoading: Bool = false, progress: Double = 0.0, compact: Bool = false) {
        self.info = info
        self.isLoading = isLoading
        self.progress = progress
        self.compact = compact
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if isLoading {
                // Show progress indicator while loading
                if compact {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Analyzing...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if progress > 0 {
                                Text("\(Int(progress * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if let info = info {
                // Show diabetic-friendly status
                if isDiabeticFriendly(info) {
                    if !compact {
                        Image(systemName: "heart.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                        Text("Diabetic-Friendly")
                            .font(.caption)
                            .foregroundStyle(Color.appSuccess)
                    } else {
                        Image(systemName: "heart.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                    }
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(impactColor(info))
                    
                    if !compact {
                        Text(impactLabel(info))
                            .font(.caption)
                            .foregroundStyle(impactColor(info))
                    }
                }
            } else {
                // No analysis available
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.gray)
                
                if !compact {
                    Text("Not Analyzed")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func isDiabeticFriendly(_ info: DiabeticInfo) -> Bool {
        // Consider diabetic-friendly if:
        // 1. Low glycemic load (< 10)
        // 2. Low-medium glycemic impact factors
        // 3. Good fiber content (>= 3g per serving)
        
        let hasLowGlycemicLoad = info.estimatedGlycemicLoad?.value ?? 100 < 10
        let hasGoodFiber = info.fiberContent.total >= 3.0
        
        // Check if most factors are low-medium impact
        let highImpactCount = info.glycemicImpactFactors.filter { $0.impact == .high }.count
        let hasLowImpact = highImpactCount <= 1 // Allow 1 high impact ingredient
        
        return hasLowGlycemicLoad && hasLowImpact && hasGoodFiber
    }
    
    private func impactColor(_ info: DiabeticInfo) -> Color {
        let glycemicLoad = info.estimatedGlycemicLoad?.value ?? 100
        
        if glycemicLoad < 10 {
            return .green
        } else if glycemicLoad < 20 {
            return .yellow
        } else {
            return .orange
        }
    }
    
    private func impactLabel(_ info: DiabeticInfo) -> String {
        let glycemicLoad = info.estimatedGlycemicLoad?.value ?? 100
        
        if glycemicLoad < 10 {
            return "Low Impact"
        } else if glycemicLoad < 20 {
            return "Moderate Impact"
        } else {
            return "High Impact"
        }
    }
}

// MARK: - Badge Variants

extension RecipeDiabeticBadge {
    /// Compact badge for list views
    static func compact(info: DiabeticInfo?, isLoading: Bool = false, progress: Double = 0.0) -> RecipeDiabeticBadge {
        RecipeDiabeticBadge(info: info, isLoading: isLoading, progress: progress, compact: true)
    }
    
    /// Full badge for detail views
    static func full(info: DiabeticInfo?, isLoading: Bool = false, progress: Double = 0.0) -> RecipeDiabeticBadge {
        RecipeDiabeticBadge(info: info, isLoading: isLoading, progress: progress, compact: false)
    }
}

// MARK: - Preview

#Preview("Diabetic-Friendly") {
    RecipeDiabeticBadge(
        info: DiabeticInfo(
            id: UUID(),
            recipeId: UUID(),
            lastUpdated: Date(),
            estimatedGlycemicLoad: GlycemicLoad(value: 8.0),
            glycemicImpactFactors: [
                GlycemicFactor(ingredient: "Oats", glycemicIndex: 55, impact: .low, explanation: "Low GI")
            ],
            carbCount: CarbInfo(totalCarbs: 30, netCarbs: 25, fiber: 5),
            fiberContent: FiberInfo(total: 5.0),
            sugarBreakdown: SugarBreakdown(total: 5.0, added: 0.0, natural: 5.0),
            diabeticGuidance: [],
            portionRecommendations: nil,
            substitutionSuggestions: [],
            sources: [],
            consensusLevel: .strongConsensus
        ),
        isLoading: false,
        progress: 0.0,
        compact: false
    )
}

#Preview("High Impact") {
    RecipeDiabeticBadge(
        info: DiabeticInfo(
            id: UUID(),
            recipeId: UUID(),
            lastUpdated: Date(),
            estimatedGlycemicLoad: GlycemicLoad(value: 25.0),
            glycemicImpactFactors: [
                GlycemicFactor(ingredient: "White Rice", glycemicIndex: 85, impact: .high, explanation: "High GI")
            ],
            carbCount: CarbInfo(totalCarbs: 60, netCarbs: 58, fiber: 2),
            fiberContent: FiberInfo(total: 2.0),
            sugarBreakdown: SugarBreakdown(total: 10.0, added: 5.0, natural: 5.0),
            diabeticGuidance: [],
            portionRecommendations: nil,
            substitutionSuggestions: [],
            sources: [],
            consensusLevel: .strongConsensus
        ),
        isLoading: false,
        progress: 0.0,
        compact: false
    )
}

#Preview("Loading") {
    RecipeDiabeticBadge(
        info: nil,
        isLoading: true,
        progress: 0.65,
        compact: false
    )
}

#Preview("Not Analyzed") {
    RecipeDiabeticBadge(
        info: nil,
        isLoading: false,
        progress: 0.0,
        compact: false
    )
}

#Preview("Compact - Friendly") {
    RecipeDiabeticBadge.compact(
        info: DiabeticInfo(
            id: UUID(),
            recipeId: UUID(),
            lastUpdated: Date(),
            estimatedGlycemicLoad: GlycemicLoad(value: 8.0),
            glycemicImpactFactors: [],
            carbCount: CarbInfo(totalCarbs: 30, netCarbs: 25, fiber: 5),
            fiberContent: FiberInfo(total: 5.0),
            sugarBreakdown: SugarBreakdown(total: 5.0, added: 0.0, natural: 5.0),
            diabeticGuidance: [],
            portionRecommendations: nil,
            substitutionSuggestions: [],
            sources: [],
            consensusLevel: .strongConsensus
        )
    )
}
