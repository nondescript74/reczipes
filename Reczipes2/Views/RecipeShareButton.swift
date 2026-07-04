//
//  RecipeShareButton.swift
//  Reczipes2
//
//  Created for recipe sharing functionality
//

import SwiftUI
import Combine

/// A reusable button for sharing recipes via email, text, or other methods
struct RecipeShareButton: View {
    let recipe: RecipeX
    @StateObject private var sharingService = RecipeSharingService()
    @State private var showingShareOptions = false
    @State private var showingSetupHelp = false
    @State private var setupHelpMessage = ""
    @State private var setupHelpTitle = ""
    
    var body: some View {
        Menu {
            // Email option
            Button {
                if sharingService.canSendEmail {
                    sharingService.shareViaEmail(recipe: recipe)
                } else {
                    setupHelpTitle = "Email Not Available"
                    setupHelpMessage = """
                    Email is not configured on this device. To use email sharing:
                    
                    1. Open the Settings app
                    2. Scroll down and tap "Mail"
                    3. Tap "Accounts"
                    4. Tap "Add Account"
                    5. Choose your email provider and sign in
                    
                    Once configured, you'll be able to share recipes via email.
                    
                    Alternatively, you can use "More Options" to share via other apps.
                    """
                    showingSetupHelp = true
                }
            } label: {
                HStack {
                    Label("Share via Email", systemImage: "envelope.fill")
                    if !sharingService.canSendEmail {
                        Spacer()
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Text message option
            Button {
                if sharingService.canSendText {
                    sharingService.shareViaText(recipe: recipe)
                } else {
                    setupHelpTitle = "Messages Not Available"
                    setupHelpMessage = """
                    Text messaging is not available on this device. This could be because:
                    
                    • You're using a simulator (Messages doesn't work in simulator)
                    • Messages is not set up on this device
                    • This device doesn't support cellular messaging
                    
                    To set up Messages:
                    1. Open the Settings app
                    2. Tap "Messages"
                    3. Sign in with your Apple ID for iMessage
                    
                    Alternatively, you can use "More Options" to share via other apps like WhatsApp, Slack, or AirDrop.
                    """
                    showingSetupHelp = true
                }
            } label: {
                HStack {
                    Label("Share via Text", systemImage: "message.fill")
                    if !sharingService.canSendText {
                        Spacer()
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Divider()
            
            // More options (system share sheet)
            Button {
                sharingService.shareViaShareSheet(recipe: recipe)
            } label: {
                Label("More Options...", systemImage: "square.and.arrow.up")
            }
        } label: {
            Label("Share Recipe", systemImage: "square.and.arrow.up")
        }
        #if os(iOS)
        .sheet(isPresented: $sharingService.showingMailComposer) {
            MailComposerView(recipe: recipe, sharingService: sharingService)
        }
        .sheet(isPresented: $sharingService.showingMessageComposer) {
            MessageComposerView(recipe: recipe, sharingService: sharingService)
        }
        .sheet(isPresented: $sharingService.showingShareSheet) {
            ShareSheetView(items: sharingService.shareItems)
        }
        #else
        .sheet(isPresented: $sharingService.showingShareSheet) {
            MacShareView(items: sharingService.shareItems)
        }
        #endif
        .alert(setupHelpTitle, isPresented: $showingSetupHelp) {
            Button("OK") {
                showingSetupHelp = false
            }
            #if os(iOS)
            Button("Open Settings") {
                if let settingsURL = URL(string: PlatformURLOpener.settingsURLString) {
                    PlatformURLOpener.open(settingsURL)
                }
            }
            #endif
        } message: {
            Text(setupHelpMessage)
        }
        .alert("Sharing Error", isPresented: $sharingService.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = sharingService.errorMessage {
                Text(errorMessage)
            }
        }
    }
}

/// An expanded share view with preview of the recipe card
struct RecipeShareView: View {
    let recipe: RecipeX
    @StateObject private var sharingService = RecipeSharingService()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSourceType: RecipeShareCardView.RecipeSourceType = .email
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Preview section
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Recipe Card Preview")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.top)
                        
                        // Source type picker
                        Picker("Share Type", selection: $selectedSourceType) {
                            Label("Email", systemImage: "envelope.fill")
                                .tag(RecipeShareCardView.RecipeSourceType.email)
                            Label("Text", systemImage: "message.fill")
                                .tag(RecipeShareCardView.RecipeSourceType.text)
                            Label("Other", systemImage: "square.and.arrow.up")
                                .tag(RecipeShareCardView.RecipeSourceType.app)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        // Recipe card preview
                        RecipeShareCardView(recipe: recipe, sourceType: selectedSourceType)
                            .frame(width: 350)
                            .frame(maxHeight: 600)
                            .padding()
                    }
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    Divider()
                    
                    // Primary share button based on selected type
                    Button {
                        switch selectedSourceType {
                        case .email:
                            sharingService.shareViaEmail(recipe: recipe)
                        case .text:
                            sharingService.shareViaText(recipe: recipe)
                        case .app:
                            sharingService.shareViaShareSheet(recipe: recipe, sourceType: selectedSourceType)
                        }
                    } label: {
                        Label(shareButtonTitle, systemImage: shareButtonIcon)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selectedSourceType.color)
                    .disabled(!isShareAvailable)
                    
                    // Alternative share options
                    HStack(spacing: 12) {
                        if sharingService.canSendEmail && selectedSourceType != .email {
                            Button {
                                sharingService.shareViaEmail(recipe: recipe)
                            } label: {
                                Label("Email", systemImage: "envelope.fill")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        if sharingService.canSendText && selectedSourceType != .text {
                            Button {
                                sharingService.shareViaText(recipe: recipe)
                            } label: {
                                Label("Text", systemImage: "message.fill")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        if selectedSourceType != .app {
                            Button {
                                sharingService.shareViaShareSheet(recipe: recipe, sourceType: selectedSourceType)
                            } label: {
                                Label("More", systemImage: "ellipsis.circle")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // Unavailability message with help
                    if !isShareAvailable {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.appWarning)
                                Text(unavailabilityMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .multilineTextAlignment(.center)
                            
                            // Help button with instructions
                            Button {
                                sharingService.errorMessage = detailedUnavailabilityHelp
                                sharingService.showingError = true
                            } label: {
                                Label("How to Set Up", systemImage: "info.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding()
                        .adaptiveToneBackground(.warning, baseOpacity: 0.1)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            .navigationTitle("Share Recipe")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            #if os(iOS)
            .sheet(isPresented: $sharingService.showingMailComposer) {
                MailComposerView(recipe: recipe, sharingService: sharingService)
            }
            .sheet(isPresented: $sharingService.showingMessageComposer) {
                MessageComposerView(recipe: recipe, sharingService: sharingService)
            }
            .sheet(isPresented: $sharingService.showingShareSheet) {
                ShareSheetView(items: sharingService.shareItems)
            }
            #else
            .sheet(isPresented: $sharingService.showingShareSheet) {
                MacShareView(items: sharingService.shareItems)
            }
            #endif
            .alert("Sharing Error", isPresented: $sharingService.showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage = sharingService.errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
    
    private var shareButtonTitle: String {
        switch selectedSourceType {
        case .email: return "Share via Email"
        case .text: return "Share via Text"
        case .app: return "Share Recipe"
        }
    }
    
    private var shareButtonIcon: String {
        switch selectedSourceType {
        case .email: return "envelope.fill"
        case .text: return "message.fill"
        case .app: return "square.and.arrow.up"
        }
    }
    
    private var isShareAvailable: Bool {
        switch selectedSourceType {
        case .email: return sharingService.canSendEmail
        case .text: return sharingService.canSendText
        case .app: return true
        }
    }
    
    private var unavailabilityMessage: String {
        switch selectedSourceType {
        case .email: return "Email is not configured on this device."
        case .text: return "Text messaging is not available."
        case .app: return ""
        }
    }
    
    private var detailedUnavailabilityHelp: String {
        switch selectedSourceType {
        case .email:
            return """
            To set up email on your device:
            
            1. Open the Settings app
            2. Scroll down and tap "Mail"
            3. Tap "Accounts"
            4. Tap "Add Account"
            5. Choose your email provider (iCloud, Gmail, etc.)
            6. Sign in with your credentials
            
            Once configured, you'll be able to share recipes via email.
            
            💡 Tip: You can also use "More Options" to share via other apps like Notes, Files, or AirDrop.
            """
        case .text:
            return """
            Text messaging may not be available because:
            
            • You're using a simulator (Messages doesn't work in simulator)
            • Messages is not set up on this device
            • This device doesn't support cellular messaging
            
            To set up Messages:
            1. Open the Settings app
            2. Tap "Messages"
            3. Sign in with your Apple ID for iMessage
            
            💡 Tip: You can use "More Options" to share via WhatsApp, Telegram, Slack, or other messaging apps.
            
            If you're testing in a simulator, try using a real device or use the "More Options" button instead.
            """
        case .app:
            return ""
        }
    }
}

// MARK: - Preview

#Preview("Share Button") {
    let ingredientSections = [
        IngredientSection(
            ingredients: [
                Ingredient(name: "Test ingredient")
            ]
        )
    ]
    let instructionSections = [
        InstructionSection(
            steps: [
                InstructionStep(stepNumber: 1, text: "Test step")
            ]
        )
    ]
    
    let recipe = RecipeX(
        title: "Test Recipe",
        recipeYield: "Serves 4",
        ingredientSectionsData: try? JSONEncoder().encode(ingredientSections),
        instructionSectionsData: try? JSONEncoder().encode(instructionSections)
    )
    
    return NavigationStack {
        List {
            Section {
                RecipeShareButton(recipe: recipe)
            }
        }
        .navigationTitle("Recipe")
    }
}

#Preview("Share View") {
    let ingredientSections = [
        IngredientSection(
            title: "Dry Ingredients",
            ingredients: [
                Ingredient(quantity: "2¼", unit: "cups", name: "all-purpose flour"),
                Ingredient(quantity: "1", unit: "tsp", name: "baking soda"),
                Ingredient(quantity: "1", unit: "tsp", name: "salt")
            ]
        ),
        IngredientSection(
            title: "Wet Ingredients",
            ingredients: [
                Ingredient(quantity: "1", unit: "cup", name: "butter", preparation: "softened"),
                Ingredient(quantity: "¾", unit: "cup", name: "granulated sugar"),
                Ingredient(quantity: "¾", unit: "cup", name: "brown sugar"),
                Ingredient(quantity: "2", unit: "", name: "large eggs"),
                Ingredient(quantity: "2", unit: "tsp", name: "vanilla extract")
            ]
        )
    ]
    
    let instructionSections = [
        InstructionSection(
            steps: [
                InstructionStep(stepNumber: 1, text: "Preheat oven to 375°F (190°C)."),
                InstructionStep(stepNumber: 2, text: "Mix flour, baking soda, and salt in a bowl."),
                InstructionStep(stepNumber: 3, text: "Beat butter and sugars until creamy."),
                InstructionStep(stepNumber: 4, text: "Add eggs and vanilla, beat well."),
                InstructionStep(stepNumber: 5, text: "Gradually blend in flour mixture."),
                InstructionStep(stepNumber: 6, text: "Stir in chocolate chips."),
                InstructionStep(stepNumber: 7, text: "Drop rounded tablespoons onto ungreased cookie sheets."),
                InstructionStep(stepNumber: 8, text: "Bake 9-11 minutes or until golden brown.")
            ]
        )
    ]
    
    let notes = [
        RecipeNote(type: .tip, text: "For chewier cookies, slightly underbake them."),
        RecipeNote(type: .timing, text: "Cookies will continue to cook on the baking sheet after removing from oven.")
    ]
    
    let recipe = RecipeX(
        title: "Classic Chocolate Chip Cookies",
        headerNotes: "Soft, chewy, and absolutely delicious!",
        recipeYield: "Makes 24 cookies",
        reference: "Family recipe from Grandma",
        ingredientSectionsData: try? JSONEncoder().encode(ingredientSections),
        instructionSectionsData: try? JSONEncoder().encode(instructionSections),
        notesData: try? JSONEncoder().encode(notes)
    )
    
    return RecipeShareView(recipe: recipe)
}
