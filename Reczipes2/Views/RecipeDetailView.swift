//
//  RecipeDetailView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/4/25.
//

import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    let recipe: RecipeX  // ✅ Now only accepts RecipeX
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppStateManager
    
    @Query private var allergenProfiles: [UserAllergenProfile]
    
    @StateObject private var fodmapSettings = UserFODMAPSettings.shared
    @StateObject private var diabeticSettings = UserDiabeticSettings.shared
    @StateObject private var onboarding = CloudKitOnboardingService.shared
    
    @State private var showingEditor = false
    @State private var showCloudKitWarning = false
    @State private var showCloudKitOnboarding = false
    @State private var showingRemindersAlert = false
    @State private var remindersAlertMessage = ""
    @State private var isExportingToReminders = false
    @State private var showingAllergenDetail = false
    @State private var showingFODMAPSubstitutions = true // Default to showing substitutions
    @State private var showingFODMAPGuide = false
    @State private var showingAddTip = false
    @State private var newTipText = ""
    @State private var pendingTips: [RecipeNote] = [] // Tips to be saved with the recipe
    @State private var showingCookingMode = false
    @State private var currentServings: Int = 1
    @State private var showingSafariView = false
    @State private var safariURL: URL?
    @State private var showingDataInspector = false
    @State private var showingMashup = false

    // Diabetic analysis
    @State private var diabeticInfo: DiabeticInfo?
    @State private var isLoadingDiabeticInfo = false
    @State private var analysisProgress: Double = 0.0
    @State private var showPendingAnalysisAlert = false

    // Repair support
    let autoRepair: Bool
    @StateObject private var repairService: RecipeRepairService
    @State private var repairCompleted = false

    private let remindersService = RemindersService()

    // FODMAP analysis - now uses RecipeX directly
    private var fodmapAnalysis: RecipeFODMAPSubstitutions {
        FODMAPSubstitutionDatabase.shared.analyzeRecipe(recipe)
    }

    init(recipe: RecipeX, autoRepair: Bool = false) {
        self.recipe = recipe
        self.autoRepair = autoRepair
        let apiKey = APIKeyHelper.getAPIKey() ?? ""
        _repairService = StateObject(wrappedValue: RecipeRepairService(apiKey: apiKey))
    }
    
    // Active allergen profile
    private var activeProfile: UserAllergenProfile? {
        allergenProfiles.first { $0.isActive == true }
    }
    
    // Allergen score for this recipe - now simplified!
    private var allergenScore: RecipeAllergenScore? {
        guard let profile = activeProfile else { return nil }
        return AllergenAnalyzer.shared.analyzeRecipe(recipe, profile: profile)
    }
    
    // Whether recipe is saved - RecipeX instances are always saved in SwiftData
    private var isSaved: Bool {
        return true
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var allergenSection: some View {
        // Allergen Information Section (if profile is active)
        if let score = allergenScore, let profile = activeProfile {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Allergen Analysis", systemImage: "allergens")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    RecipeAllergenBadge(score: score)
                }
                
                Text("Based on \(profile.name ?? "Profile")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if !score.isSafe {
                    Button {
                        showingAllergenDetail = true
                    } label: {
                        HStack {
                            Image(systemName: "info.circle.fill")
                            Text("View Detailed Analysis")
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .adaptiveToneBackground(.warning, baseOpacity: 0.1)
                        .foregroundStyle(Color.appWarning)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 8)
            
            Divider()
        }
    }
    
    @ViewBuilder
    private var fodmapSection: some View {
        // FODMAP Substitutions Section (if there are any high FODMAP ingredients)
        if fodmapSettings.isFODMAPEnabled && fodmapAnalysis.hasSubstitutions {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("FODMAP Friendly Options", systemImage: "leaf.circle.fill")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appWarning)
                    
                    Spacer()
                    
                    Button {
                        withAnimation {
                            showingFODMAPSubstitutions.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showingFODMAPSubstitutions ? "Hide" : "Show")
                                .font(.subheadline)
                            Image(systemName: showingFODMAPSubstitutions ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.appInfo)
                    }
                }
                
                if showingFODMAPSubstitutions {
                    FODMAPSubstitutionSection(analysis: fodmapAnalysis)
                }
            }
            .padding(.vertical, 8)
            
            Divider()
        }
    }
    
    @ViewBuilder
    private var diabeticSection: some View {
        // Diabetic-Friendly Analysis Section
        // Show if diabetic mode is enabled OR if active profile has diabetes concern
        if diabeticSettings.isDiabeticEnabled || (activeProfile?.hasDiabetesConcern ?? false) {
            VStack(alignment: .leading, spacing: 12) {
                diabeticHeaderView
                
                diabeticContentView
            }
            .padding(.vertical, 8)
            
            Divider()
        }
    }
    
    @ViewBuilder
    private var diabeticHeaderView: some View {
        HStack {
            Label("Diabetic-Friendly Analysis", systemImage: "heart.text.square")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.appCritical)
            
            Spacer()
            
            // Show diabetes status badge if from profile
            if let profile = activeProfile, profile.hasDiabetesConcern {
                HStack(spacing: 4) {
                    Text(profile.diabetesStatus.icon)
                    Text(profile.diabetesStatus.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .adaptiveToneBackground(.critical, baseOpacity: 0.1)
                .foregroundStyle(Color.appCritical)
                .clipShape(Capsule())
            }
        }
        
        // Show profile note if analysis is triggered by profile diabetes status
        if let profile = activeProfile, profile.hasDiabetesConcern {
            Text("Analysis based on \(profile.name ?? "Profile") - \(profile.diabetesStatus.description)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var diabeticContentView: some View {
        if let info = diabeticInfo {
            DiabeticInfoView(info: info)
            
            // Rerun analysis button
            Button {
                Task {
                    await rerunDiabeticAnalysis()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Rerun Analysis")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .adaptiveToneBackground(.critical, baseOpacity: 0.1)
                .foregroundStyle(Color.appCritical)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isLoadingDiabeticInfo)
        } else if isLoadingDiabeticInfo {
            VStack(spacing: 12) {
                ProgressView("Analyzing recipe...", value: analysisProgress)
                    .progressViewStyle(.linear)
                    .tint(.red)
                
                Text("\(Int(analysisProgress * 100))% complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            Button {
                Task {
                    await loadDiabeticInfo()
                }
            } label: {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                    Text("Analyze for Diabetic-Friendly Info")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding()
                .adaptiveToneBackground(.critical, baseOpacity: 0.1)
                .foregroundStyle(Color.appCritical)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    @ViewBuilder
    private var nutritionalSection: some View {
        // Nutritional Analysis Section - now simplified!
        if activeProfile?.nutritionalGoals != nil || activeProfile != nil {
            VStack(alignment: .leading, spacing: 12) {
                RecipeNutritionalSection(
                    recipe: recipe,  // ✅ Direct use of RecipeX
                    profile: activeProfile,
                    servings: currentServings
                )
            }
            .padding(.vertical, 8)
            
            Divider()
        }
    }
    
    @ViewBuilder
    private var ingredientsSection: some View {
        // Ingredients Section
        VStack(alignment: .leading, spacing: 16) {
            Label("Ingredients", systemImage: "list.bullet")
                .font(.title2)
                .fontWeight(.bold)

            if recipe.ingredientSections.isEmpty {
                if repairService.isRepairing {
                    repairSpinner(label: "Retrieving ingredients...")
                } else if repairCompleted {
                    Text("Could not retrieve ingredients from source.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    Text("No ingredients available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            } else {
                ForEach(recipe.ingredientSections) { section in
                    ingredientSectionView(section)
                }
            }
        }
    }
    
    @ViewBuilder
    private func ingredientSectionView(_ section: IngredientSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = section.title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.appInfo)
                    .padding(.top, 8)
            }
            
            ForEach(section.ingredients) { ingredient in
                ingredientRowView(ingredient)
            }
            
            if let transitionNote = section.transitionNote {
                Text(transitionNote)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(Color.appWarning)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .adaptiveToneBackground(.warning, baseOpacity: 0.1)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    @ViewBuilder
    private func ingredientRowView(_ ingredient: Ingredient) -> some View {
        // Check if this ingredient has a FODMAP substitution
        let substitution = fodmapSettings.isFODMAPEnabled && fodmapSettings.showInlineIndicators
            ? FODMAPSubstitutionDatabase.shared.getSubstitutions(for: ingredient.name)
            : nil
        
        IngredientRowWithFODMAP(
            ingredient: ingredient,
            substitution: substitution
        )
    }
    
    @ViewBuilder
    private var instructionsSection: some View {
        // Instructions Section
        VStack(alignment: .leading, spacing: 16) {
            Label("Instructions", systemImage: "list.number")
                .font(.title2)
                .fontWeight(.bold)

            if recipe.instructionSections.isEmpty {
                if repairService.isRepairing {
                    repairSpinner(label: "Retrieving instructions...")
                } else if repairCompleted {
                    Text("Could not retrieve instructions from source.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    Text("No instructions available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            } else {
                ForEach(recipe.instructionSections) { section in
                    instructionSectionView(section)
                }
            }
        }
    }

    /// Animated spinner shown while repair is in progress
    @ViewBuilder
    private func repairSpinner(label: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if repairService.repairPhase == .fetchingSource {
                    Text("Fetching from source...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if repairService.repairPhase == .extracting {
                    Text("Extracting recipe data...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }
    
    @ViewBuilder
    private func instructionSectionView(_ section: InstructionSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = section.title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.appSuccess)
                    .padding(.top, 8)
            }
            
            ForEach(section.steps) { step in
                instructionStepView(step)
            }
        }
    }
    
    @ViewBuilder
    private func instructionStepView(_ step: InstructionStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if step.stepNumber > 0 {
                Text("\(step.stepNumber)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.onTint)
                    .frame(width: 32, height: 32)
                    .background(Color.green)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
            
            Text(step.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }
    
    @ViewBuilder
    private var notesSection: some View {
        // Notes Section - Always show to allow adding tips
        VStack(alignment: .leading, spacing: 12) {
            Label("Notes", systemImage: "note.text")
                .font(.title2)
                .fontWeight(.bold)
            
            notesListView
            
            addTipButtonView
        }
    }
    
    @ViewBuilder
    private var notesListView: some View {
        // Show existing notes
        ForEach(recipe.notes) { note in
            noteView(note, isPending: false)
        }
        
        // Show pending tips (not yet saved)
        ForEach(pendingTips) { note in
            noteView(note, isPending: true)
        }
        
        // Show helpful message if no notes exist yet
        if recipe.notes.isEmpty && pendingTips.isEmpty {
            Text("No notes yet. Add cooking tips, substitutions, or important reminders.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .italic()
                .padding(.vertical, 8)
        }
    }
    
    @ViewBuilder
    private func noteView(_ note: RecipeNote, isPending: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconForNoteType(note.type))
                .font(.title3)
                .foregroundStyle(colorForNoteType(note.type))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                if isPending {
                    HStack {
                        Text(note.type.rawValue.capitalized)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(colorForNoteType(note.type))
                        
                        Spacer()
                        
                        Text("Pending")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .adaptiveToneBackground(.warning, baseOpacity: 0.2)
                            .foregroundStyle(Color.appWarning)
                            .clipShape(Capsule())
                    }
                } else {
                    Text(note.type.rawValue.capitalized)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(colorForNoteType(note.type))
                }
                
                Text(note.text)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            
            if isPending {
                Button {
                    removePendingTip(note)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(colorForNoteType(note.type).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            Group {
                if isPending {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [5]))
                }
            }
        )
    }
    
    @ViewBuilder
    private var addTipButtonView: some View {
        // Add Tip Button - Always visible
        Button {
            showingAddTip = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add a Tip")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue.opacity(0.1))
            .foregroundStyle(Color.appInfo)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    @ViewBuilder
    private var referenceSection: some View {
        // Reference
        if let reference = recipe.reference {
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Reference", systemImage: "link")
                    .font(.headline)
                
                referenceContentView(reference)
            }
        }
    }
    
    @ViewBuilder
    private func referenceContentView(_ reference: String) -> some View {
        // Check if reference is a single valid URL
        if let url = URL(string: reference),
           url.scheme == "http" || url.scheme == "https",
           !reference.contains("\n") {
            // Single clickable link button
            Button {
                safariURL = url
                showingSafariView = true
            } label: {
                HStack {
                    Text(reference)
                        .font(.subheadline)
                        .foregroundStyle(Color.appInfo)
                        .underline()
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: "safari")
                        .foregroundStyle(Color.appInfo)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        } else {
            // Text with embedded URLs - make URLs clickable
            VStack(alignment: .leading, spacing: 8) {
                let lines = reference.split(separator: "\n", omittingEmptySubsequences: false)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    let lineString = String(line)
                    if let url = extractURL(from: lineString) {
                        // Line contains a URL - make it clickable
                        Button {
                            safariURL = url
                            showingSafariView = true
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lineString)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "safari")
                                    .font(.caption)
                                    .foregroundStyle(Color.appInfo)
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    } else if !lineString.trimmingCharacters(in: .whitespaces).isEmpty {
                        // Plain text line
                        Text(lineString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    // Helper function to extract URL from a line of text
    private func extractURL(from text: String) -> URL? {
        // Look for "URL: " prefix pattern first
        if let urlRange = text.range(of: "URL: "),
           let url = URL(string: String(text[urlRange.upperBound...])),
           url.scheme == "http" || url.scheme == "https" {
            return url
        }
        
        // Otherwise try to find any http/https URL in the text
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        if let match = matches?.first,
           let range = Range(match.range, in: text),
           let url = URL(string: String(text[range])),
           url.scheme == "http" || url.scheme == "https" {
            return url
        }
        
        return nil
    }
    
    @ViewBuilder
    private var recipeImageSection: some View {
        // Recipe Image - supports multiple images stored in imageData and additionalImagesData
        let imageCount = recipe.imageCount

        if imageCount > 1 {
            // Show scrollable gallery for multiple images using actual image data
            TabView {
                ForEach(0..<imageCount, id: \.self) { index in
                    if let image = recipe.getImage(at: index) {
                        Image(platformImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                            .padding(.horizontal)
                    }
                }
            }
            .platformPageTabViewStyle(indexDisplayMode: .always)
            .frame(height: 220)
            .platformPageIndexViewStyle(backgroundDisplayMode: .always)
        } else if let imageName = recipe.imageName {
            // Show single image
            RecipeImageView(
                imageName: imageName,
                imageData: recipe.imageData,
                size: nil,
                aspectRatio: .fit,
                cornerRadius: 16
            )
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 200)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .padding(.horizontal)
        } else if let imageData = recipe.imageData {
            // Direct imageData display
            RecipeImageView(
                imageName: nil,
                imageData: imageData,
                size: nil,
                aspectRatio: .fit,
                cornerRadius: 16
            )
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 200)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.title ?? "Untitled Recipe")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if let headerNotes = recipe.headerNotes {
                        Text(headerNotes)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
                
                Spacer()
                
                saveButtonSection
            }
            
            yieldSection
        }
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private var saveButtonSection: some View {
        VStack(spacing: 8) {
            // RecipeX is always saved, so just show save tips button if there are pending tips
            if !pendingTips.isEmpty {
                Button(action: { 
                    savePendingTipsToExistingRecipe()
                }) {
                    Label("Save Tips", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.onTint)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
            
            if !pendingTips.isEmpty {
                Text("\(pendingTips.count) tip\(pendingTips.count == 1 ? "" : "s") to save")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            if diabeticSettings.isDiabeticEnabled || (activeProfile?.hasDiabetesConcern ?? false) {
                RecipeDiabeticBadge.full(
                    info: diabeticInfo,
                    isLoading: isLoadingDiabeticInfo,
                    progress: analysisProgress
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.appSystemBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    @ViewBuilder
    private var yieldSection: some View {
        if let yield = recipe.yield {
            HStack {
                Label(yield, systemImage: "chart.bar.doc.horizontal")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                
                if activeProfile?.nutritionalGoals != nil {
                    Divider()
                        .frame(height: 20)
                    
                    Stepper("Servings: \(currentServings)", value: $currentServings, in: 1...20)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    @ViewBuilder
    private var mainContentSection: some View {
        Group {
            recipeImageSection
            
            headerSection
            
            Divider()
        }
        
        Group {
            allergenSection
            
            fodmapSection
            
            diabeticSection
            
            nutritionalSection
        }
    }
    
    @ViewBuilder
    private var recipeSectionsContent: some View {
        Group {
            ingredientsSection
            
            Divider()
            
            instructionsSection
        }
        
        Group {
            Divider()
            
            notesSection
            
            referenceSection
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                mainContentSection
                
                recipeSectionsContent
            }
            .padding()
        }
        .navigationTitle(recipe.title ?? "Recipe")
#if os(iOS)
        .platformNavigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
//            // CloudKit Sync Badge
//            ToolbarItem(placement: .platformNavBarTrailing) {
//                CloudKitSyncBadge()
//            }
            
            // Cooking Mode button
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCookingMode = true
                } label: {
                    Label("Cooking Mode", systemImage: "frying.pan")
                }
            }
            
            // Recipe Mashup button
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingMashup = true
                } label: {
                    Label("Recipe Mashup", systemImage: "arrow.triangle.merge")
                }
            }
//            
//            // Share button (for email, text, etc.)
//            ToolbarItem(placement: .primaryAction) {
//                RecipeShareButton(recipe: recipe)
//            }
//            
//            // Community Share button (CloudKit required)
//            ToolbarItem(placement: .primaryAction) {
//                Button {
//                    // Check CloudKit before community sharing
//                    if case .ready = onboarding.onboardingState {
//                        shareToCloudKitCommunity()
//                    } else {
//                        showCloudKitWarning = true
//                    }
//                } label: {
//                    Label("Share to Community", systemImage: "person.2.fill")
//                }
//            }
            
            // Export to Reminders button
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await exportIngredientsToReminders()
                    }
                } label: {
                    if isExportingToReminders {
                        ProgressView()
                    } else {
                        Label("Add to Reminders", systemImage: "list.bullet.clipboard")
                    }
                }
                .disabled(isExportingToReminders)
            }
            
            // FODMAP Guide button
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingFODMAPGuide = true
                } label: {
                    Label("FODMAP Guide", systemImage: "book.circle")
                }
            }
            
            // Data Inspector button (for debugging)
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingDataInspector = true
                } label: {
                    Label("Inspect Recipe Data", systemImage: "magnifyingglass.circle")
                }
            }
            
            // Edit button (only for saved recipes)
            if isSaved {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit Recipe", systemImage: "pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            RecipeEditorView(recipe: recipe)
        }
        .sheet(isPresented: $showingCookingMode) {
            NavigationStack {
                CookingModeView(recipe: recipe)
            }
        }
        .sheet(isPresented: $showingMashup) {
            RecipeMashupView(
                baseRecipe: recipe,
                apiKey: APIKeyHelper.getAPIKey() ?? ""
            )
        }
        .sheet(isPresented: $showingAllergenDetail) {
            if let score = allergenScore {
                RecipeAllergenDetailView(recipe: recipe, score: score)
            }
        }
        .sheet(isPresented: $showingFODMAPGuide) {
            FODMAPQuickReferenceView()
        }
        .sheet(isPresented: $showingDataInspector) {
            NavigationStack {
                RecipeDataInspectorView(recipe: recipe)
            }
        }
        .sheet(isPresented: $showingAddTip) {
            AddTipSheet(
                tipText: $newTipText,
                onSave: {
                    addPendingTip()
                },
                onCancel: {
                    newTipText = ""
                }
            )
            .platformPresentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSafariView) {
            if let url = safariURL {
                SafariView(url: url, entersReaderIfAvailable: true)
                    .ignoresSafeArea()
            }
        }
//        .alert("Reminders", isPresented: $showingRemindersAlert) {
//            Button("OK", role: .cancel) { }
//        } message: {
//            Text(remindersAlertMessage)
//        }
//        .alert("Community Sharing Not Available", isPresented: $showCloudKitWarning) {
//            Button("Set Up Now") {
//                showCloudKitOnboarding = true
//            }
//            Button("Cancel", role: .cancel) {}
//        } message: {
//            Text("CloudKit needs to be set up before you can share to the community. This enables recipe syncing across your devices and sharing with others.")
//        }
//        .sheet(isPresented: $showCloudKitOnboarding) {
//            CloudKitOnboardingView()
//                .environmentObject(onboarding)
//        }
        .onAppear {
            checkForPendingAnalysis()

            // Auto-load diabetic analysis if profile has diabetes concern
            if let profile = activeProfile, profile.hasDiabetesConcern, diabeticInfo == nil, !isLoadingDiabeticInfo {
                Task {
                    await loadDiabeticInfo()
                }
            }
        }
        .task(id: autoRepair) {
            // Auto-repair when triggered from the "Fix" badge
            if autoRepair && recipe.needsRepair && !repairService.isRepairing {
                await repairService.repair(recipe, in: modelContext)
                repairCompleted = true
            }
        }
        .trackTask(
            type: .diabeticAnalysis,
            recipeId: recipe.id,
            progress: analysisProgress,
            isActive: isLoadingDiabeticInfo
        )
        .alert("Resume Analysis?", isPresented: $showPendingAnalysisAlert) {
            Button("Resume") {
                Task {
                    await resumeAnalysis()
                }
            }
            Button("Cancel", role: .cancel) {
                appState.completeTask()
            }
        } message: {
            Text("You have a diabetic analysis in progress for this recipe. Would you like to resume?")
        }
    }
    
    // MARK: - Export to Reminders
    
    private func exportIngredientsToReminders() async {
        isExportingToReminders = true
        
        do {
            try await remindersService.addIngredientsToReminders(recipe: recipe)
            
            // Count total ingredients
            let totalIngredients = recipe.ingredientSections.reduce(0) { $0 + $1.ingredients.count }
            
            remindersAlertMessage = "Successfully added \(totalIngredients) ingredient\(totalIngredients == 1 ? "" : "s") to your Reminders app in a list called '\(String(describing: recipe.title))'."
            showingRemindersAlert = true
        } catch RemindersError.permissionDenied {
            remindersAlertMessage = "Permission to access Reminders was denied. Please enable it in Settings > Privacy & Security > Reminders to use this feature."
            showingRemindersAlert = true
        } catch {
            remindersAlertMessage = "Failed to add ingredients to Reminders: \(error.localizedDescription)"
            showingRemindersAlert = true
        }
        
        isExportingToReminders = false
    }
    
    // MARK: - Diabetic Analysis
    
    private func loadDiabeticInfo() async {
        isLoadingDiabeticInfo = true
        analysisProgress = 0.0
        defer { 
            isLoadingDiabeticInfo = false
            analysisProgress = 0.0
        }
        
        do {
            // Progress: Preparing request
            analysisProgress = 0.1
            AppLog.info("Starting diabetic analysis for recipe: \(recipe.safeTitle)", category: .recipe)
            
            // Get the model container from the context
            let modelContainer = modelContext.container
            
            // Progress: Container ready
            analysisProgress = 0.2
            
            // Analyze using RecipeX directly
            analysisProgress = 0.3
            AppLog.info("Analyzing RecipeX", category: .recipe)
            
            diabeticInfo = try await DiabeticAnalyzer.shared.analyzeDiabeticInfo(
                for: recipe,
                modelContainer: modelContainer
            )
            
            // Progress: Analysis complete
            analysisProgress = 1.0
            AppLog.info("Diabetic analysis completed successfully", category: .recipe)
            
        } catch {
            // Handle error - show alert to user
            AppLog.error("Diabetic analysis failed: \(error)", category: .recipe)
            remindersAlertMessage = "Failed to analyze recipe: \(error.localizedDescription)"
            showingRemindersAlert = true
        }
    }
    
    private func rerunDiabeticAnalysis() async {
        // Clear existing analysis
        diabeticInfo = nil
        
        AppLog.info("Rerunning diabetic analysis for recipe: \(recipe.safeTitle)", category: .recipe)
        
        // Rerun the analysis
        await loadDiabeticInfo()
    }
    
    // MARK: - Task Restoration
    
    private func checkForPendingAnalysis() {
        // Check if there's a pending analysis task for this recipe
        if let task = appState.activeTask,
           task.taskType == .diabeticAnalysis,
           task.recipeId == recipe.safeID {
            AppLog.info("Found pending diabetic analysis for recipe: \(recipe.safeTitle)", category: .state)
            showPendingAnalysisAlert = true
        }
    }
    
    private func resumeAnalysis() async {
        // Resume from saved progress
        guard let task = appState.activeTask,
              task.recipeId == recipe.safeID else { 
            appState.completeTask()
            return 
        }
        
        AppLog.info("Resuming diabetic analysis from progress: \(task.progress)", category: .state)
        analysisProgress = task.progress
        
        // Continue analysis from where it left off
        await loadDiabeticInfo()
    }
    
    // MARK: - Helper Functions
    
    private func addPendingTip() {
        guard !newTipText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showingAddTip = false
            return
        }
        
        let tip = RecipeNote(type: .tip, text: newTipText)
        pendingTips.append(tip)
        newTipText = ""
        showingAddTip = false
    }
    
    private func removePendingTip(_ tip: RecipeNote) {
        pendingTips.removeAll { $0.id == tip.id }
    }
    
    // saveRecipeWithTips removed - RecipeX is always saved
    
    private func savePendingTipsToExistingRecipe() {
        guard !pendingTips.isEmpty else {
            AppLog.warning("Cannot save tips - no pending tips", category: .ui)
            return
        }
        
        // Store count before clearing for the success message
        let tipCount = pendingTips.count
        
        // Get existing notes from the RecipeX
        let decoder = JSONDecoder()
        var existingNotes: [RecipeNote] = []
        if let notesData = recipe.notesData,
           let notes = try? decoder.decode([RecipeNote].self, from: notesData) {
            existingNotes = notes
        }
        
        // Add pending tips to existing notes
        let updatedNotes = existingNotes + pendingTips
        
        // Encode and save
        let encoder = JSONEncoder()
        if let encodedNotes = try? encoder.encode(updatedNotes) {
            recipe.notesData = encodedNotes
            
            // Update version tracking
            if let currentVersion = recipe.version {
                recipe.version = currentVersion + 1
            }
            recipe.lastModified = Date()
            
            // Try to save context
            do {
                try modelContext.save()
                AppLog.info("Successfully saved \(tipCount) tip(s) to recipe: \(recipe.safeTitle)", category: .ui)
                
                // Clear pending tips after successful save
                pendingTips.removeAll()
                
                // Show success feedback with correct count
                remindersAlertMessage = "Successfully added \(tipCount) tip\(tipCount == 1 ? "" : "s") to the recipe!"
                showingRemindersAlert = true
            } catch {
                AppLog.error("Failed to save tips: \(error)", category: .ui)
                remindersAlertMessage = "Failed to save tips: \(error.localizedDescription)"
                showingRemindersAlert = true
            }
        }
    }
    
    private func getAllImageNames(for recipe: RecipeX) -> [String] {
        var names: [String] = []
        
        // Add main image
        if let imageName = recipe.imageName {
            names.append(imageName)
        }
        
        // Add additionalImageNames
        if let additionalNames = recipe.additionalImageNames {
            names.append(contentsOf: additionalNames)
        }
        
        // Remove duplicates while preserving order
        let uniqueNames = names.reduce(into: [String]()) { result, item in
            if !result.contains(item) {
                result.append(item)
            }
        }
        
        // Debug: Log image count
        AppLog.debug("Recipe '\(recipe.safeTitle)' has \(uniqueNames.count) images: \(uniqueNames)", category: .image)
        
        return uniqueNames
    }
    
    private func iconForNoteType(_ type: RecipeNoteType) -> String {
        switch type {
        case .tip: return "lightbulb.fill"
        case .substitution: return "arrow.left.arrow.right"
        case .warning: return "exclamationmark.triangle.fill"
        case .timing: return "clock.fill"
        case .general: return "info.circle.fill"
        }
    }
    
    private func colorForNoteType(_ type: RecipeNoteType) -> Color {
        switch type {
        case .tip: return .blue
        case .substitution: return .orange
        case .warning: return .red
        case .timing: return .purple
        case .general: return .gray
        }
    }
    
    // MARK: - CloudKit Community Sharing
    
    private func shareToCloudKitCommunity() {
        // TODO: Implement CloudKit community sharing
        // This will create a SharedRecipe entity and share it via CloudKit
        AppLog.info("Community sharing initiated for recipe: \(recipe.safeTitle)", category: .cloudKit)
        
        // For now, show a coming soon alert
        remindersAlertMessage = "Community sharing is coming soon! Once enabled, you'll be able to share your recipes with other users and discover new recipes from the community."
        showingRemindersAlert = true
    }
}

//// MARK: - SafariView Wrapper
//
//import SafariServices
//
//struct SafariView: UIViewControllerRepresentable {
//    let url: URL
//    let entersReaderIfAvailable: Bool
//    
//    func makeUIViewController(context: Context) -> SFSafariViewController {
//        let configuration = SFSafariViewController.Configuration()
//        configuration.entersReaderIfAvailable = entersReaderIfAvailable
//        configuration.barCollapsingEnabled = true
//        
//        let safariVC = SFSafariViewController(url: url, configuration: configuration)
//        safariVC.dismissButtonStyle = .done
//        
//        return safariVC
//    }
//    
//    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
//        // No updates needed
//    }
//}
//
//// Alternative: Use the standard SwiftUI approach
//extension View {
//    func safariView(url: Binding<URL?>, isPresented: Binding<Bool>) -> some View {
//        self.sheet(isPresented: isPresented) {
//            if let url = url.wrappedValue {
//                SafariView(url: url, entersReaderIfAvailable: true)
//                    .ignoresSafeArea()
//            }
//        }
//    }
//}

// MARK: - Add Tip Sheet

struct AddTipSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var tipText: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Add a Tip", systemImage: "lightbulb.fill")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appInfo)
                    
                    Text("Share your cooking tips, tricks, or modifications for this recipe.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Add character count
                HStack {
                    Spacer()
                    Text("\(tipText.count) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                
                TextEditor(text: $tipText)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color.appGray6)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                    .focused($isFocused)
                    .padding(.horizontal)
                
                // Add a prominent save button at the bottom as well
                Button {
                    onSave()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Add Tip")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(tipText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                    .foregroundStyle(Color.onTint)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(tipText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal)
                .padding(.bottom)
                
                Spacer()
            }
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave()
                        dismiss()
                    }
                    .disabled(tipText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Auto-focus the text editor
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFocused = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        // Create a temporary RecipeX for preview
        let previewRecipe = RecipeX(
            id: UUID(),
            title: "Lassi",
            headerNotes: "Yogurt Sherbet - Very refreshing and cooling.",
            recipeYield: "Serves 1 to 2",
            reference: "See photograph, page 48.",
            ingredientSectionsData: try? JSONEncoder().encode([
                IngredientSection(
                    ingredients: [
                        Ingredient(quantity: "¾", unit: "cup", name: "plain yogurt", metricQuantity: "175", metricUnit: "mL"),
                        Ingredient(quantity: "1", unit: "cup", name: "water", metricQuantity: "250", metricUnit: "mL"),
                        Ingredient(quantity: "⅛", unit: "tsp.", name: "salt", metricQuantity: "0.5", metricUnit: "mL"),
                        Ingredient(quantity: "⅛", unit: "tsp.", name: "ground black pepper", metricQuantity: "0.5", metricUnit: "mL"),
                        Ingredient(quantity: "⅛", unit: "tsp.", name: "cumin powder", metricQuantity: "0.5", metricUnit: "mL"),
                        Ingredient(quantity: "", unit: "", name: "ice cubes")
                    ]
                )
            ]),
            instructionSectionsData: try? JSONEncoder().encode([
                InstructionSection(
                    steps: [
                        InstructionStep(stepNumber: 1, text: "Combine all ingredients in the blender and blend until smooth. Sugar can be added instead of salt and pepper, if preferred.")
                    ]
                )
            ]),
            notesData: nil,
            imageData: nil,
            additionalImagesData: nil,
            imageName: nil,
            additionalImageNames: nil,
            dateAdded: Date(),
            dateCreated: Date(),
            lastModified: Date(),
            version: 1
        )
        
        RecipeDetailView(recipe: previewRecipe)
            .modelContainer(for: [RecipeX.self, UserAllergenProfile.self], inMemory: true)
            .environmentObject(AppStateManager.shared)
    }
}
