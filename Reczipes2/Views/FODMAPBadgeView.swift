//
//  FODMAPBadgeView.swift
//  Reczipes2
//
//  Badge components for displaying FODMAP scores on recipes
//  Created on 12/18/25.
//

import SwiftUI

// MARK: - FODMAP Badge View (Compact - for Recipe List)

struct FODMAPBadgeView: View {
    let recommendation: FODMAPRecommendation
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption)
            Text(recommendation.rawValue)
                .font(.caption2)
                .bold()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.2))
        .foregroundStyle(badgeColor)
        .clipShape(Capsule())
    }
    
    private var iconName: String {
        switch recommendation {
        case .safe: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .modify: return "wrench.fill"
        case .avoid: return "xmark.circle.fill"
        }
    }
    
    private var badgeColor: Color {
        switch recommendation.color {
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Standard Badge (for Detail Views)

struct StandardFODMAPBadge: View {
    let score: EnhancedFODMAPScore
    
    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: iconName)
                .font(.body)
                .foregroundStyle(badgeColor)
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text("FODMAP")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Text(score.combinedRecommendation.rawValue.components(separatedBy: " - ").last ?? "Unknown")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(badgeColor)
            }
            
            // Score
            if score.basicAnalysis.overallScore > 0 {
                Text("\(Int(score.basicAnalysis.overallScore))")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.onTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(badgeColor)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(badgeColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(badgeColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var iconName: String {
        switch score.combinedRecommendation {
        case .safe: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .modify: return "wrench.and.screwdriver.fill"
        case .avoid: return "xmark.circle.fill"
        }
    }
    
    private var badgeColor: Color {
        switch score.combinedRecommendation.color {
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Compact Badge (Alternative)

struct CompactFODMAPBadge: View {
    let score: EnhancedFODMAPScore
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
            
            Text("FODMAP")
                .font(.caption2)
                .fontWeight(.medium)
            
            if score.basicAnalysis.overallScore > 0 {
                Text("\(Int(score.basicAnalysis.overallScore))")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.onTint)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(badgeColor)
                    .clipShape(Capsule())
            }
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.15))
        .clipShape(Capsule())
    }
    
    private var iconName: String {
        switch score.combinedRecommendation {
        case .safe: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .modify: return "wrench.fill"
        case .avoid: return "xmark.circle.fill"
        }
    }
    
    private var badgeColor: Color {
        switch score.combinedRecommendation.color {
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Loading Badges

struct StandardLoadingBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            
            Text("Analyzing FODMAP...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.appGray6)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CompactLoadingBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.mini)
            
            Text("FODMAP")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.appGray6)
        .clipShape(Capsule())
    }
}

// MARK: - FODMAP Analysis Detail View

struct FODMAPAnalysisDetailView: View {
    let score: EnhancedFODMAPScore
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with overall recommendation
                    FODMAPRecommendationCard(recommendation: score.combinedRecommendation)
                    
                    // FODMAP Category Breakdown
                    FODMAPCategoryBreakdownView(breakdown: score.basicAnalysis.categoryBreakdown)
                    
                    // Detected High FODMAP Foods
                    if !score.basicAnalysis.detectedFoods.isEmpty {
                        DetectedFODMAPFoodsView(foods: score.basicAnalysis.detectedFoods)
                    }
                    
                    // Claude's Additional Insights (if available)
                    if let claude = score.claudeAnalysis {
                        ClaudeFODMAPInsightsView(analysis: claude)
                    }
                    
                    // Low FODMAP Alternatives
                    if !score.allAlternatives.isEmpty {
                        LowFODMAPAlternativesView(alternatives: score.allAlternatives)
                    }
                    
                    // Modification Tips
                    if !score.modificationTips.isEmpty {
                        ModificationTipsView(tips: score.modificationTips)
                    }
                    
                    // Monash University Attribution
                    MonashAttributionView()
                }
                .padding()
            }
            .navigationTitle("FODMAP Analysis")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - FODMAP Recommendation Card

struct FODMAPRecommendationCard: View {
    let recommendation: FODMAPRecommendation
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon and title
            HStack(spacing: 16) {
                Image(systemName: iconForRecommendation)
                    .font(.system(size: 40))
                    .foregroundStyle(colorForRecommendation)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("FODMAP Level")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(recommendation.rawValue)
                        .font(.title2)
                        .bold()
                        .foregroundStyle(colorForRecommendation)
                }
                
                Spacer()
            }
            
            // Description
            Text(descriptionForRecommendation)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(colorForRecommendation.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var iconForRecommendation: String {
        switch recommendation {
        case .safe: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .modify: return "wrench.and.screwdriver.fill"
        case .avoid: return "xmark.circle.fill"
        }
    }
    
    private var colorForRecommendation: Color {
        switch recommendation.color {
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
    
    private var descriptionForRecommendation: String {
        switch recommendation {
        case .safe:
            return "This recipe appears to be low FODMAP and suitable for a low FODMAP diet. Always verify ingredients and portion sizes."
        case .caution:
            return "This recipe contains some moderate FODMAP ingredients. Pay attention to portion sizes."
        case .modify:
            return "This recipe contains high FODMAP ingredients but can be modified. See suggested alternatives below."
        case .avoid:
            return "This recipe contains multiple high FODMAP ingredients and is not recommended for a low FODMAP diet without significant modifications."
        }
    }
}

// MARK: - FODMAP Category Breakdown

struct FODMAPCategoryBreakdownView: View {
    let breakdown: [FODMAPCategory: FODMAPCategoryScore]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FODMAP Categories")
                .font(.headline)
            
            VStack(spacing: 12) {
                ForEach(FODMAPCategory.allCases, id: \.self) { category in
                    if let score = breakdown[category] {
                        FODMAPCategoryRow(categoryScore: score)
                    }
                }
            }
        }
        .padding()
        .background(Color.appSystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Category Score Row

struct FODMAPCategoryRow: View {
    let categoryScore: FODMAPCategoryScore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(categoryScore.category.icon)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(categoryScore.category.rawValue)
                        .font(.subheadline)
                        .bold()
                    
                    Text(categoryScore.category.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Level badge
                Text(categoryScore.level.rawValue)
                    .font(.caption)
                    .bold()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(levelColor.opacity(0.2))
                    .foregroundStyle(levelColor)
                    .clipShape(Capsule())
            }
            
            // Detected ingredients in this category
            if !categoryScore.detectedIngredients.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    FlowLayoutFAV(spacing: 6) {
                        ForEach(categoryScore.detectedIngredients, id: \.self) { ingredient in
                            Text(ingredient)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.appGray6)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.appGray6.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var levelColor: Color {
        switch categoryScore.level.color {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Detected FODMAP Foods

struct DetectedFODMAPFoodsView: View {
    let foods: [DetectedFODMAPFood]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("High FODMAP Ingredients Detected")
                .font(.headline)
            
            VStack(spacing: 10) {
                ForEach(foods) { food in
                    DetectedFODMAPFoodRow(food: food)
                }
            }
        }
        .padding()
        .background(Color.appSystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct DetectedFODMAPFoodRow: View {
    let food: DetectedFODMAPFood
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // FODMAP category icons
                HStack(spacing: 4) {
                    ForEach(food.foodData.categories, id: \.self) { category in
                        Text(category.icon)
                            .font(.caption)
                    }
                }
                
                Text(food.matchedIngredient)
                    .font(.subheadline)
                    .bold()
                
                Spacer()
                
                // Level badge
                Text(food.foodData.level.rawValue)
                    .font(.caption2)
                    .bold()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .adaptiveToneBackground(.critical, baseOpacity: 0.2)
                    .foregroundStyle(Color.appCritical)
                    .clipShape(Capsule())
            }
            
            // FODMAP type
            Text(food.foodData.categories.map { $0.rawValue }.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Serving size info
            if let servingSize = food.foodData.servingSize {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption2)
                    Text("Serving: \(servingSize)")
                        .font(.caption)
                }
                .foregroundStyle(Color.appWarning)
            }
            
            // Additional notes
            if let notes = food.foodData.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            
            // Portion concern indicator
            if food.portionConcern {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                    Text("Portion size matters - may be acceptable in small amounts")
                        .font(.caption)
                }
                .foregroundStyle(Color.appInfo)
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.appGray6.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Claude FODMAP Insights

struct ClaudeFODMAPInsightsView: View {
    let analysis: ClaudeFODMAPAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("AI-Enhanced Analysis")
                    .font(.headline)
            }
            
            if !analysis.overallGuidance.isEmpty {
                Text(analysis.overallGuidance)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            if let monashNotes = analysis.monashNotes {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "book.fill")
                            .foregroundStyle(Color.appInfo)
                        Text("Monash University Guidance")
                            .font(.subheadline)
                            .bold()
                    }
                    
                    Text(monashNotes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color.appSystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Low FODMAP Alternatives

struct LowFODMAPAlternativesView: View {
    let alternatives: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.appSuccess)
                Text("Low FODMAP Alternatives")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(alternatives, id: \.self) { alternative in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.appSuccess)
                            .padding(.top, 2)
                        
                        Text(alternative)
                            .font(.body)
                    }
                }
            }
        }
        .padding()
        .background(Color.appSystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Modification Tips

struct ModificationTipsView: View {
    let tips: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("Recipe Modification Tips")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.body)
                            .bold()
                            .foregroundStyle(.secondary)
                        
                        Text(tip)
                            .font(.body)
                    }
                }
            }
        }
        .padding()
        .background(Color.appSystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Monash Attribution

struct MonashAttributionView: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.appInfo)
                Text("About FODMAP Data")
                    .font(.subheadline)
                    .bold()
            }
            
            Text("FODMAP analysis is based on research from Monash University, the creators of the Low FODMAP Diet. For the most accurate and up-to-date information, consult a registered dietitian and visit the official Monash FODMAP app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Link(destination: URL(string: "https://www.monashfodmap.com")!) {
                HStack {
                    Text("Learn More at Monash University")
                        .font(.caption)
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.appGray6.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayoutFAV: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}


// MARK: - Previews

#Preview("FODMAP Badges") {
    VStack(spacing: 20) {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compact Badges")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                FODMAPBadgeView(recommendation: .safe)
                FODMAPBadgeView(recommendation: .caution)
                FODMAPBadgeView(recommendation: .modify)
                FODMAPBadgeView(recommendation: .avoid)
            }
        }
        
        Divider()
        
        VStack(alignment: .leading, spacing: 12) {
            Text("Loading States")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                StandardLoadingBadge()
                CompactLoadingBadge()
            }
        }
    }
    .padding()
}

#Preview("FODMAP Analysis Detail") {
    // Create sample data
    let sampleRecipe = RecipeX()
    sampleRecipe.id = UUID()
    sampleRecipe.title = "Pasta with Garlic and Mushrooms"
    sampleRecipe.recipeYield = "4 servings"
    
    // Create ingredient sections
    let ingredientSection = IngredientSection(
        title: "Main Ingredients",
        ingredients: [
            Ingredient(name: "pasta"),
            Ingredient(name: "garlic"),
            Ingredient(name: "button mushrooms")
        ]
    )
    if let ingredientData = try? JSONEncoder().encode([ingredientSection]) {
        sampleRecipe.ingredientSectionsData = ingredientData
    }
    
    // Create instruction sections
    let instructionSection = InstructionSection(
        title: "Cooking",
        steps: [
            InstructionStep(stepNumber: 1, text: "Cook pasta according to package directions.")
        ]
    )
    if let instructionData = try? JSONEncoder().encode([instructionSection]) {
        sampleRecipe.instructionSectionsData = instructionData
    }
    
    let sampleFoodData1 = FODMAPFoodData(
        name: "garlic",
        categories: [.oligosaccharides],
        level: .high,
        servingSize: "any amount",
        notes: "Very high in fructans"
    )
    
    let sampleFoodData2 = FODMAPFoodData(
        name: "mushroom",
        categories: [.polyols],
        level: .high,
        servingSize: ">1/2 cup",
        notes: "High in mannitol"
    )
    
    let detectedFoods = [
        DetectedFODMAPFood(foodData: sampleFoodData1, matchedIngredient: "garlic", portionConcern: false),
        DetectedFODMAPFood(foodData: sampleFoodData2, matchedIngredient: "button mushrooms", portionConcern: true)
    ]
    
    let categoryBreakdown: [FODMAPCategory: FODMAPCategoryScore] = [
        .oligosaccharides: FODMAPCategoryScore(category: .oligosaccharides, score: 10.0, level: .high, detectedIngredients: ["garlic", "wheat pasta"]),
        .polyols: FODMAPCategoryScore(category: .polyols, score: 3.0, level: .moderate, detectedIngredients: ["mushrooms"])
    ]
    
    let basicAnalysis = FODMAPAnalysisResult(
        recipeID: sampleRecipe.id ?? UUID(),
        overallScore: 13.0,
        categoryBreakdown: categoryBreakdown,
        detectedFoods: detectedFoods,
        recommendation: .modify,
        lowFODMAPAlternatives: [
            "Use garlic-infused oil (strain out solids)",
            "Replace wheat pasta with gluten-free pasta",
            "Use oyster mushrooms in small amounts"
        ]
    )
    
    let enhancedScore = EnhancedFODMAPScore(
        basicAnalysis: basicAnalysis,
        claudeAnalysis: nil,
        recipe: sampleRecipe
    )
    
    return FODMAPAnalysisDetailView(score: enhancedScore)
}

