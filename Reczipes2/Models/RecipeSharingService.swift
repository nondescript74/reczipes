//
//  RecipeSharingService.swift
//  Reczipes2
//
//  Created for recipe sharing functionality
//

import SwiftUI
#if os(iOS)
import MessageUI
#endif
#if os(iOS)
import UIKit
#endif
import Combine

/// Service for sharing recipes via email, text, and other methods
@MainActor
class RecipeSharingService: ObservableObject {
    @Published var showingMailComposer = false
    @Published var showingMessageComposer = false
    @Published var showingShareSheet = false
    @Published var shareItems: [Any] = []
    @Published var errorMessage: String?
    @Published var showingError = false
    
    // MARK: - Check Availability
    
    /// Check if email is available on this device
    var canSendEmail: Bool {
        #if os(iOS)
        return MFMailComposeViewController.canSendMail()
        #else
        // macOS routes email through the system share sheet (NSSharingServicePicker).
        return true
        #endif
    }

    /// Check if text messages are available on this device
    var canSendText: Bool {
        #if os(iOS)
        return MFMessageComposeViewController.canSendText()
        #else
        // macOS routes messages through the system share sheet (NSSharingServicePicker).
        return true
        #endif
    }
    
    // MARK: - Generate Recipe Content
    
    /// Generate a formatted text version of the recipe
    func generateRecipeText(from recipe: RecipeX) -> String {
        var text = ""
        
        // Title
        text += "🍽️ \(String(describing: recipe.title))\n"
        text += String(repeating: "=", count: (recipe.title?.count ?? 0) + 3) + "\n\n"
        
        // Header notes
        if let headerNotes = recipe.headerNotes {
            text += "\(headerNotes)\n\n"
        }
        
        // Yield
        if let yield = recipe.yield {
            text += "📊 \(yield)\n\n"
        }
        
        // Ingredients
        text += "📝 INGREDIENTS\n"
        text += String(repeating: "-", count: 20) + "\n"
        for section in recipe.ingredientSections {
            if let title = section.title {
                text += "\n\(title):\n"
            }
            for ingredient in section.ingredients {
                var line = "• "
                if let quantity = ingredient.quantity, !quantity.isEmpty {
                    line += "\(quantity) "
                }
                if let unit = ingredient.unit, !unit.isEmpty {
                    line += "\(unit) "
                }
                line += ingredient.name
                if let prep = ingredient.preparation {
                    line += ", \(prep)"
                }
                text += "\(line)\n"
            }
            if let transitionNote = section.transitionNote {
                text += "\n⚠️ \(transitionNote)\n"
            }
        }
        
        // Instructions
        text += "\n👨‍🍳 INSTRUCTIONS\n"
        text += String(repeating: "-", count: 20) + "\n"
        for section in recipe.instructionSections {
            if let title = section.title {
                text += "\n\(title):\n"
            }
            for step in section.steps {
                if step.stepNumber > 0 {
                    text += "\n\(step.stepNumber). \(step.text)\n"
                } else {
                    text += "\n• \(step.text)\n"
                }
            }
        }
        
        // Notes
        if !recipe.notes.isEmpty {
            text += "\n💡 NOTES\n"
            text += String(repeating: "-", count: 20) + "\n"
            for note in recipe.notes {
                let icon = iconForNoteType(note.type)
                text += "\n\(icon) \(note.type.rawValue.capitalized): \(note.text)\n"
            }
        }
        
        // Reference
        if let reference = recipe.reference {
            text += "\n📚 Reference: \(reference)\n"
        }
        
        text += "\n" + String(repeating: "=", count: 40) + "\n"
        text += "Shared from Reczipes - Your Personal Recipe Collection\n"
        
        return text
    }
    
    /// Generate HTML version of the recipe for email
    func generateRecipeHTML(from recipe: RecipeX, sourceType: RecipeShareCardView.RecipeSourceType) -> String {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    max-width: 600px;
                    margin: 0 auto;
                    padding: 20px;
                    background-color: #f5f5f5;
                }
                .card {
                    background: white;
                    border-radius: 16px;
                    overflow: hidden;
                    box-shadow: 0 4px 20px rgba(0,0,0,0.1);
                }
                .header {
                    background: linear-gradient(135deg, \(sourceType == .email ? "#007AFF" : "#34C759"), \(sourceType == .email ? "#0051D5" : "#248A3D"));
                    color: white;
                    padding: 30px 20px;
                    text-align: center;
                }
                .badge {
                    display: inline-block;
                    background: rgba(255,255,255,0.2);
                    padding: 6px 12px;
                    border-radius: 20px;
                    font-size: 12px;
                    margin-bottom: 10px;
                }
                .title {
                    font-size: 28px;
                    font-weight: bold;
                    margin: 10px 0;
                }
                .subtitle {
                    font-size: 14px;
                    opacity: 0.9;
                }
                .content {
                    padding: 20px;
                }
                .section {
                    margin-bottom: 30px;
                }
                .section-title {
                    font-size: 20px;
                    font-weight: bold;
                    margin-bottom: 15px;
                    color: #007AFF;
                    display: flex;
                    align-items: center;
                }
                .ingredient-section-title {
                    font-size: 16px;
                    font-weight: 600;
                    color: #007AFF;
                    margin: 15px 0 10px 0;
                }
                .ingredient {
                    padding: 8px 0;
                    border-bottom: 1px solid #f0f0f0;
                }
                .ingredient:last-child {
                    border-bottom: none;
                }
                .step {
                    display: flex;
                    margin-bottom: 15px;
                }
                .step-number {
                    background: #34C759;
                    color: white;
                    width: 30px;
                    height: 30px;
                    border-radius: 50%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    font-weight: bold;
                    flex-shrink: 0;
                    margin-right: 12px;
                }
                .note {
                    background: #FFF9E6;
                    border-left: 4px solid #FFB800;
                    padding: 12px;
                    margin-bottom: 10px;
                    border-radius: 4px;
                }
                .note-title {
                    font-weight: 600;
                    color: #B8860B;
                    margin-bottom: 5px;
                }
                .footer {
                    background: #f8f8f8;
                    padding: 20px;
                    text-align: center;
                    color: #666;
                    font-size: 14px;
                }
                .stats {
                    display: flex;
                    justify-content: space-around;
                    padding: 20px;
                    background: #f8f8f8;
                    margin-bottom: 20px;
                }
                .stat {
                    text-align: center;
                }
                .stat-value {
                    font-size: 24px;
                    font-weight: bold;
                    color: #007AFF;
                }
                .stat-label {
                    font-size: 12px;
                    color: #666;
                    text-transform: uppercase;
                }
                .yield-badge {
                    background: #E3F2FD;
                    color: #1976D2;
                    padding: 8px 16px;
                    border-radius: 20px;
                    display: inline-block;
                    margin-bottom: 20px;
                    font-size: 14px;
                }
            </style>
        </head>
        <body>
            <div class="card">
                <div class="header">
                    <div class="badge">\(sourceType == .email ? "📧" : "💬") Shared via \(sourceType == .email ? "Email" : "Text")</div>
                    <div class="title">\(String(describing: recipe.title))</div>
        """
        
        if let headerNotes = recipe.headerNotes {
            html += """
                    <div class="subtitle">\(headerNotes)</div>
            """
        }
        
        html += """
                </div>
        """
        
        // Stats section
        let ingredientCount = recipe.ingredientSections.reduce(0) { $0 + $1.ingredients.count }
        let stepCount = recipe.instructionSections.reduce(0) { $0 + $1.steps.count }
        
        html += """
                <div class="stats">
                    <div class="stat">
                        <div class="stat-value">\(ingredientCount)</div>
                        <div class="stat-label">Ingredients</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value">\(stepCount)</div>
                        <div class="stat-label">Steps</div>
                    </div>
        """
        
        if !recipe.notes.isEmpty {
            html += """
                    <div class="stat">
                        <div class="stat-value">\(recipe.notes.count)</div>
                        <div class="stat-label">Notes</div>
                    </div>
            """
        }
        
        html += """
                </div>
                <div class="content">
        """
        
        // Yield
        if let yield = recipe.yield {
            html += """
                    <div class="yield-badge">📊 \(yield)</div>
            """
        }
        
        // Ingredients
        html += """
                    <div class="section">
                        <div class="section-title">📝 Ingredients</div>
        """
        
        for section in recipe.ingredientSections {
            if let title = section.title {
                html += """
                        <div class="ingredient-section-title">\(title)</div>
                """
            }
            
            for ingredient in section.ingredients {
                var ingredientText = ""
                if let quantity = ingredient.quantity, !quantity.isEmpty {
                    ingredientText += "<strong>\(quantity)</strong> "
                }
                if let unit = ingredient.unit, !unit.isEmpty {
                    ingredientText += "\(unit) "
                }
                ingredientText += ingredient.name
                if let prep = ingredient.preparation {
                    ingredientText += " <em style='color: #666;'>(\(prep))</em>"
                }
                
                html += """
                        <div class="ingredient">\(ingredientText)</div>
                """
            }
            
            if let transitionNote = section.transitionNote {
                html += """
                        <div class="note">
                            <div class="note-title">⚠️ Note</div>
                            <div>\(transitionNote)</div>
                        </div>
                """
            }
        }
        
        html += """
                    </div>
        """
        
        // Instructions
        html += """
                    <div class="section">
                        <div class="section-title">👨‍🍳 Instructions</div>
        """
        
        for section in recipe.instructionSections {
            if let title = section.title {
                html += """
                        <div class="ingredient-section-title">\(title)</div>
                """
            }
            
            for step in section.steps {
                if step.stepNumber > 0 {
                    html += """
                        <div class="step">
                            <div class="step-number">\(step.stepNumber)</div>
                            <div>\(step.text)</div>
                        </div>
                    """
                } else {
                    html += """
                        <div class="step">
                            <div>• \(step.text)</div>
                        </div>
                    """
                }
            }
        }
        
        html += """
                    </div>
        """
        
        // Notes
        if !recipe.notes.isEmpty {
            html += """
                    <div class="section">
                        <div class="section-title">💡 Notes</div>
            """
            
            for note in recipe.notes {
                let icon = iconForNoteType(note.type)
                html += """
                        <div class="note">
                            <div class="note-title">\(icon) \(note.type.rawValue.capitalized)</div>
                            <div>\(note.text)</div>
                        </div>
                """
            }
            
            html += """
                    </div>
            """
        }
        
        // Reference
        if let reference = recipe.reference {
            html += """
                    <div style="color: #666; font-size: 14px; font-style: italic; margin-top: 20px;">
                        📚 Reference: \(reference)
                    </div>
            """
        }
        
        html += """
                </div>
                <div class="footer">
                    <div style="font-size: 16px; margin-bottom: 5px;">🍽️ <strong>Reczipes</strong></div>
                    <div>Your Personal Recipe Collection</div>
                </div>
            </div>
        </body>
        </html>
        """
        
        return html
    }
    
    /// Generate a shareable image of the recipe card
    @MainActor
    func generateRecipeCardImage(from recipe: RecipeX, sourceType: RecipeShareCardView.RecipeSourceType) -> PlatformImage? {
        #if os(iOS)
        let cardView = RecipeShareCardView(recipe: recipe, sourceType: sourceType)
        let hostingController = UIHostingController(rootView: cardView)
        
        // Set a specific size for iPhone
        let targetSize = CGSize(width: 390, height: 844) // iPhone 14 Pro size
        hostingController.view.bounds = CGRect(origin: .zero, size: targetSize)
        hostingController.view.backgroundColor = .clear
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            hostingController.view.drawHierarchy(in: hostingController.view.bounds, afterScreenUpdates: true)
        }
        #else
        return nil
        #endif
    }
    
    // MARK: - Share Actions
    
    /// Prepare to share recipe via email
    func shareViaEmail(recipe: RecipeX) {
        #if os(iOS)
        guard canSendEmail else {
            errorMessage = "Email is not configured on this device. Please set up Mail in Settings."
            showingError = true
            return
        }
        showingMailComposer = true
        #else
        // macOS: route through the system share sheet, which offers Mail among others.
        shareViaShareSheet(recipe: recipe)
        #endif
    }

    /// Prepare to share recipe via text message
    func shareViaText(recipe: RecipeX) {
        #if os(iOS)
        guard canSendText else {
            errorMessage = "Text messaging is not available on this device."
            showingError = true
            return
        }
        showingMessageComposer = true
        #else
        // macOS: route through the system share sheet, which offers Messages among others.
        shareViaShareSheet(recipe: recipe)
        #endif
    }
    
    /// Prepare to share recipe using the system share sheet
    func shareViaShareSheet(recipe: RecipeX, sourceType: RecipeShareCardView.RecipeSourceType = .app) {
        let recipeText = generateRecipeText(from: recipe)
        
        var items: [Any] = [recipeText]
        
        // Optionally add image if available
        if let cardImage = generateRecipeCardImage(from: recipe, sourceType: sourceType) {
            items.insert(cardImage, at: 0)
        }
        
        shareItems = items
        showingShareSheet = true
    }
    
    // MARK: - Helper Methods
    
    private func iconForNoteType(_ type: RecipeNoteType) -> String {
        switch type {
        case .tip: return "💡"
        case .substitution: return "🔄"
        case .warning: return "⚠️"
        case .timing: return "⏰"
        case .general: return "ℹ️"
        }
    }
}

// MARK: - Mail Composer View

#if os(iOS)
struct MailComposerView: UIViewControllerRepresentable {
    let recipe: RecipeX
    let sharingService: RecipeSharingService
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setSubject("Recipe: \(String(describing: recipe.title))")
        
        // Generate HTML body
        let htmlBody = sharingService.generateRecipeHTML(from: recipe, sourceType: .email)
        composer.setMessageBody(htmlBody, isHTML: true)
        
        // Attach recipe card image if possible
        if let cardImage = sharingService.generateRecipeCardImage(from: recipe, sourceType: .email),
           let imageData = cardImage.pngData() {
            composer.addAttachmentData(imageData, mimeType: "image/png", fileName: "\(String(describing: recipe.title?.replacingOccurrences(of: " ", with: "_")))_recipe.png")
        }
        
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposerView
        
        init(_ parent: MailComposerView) {
            self.parent = parent
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            if let error = error {
                parent.sharingService.errorMessage = "Failed to send email: \(error.localizedDescription)"
                parent.sharingService.showingError = true
            }
            parent.dismiss()
        }
    }
}

// MARK: - Message Composer View

struct MessageComposerView: UIViewControllerRepresentable {
    let recipe: RecipeX
    let sharingService: RecipeSharingService
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = context.coordinator
        
        // Set text body
        let textBody = sharingService.generateRecipeText(from: recipe)
        composer.body = textBody
        
        // Try to attach recipe card image
        if let cardImage = sharingService.generateRecipeCardImage(from: recipe, sourceType: .text),
           let imageData = cardImage.pngData() {
            composer.addAttachmentData(imageData, typeIdentifier: "public.png", filename: "\(String(describing: recipe.title?.replacingOccurrences(of: " ", with: "_")))_recipe.png")
        }
        
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: MessageComposerView
        
        init(_ parent: MessageComposerView) {
            self.parent = parent
        }
        
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            parent.dismiss()
        }
    }
}

// MARK: - Share Sheet View

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            dismiss()
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
