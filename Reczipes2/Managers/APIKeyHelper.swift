//
//  APIKeyHelper.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/29/26.
//

import Foundation

// MARK: - API Key Helper

class APIKeyHelper {
    private static let recipeAPIKeychainKey = "recipeAPIKey"
    
    /// The storage method being used (configure this for your app)
    static var storageMethod: APIKeyStorage = .keychain(key: "claudeAPIKey")
    
    /// Get the API key from configured storage
    static func getAPIKey() -> String? {
        let key = storageMethod.retrieve()
        
        if RecipeExtractorConfig.debugLogging {
            if key != nil {
                print("✅ API Key retrieved successfully")
            } else {
                print("❌ API Key not found")
            }
        }
        
        return key
    }
    
    /// Set the API key (useful for first-time setup)
    static func setAPIKey(_ key: String) -> Bool {
        switch storageMethod {
        case .keychain(let keychainKey):
            return KeychainManager.shared.save(key: keychainKey, value: key)
            
        case .userDefaults(let defaultsKey):
            UserDefaults.standard.set(key, forKey: defaultsKey)
            return true
            
        default:
            print("⚠️ Cannot programmatically set API key for current storage method")
            return false
        }
    }
    
    /// Check if API key is configured
    static var isConfigured: Bool {
        guard let key = getAPIKey(), !key.isEmpty else {
            return false
        }
        return true
    }

    /// Get the recipe-api.com key from Keychain
    static func getRecipeAPIKey() -> String? {
        KeychainManager.shared.get(key: recipeAPIKeychainKey)
    }

    /// Save the recipe-api.com key in Keychain
    static func setRecipeAPIKey(_ key: String) -> Bool {
        KeychainManager.shared.save(key: recipeAPIKeychainKey, value: key)
    }

    /// Remove the recipe-api.com key from Keychain
    static func removeRecipeAPIKey() -> Bool {
        KeychainManager.shared.delete(key: recipeAPIKeychainKey)
    }

    /// Check if recipe-api.com key is configured
    static var isRecipeAPIConfigured: Bool {
        guard let key = getRecipeAPIKey(), !key.isEmpty else {
            return false
        }
        return true
    }
}
