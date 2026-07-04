//
//  DiabeticInfoView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/24/25.
//
import SwiftUI
import SwiftData

// MARK: - Main Diabetic Info Section

struct DiabeticInfoView: View {
    let info: DiabeticInfo
    @State private var showingSources = false
    @State private var expandedGuidance: Set<UUID> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("Diabetic-Friendly Analysis", systemImage: "heart.text.square")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appInfo)
                
                Spacer()
                
                ConsensusLevelBadge(level: info.consensusLevel)
            }
            
            // Medical Disclaimer
            MedicalDisclaimerBanner()
            
            // Quick summary card
            if let load = info.estimatedGlycemicLoad {
                GlycemicImpactCard(load: load)
            }
            
            // Carb breakdown
            CarbCountView(carbInfo: info.carbCount)
            
            // Guidance sections
            ForEach(info.diabeticGuidance) { guidance in
                GuidanceCard(
                    guidance: guidance,
                    isExpanded: expandedGuidance.contains(guidance.id)
                ) {
                    toggleExpanded(guidance.id)
                }
            }
            
            // Substitutions
            if !info.substitutionSuggestions.isEmpty {
                SubstitutionsSection(suggestions: info.substitutionSuggestions)
            }
            
            // Source verification footer
            SourceVerificationFooter(
                sources: info.sources,
                consensus: info.consensusLevel,
                lastUpdated: info.lastUpdated
            )
            .onTapGesture { showingSources = true }
            .sheet(isPresented: $showingSources) {
                SourcesDetailSheet(sources: info.sources)
            }
        }
    }
    
    private func toggleExpanded(_ id: UUID) {
        if expandedGuidance.contains(id) {
            expandedGuidance.remove(id)
        } else {
            expandedGuidance.insert(id)
        }
    }
}

// MARK: - Medical Disclaimer Banner

struct MedicalDisclaimerBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.appInfo)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Informational Only")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text("This analysis is not medical advice. Consult your healthcare provider.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Consensus Level Badge

struct ConsensusLevelBadge: View {
    let level: ConsensusLevel
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption)
            Text(levelText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(Capsule())
    }
    
    private var iconName: String {
        switch level {
        case .strongConsensus: return "checkmark.seal.fill"
        case .moderateConsensus: return "checkmark.circle.fill"
        case .limitedEvidence: return "info.circle"
        case .needsReview: return "exclamationmark.triangle"
        }
    }
    
    private var levelText: String {
        switch level {
        case .strongConsensus: return "Verified"
        case .moderateConsensus: return "Moderate"
        case .limitedEvidence: return "Limited"
        case .needsReview: return "Review"
        }
    }
    
    private var backgroundColor: Color {
        switch level {
        case .strongConsensus: return .green.opacity(0.2)
        case .moderateConsensus: return .blue.opacity(0.2)
        case .limitedEvidence: return .yellow.opacity(0.2)
        case .needsReview: return .orange.opacity(0.2)
        }
    }
    
    private var foregroundColor: Color {
        switch level {
        case .strongConsensus: return .green
        case .moderateConsensus: return .blue
        case .limitedEvidence: return .orange
        case .needsReview: return .red
        }
    }
}

// MARK: - Glycemic Impact Card

struct GlycemicImpactCard: View {
    let load: GlycemicLoad
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Glycemic Impact", systemImage: "waveform.path.ecg")
                    .font(.headline)
                
                Spacer()
                
                GlycemicLoadBadge(value: load.value)
            }
            
            // Visual indicator
            GlycemicLoadBar(value: load.value)
            
            if let explanation = load.explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.appSystemBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(impactColor.opacity(0.3), lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var impactColor: Color {
        if load.value <= 10 { return .green }
        else if load.value <= 20 { return .yellow }
        else { return .red }
    }
}

struct GlycemicLoadBadge: View {
    let value: Double
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(value))")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(impactColor)
            
            Text(impactLevel)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(impactColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(impactColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var impactLevel: String {
        if value <= 10 { return "Low" }
        else if value <= 20 { return "Medium" }
        else { return "High" }
    }
    
    private var impactColor: Color {
        if value <= 10 { return .green }
        else if value <= 20 { return .yellow }
        else { return .red }
    }
}

struct GlycemicLoadBar: View {
    let value: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.appGray5)
                
                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(fillColor)
                    .frame(width: min(geometry.size.width * CGFloat(value / 30.0), geometry.size.width))
            }
        }
        .frame(height: 8)
    }
    
    private var fillColor: Color {
        if value <= 10 { return .green }
        else if value <= 20 { return .yellow }
        else { return .red }
    }
}

// MARK: - Carb Count View

struct CarbCountView: View {
    let carbInfo: CarbInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Carbohydrate Breakdown", systemImage: "chart.pie")
                .font(.headline)
            
            HStack(spacing: 20) {
                CarbMetric(
                    title: "Total Carbs",
                    value: carbInfo.totalCarbs,
                    unit: "g",
                    color: .blue
                )
                
                CarbMetric(
                    title: "Net Carbs",
                    value: carbInfo.netCarbs,
                    unit: "g",
                    color: .purple
                )
                
                CarbMetric(
                    title: "Fiber",
                    value: carbInfo.fiber,
                    unit: "g",
                    color: .green
                )
            }
        }
        .padding()
        .background(Color.appGray6)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CarbMetric: View {
    let title: String
    let value: Double
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(value))")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Guidance Card

struct GuidanceCard: View {
    let guidance: GuidanceItem
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: guidance.icon)
                        .font(.title3)
                        .foregroundStyle(guidance.swiftUIColor)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(guidance.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        if !isExpanded {
                            Text(guidance.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(guidance.detailedExplanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if let tips = guidance.practicalTips, !tips.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tips:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            
                            ForEach(tips, id: \.self) { tip in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                    Text(tip)
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding()
        .background(Color.appSystemBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appGray4, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Substitutions Section

struct SubstitutionsSection: View {
    let suggestions: [IngredientSubstitution]
    @State private var expandedSubstitutions: Set<UUID> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Healthier Alternatives", systemImage: "arrow.triangle.swap")
                .font(.headline)
            
            ForEach(suggestions) { substitution in
                SubstitutionCard(
                    substitution: substitution,
                    isExpanded: expandedSubstitutions.contains(substitution.id)
                ) {
                    toggleExpanded(substitution.id)
                }
            }
        }
    }
    
    private func toggleExpanded(_ id: UUID) {
        if expandedSubstitutions.contains(id) {
            expandedSubstitutions.remove(id)
        } else {
            expandedSubstitutions.insert(id)
        }
    }
}

struct SubstitutionCard: View {
    let substitution: IngredientSubstitution
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(substitution.originalIngredient)
                            .font(.subheadline)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(Color.appSuccess)
                            
                            Text(substitution.substitute)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded, let reason = substitution.reason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.appGray6)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Source Verification Footer

struct SourceVerificationFooter: View {
    let sources: [VerifiedSource]
    let consensus: ConsensusLevel
    let lastUpdated: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Based on \(sources.count) verified source\(sources.count == 1 ? "" : "s")")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text("Last updated: \(lastUpdated, style: .date)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("Tap to view")
                    .font(.caption2)
                    .foregroundStyle(Color.appInfo)
            }
        }
        .padding()
        .background(Color.appGray6.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Sources Detail Sheet

struct SourcesDetailSheet: View {
    let sources: [VerifiedSource]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(sources) { source in
                VStack(alignment: .leading, spacing: 8) {
                    Text(source.title)
                        .font(.headline)
                    
                    if let organization = source.organization {
                        Text(organization)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let url = source.url {
                        Link(destination: url) {
                            HStack {
                                Text("View Source")
                                    .font(.caption)
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.caption)
                            }
                        }
                    }
                    
                    if let publishDate = source.publishDate {
                        Text("Published: \(publishDate, style: .date)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Verified Sources")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        DiabeticInfoView(info: DiabeticInfo(
            id: UUID(),
            recipeId: UUID(),
            lastUpdated: Date(),
            estimatedGlycemicLoad: GlycemicLoad(value: 15.0, explanation: "Moderate impact due to whole grain pasta"),
            glycemicImpactFactors: [],
            carbCount: CarbInfo(totalCarbs: 45.0, netCarbs: 38.0, fiber: 7.0),
            fiberContent: FiberInfo(total: 7.0, soluble: 3.0, insoluble: 4.0),
            sugarBreakdown: SugarBreakdown(total: 8.0, added: 2.0, natural: 6.0),
            diabeticGuidance: [
                GuidanceItem(
                    id: UUID(),
                    title: "Pair with Protein",
                    summary: "Add lean protein to slow glucose absorption",
                    detailedExplanation: "Protein helps moderate blood sugar spikes by slowing carbohydrate digestion.",
                    icon: "fork.knife",
                    color: .blue,
                    practicalTips: ["Add grilled chicken", "Include beans or lentils"]
                )
            ],
            portionRecommendations: nil,
            substitutionSuggestions: [
                IngredientSubstitution(
                    id: UUID(),
                    originalIngredient: "White rice",
                    substitute: "Cauliflower rice",
                    reason: "Lower glycemic impact and reduced carbohydrate content"
                )
            ],
            sources: [
                VerifiedSource(
                    id: UUID(),
                    title: "Glycemic Index Guide",
                    organization: "American Diabetes Association",
                    url: URL(string: "https://diabetes.org"),
                    publishDate: Date()
                )
            ],
            consensusLevel: .strongConsensus
        ))
        .padding()
    }
}
