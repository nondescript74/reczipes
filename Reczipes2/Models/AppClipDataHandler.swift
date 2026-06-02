//
//  AppClipDataHandler.swift
//  Reczipes2
//
//  Handles data passed from App Clip to main app
//  Created by Zahirudeen Premji on 12/30/25.
//

import SwiftUI
import SwiftData

/// Handles data transfer from App Clip to main app via App Groups
struct AppClipDataHandler {
    private static let sharedDefaults = UserDefaults(suiteName: "group.com.headydiscy.reczipes")
    private static let pendingRecipeKey = "appClipPendingRecipe"
    
    /// Check if there's a pending recipe from App Clip and import it
    @MainActor
    static func checkForPendingRecipe(modelContext: ModelContext) -> Bool {
        guard let data = sharedDefaults?.data(forKey: pendingRecipeKey) else {
            return false
        }
        
        do {
            let decoder = JSONDecoder()
            let extractedRecipe = try decoder.decode(AppClipExtractedRecipeData.self, from: data)
            
            // Convert simple App Clip data to RecipeModel structure
            let recipe = convertAppClipDataToRecipeX(extractedRecipe)
            
            // Save to SwiftData
            modelContext.insert(recipe)
            try modelContext.save()
            
            // Clear the pending recipe
            sharedDefaults?.removeObject(forKey: pendingRecipeKey)
            
            AppLog.info("✅ Successfully imported recipe from App Clip: \(String(describing: recipe.title))", category: .lifecycle)
            return true
            
        } catch {
            AppLog.error("Failed to import App Clip recipe: \(error)", category: .lifecycle)
            return false
        }
    }
    
    /// Convert App Clip's simple data structure to RecipeX
    private static func convertAppClipDataToRecipeX(_ clipData: AppClipExtractedRecipeData) -> RecipeX {
        let encoder = JSONEncoder()
        
        // Convert ingredients array to IngredientSection
        let ingredientSection = IngredientSection(
            title: nil,
            ingredients: clipData.ingredients.map { ingredientText in
                Ingredient(name: ingredientText)
            }
        )
        
        // Convert instructions array to InstructionSection
        let instructionSection = InstructionSection(
            title: nil,
            steps: clipData.instructions.enumerated().map { index, text in
                InstructionStep(stepNumber: index + 1, text: text)
            }
        )
        
        // Build yield string
        let yieldString = "Serves \(clipData.servings)"
        
        // Build header notes with timing info
        var headerNotesText: String? = nil
        if let prepTime = clipData.prepTime, let cookTime = clipData.cookTime {
            headerNotesText = "Prep Time: \(prepTime)\nCook Time: \(cookTime)"
        } else if let prepTime = clipData.prepTime {
            headerNotesText = "Prep Time: \(prepTime)"
        } else if let cookTime = clipData.cookTime {
            headerNotesText = "Cook Time: \(cookTime)"
        }
        
        // Create notes array
        var notes: [RecipeNote] = []
        if let clipNotes = clipData.notes, !clipNotes.isEmpty {
            notes.append(RecipeNote(type: .general, text: clipNotes))
        }
        notes.append(RecipeNote(type: .general, text: "Imported from App Clip"))
        
        // Encode sections to Data
        let ingredientSectionsData = try? encoder.encode([ingredientSection])
        let instructionSectionsData = try? encoder.encode([instructionSection])
        let notesData = try? encoder.encode(notes)
        
        return RecipeX(
            title: clipData.title,
            headerNotes: headerNotesText,
            recipeYield: yieldString,
            ingredientSectionsData: ingredientSectionsData,
            instructionSectionsData: instructionSectionsData,
            notesData: notesData
        )
    }
    
    // MARK: - API Key Sharing (Keychain-based)

    /// The App Group identifier used for the shared Keychain.
    /// Must match the value in AppClipAPIKeyHelper.
    private static let appGroupID        = "group.com.headydiscy.reczipes"

    /// The Keychain account label the App Clip reads from.
    /// Must match the value in AppClipAPIKeyHelper.
    private static let sharedKeychainKey = "claudeAPIKey"

    /// Write the API key into the shared App-Group Keychain so the App Clip
    /// can retrieve it securely — no plaintext in UserDefaults.
    static func shareAPIKeyWithAppClip(_ apiKey: String) {
        guard let data = apiKey.data(using: .utf8) else {
            AppLog.warning("Could not encode API key for Keychain", category: .lifecycle)
            return
        }

        let attributes: [String: Any] = [
            kSecClass            as String: kSecClassGenericPassword,
            kSecAttrAccount      as String: sharedKeychainKey,
            kSecAttrAccessGroup  as String: appGroupID,
            kSecValueData        as String: data,
            kSecAttrAccessible   as String: kSecAttrAccessibleWhenUnlocked
        ]

        // Delete any existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass           as String: kSecClassGenericPassword,
            kSecAttrAccount     as String: sharedKeychainKey,
            kSecAttrAccessGroup as String: appGroupID
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess {
            AppLog.info("Shared API key with App Clip via App-Group Keychain", category: .lifecycle)
        } else {
            AppLog.warning("Failed to share API key with App Clip (Keychain status: \(status))", category: .lifecycle)
        }
    }

    /// Returns `true` when the shared App-Group Keychain already contains an
    /// API key (written by either the main app or the App Clip).
    static func isAPIKeyShared() -> Bool {
        let query: [String: Any] = [
            kSecClass           as String: kSecClassGenericPassword,
            kSecAttrAccount     as String: sharedKeychainKey,
            kSecAttrAccessGroup as String: appGroupID,
            kSecReturnData      as String: false,   // existence check only
            kSecMatchLimit      as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}

// NOTE: AppClipExtractedRecipeData is defined in AppClipSharedModels.swift
// and is included in both the main app and App Clip targets.

// MARK: - App Clip Banner View

/// Shows when a recipe from App Clip is successfully imported
struct AppClipImportBanner: View {
    let recipeName: String
    @Binding var isPresented: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Recipe Imported")
                    .font(.headline)
                
                Text(recipeName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button {
                withAnimation {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
        .shadow(radius: 5)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
