//
//  RemindersService.swift
//  Reczipes2
//
//  Created for exporting recipe ingredients to Reminders app
//

import Foundation
import EventKit

@MainActor
class RemindersService {
    private let eventStore = EKEventStore()
    
    /// Check if the app has permission to access reminders
    var hasPermission: Bool {
        if #available(iOS 17.0, *) {
            let status = EKEventStore.authorizationStatus(for: .reminder)
            return status == .fullAccess || status == .writeOnly
        } else {
            return EKEventStore.authorizationStatus(for: .reminder) == .authorized
        }
    }
    
    /// Request permission to access reminders
    /// - Returns: true if permission was granted, false otherwise
    func requestPermission() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                // Request full access for iOS 17+
                let granted = try await eventStore.requestFullAccessToReminders()
                AppLog.info("📝 Reminders permission: \(granted ? "Granted" : "Denied")", category: .general)
                return granted
            } else {
                // Fall back to the old API for earlier iOS versions
                let granted = try await eventStore.requestAccess(to: .reminder)
                AppLog.info("📝 Reminders permission: \(granted ? "Granted" : "Denied")", category: .general)
                return granted
            }
        } catch {
            AppLog.error("❌ Error requesting reminders permission: \(error)", category: .general)
            return false
        }
    }
    
    /// Add recipe ingredients to a new reminder list
    /// - Parameters:
    ///   - recipe: The RecipeX containing ingredients to export
    /// - Returns: true if successful, false otherwise
    func addIngredientsToReminders(recipe: RecipeX) async throws {
        // Ensure we have permission
        if !hasPermission {
            let granted = await requestPermission()
            guard granted else {
                throw RemindersError.permissionDenied
            }
        }
        
        AppLog.info("📝 ========== ADDING INGREDIENTS TO REMINDERS ==========", category: .general)
        AppLog.info("📝 Recipe: \(recipe.safeTitle)", category: .general)
        
        // Find or create a list for recipe ingredients
        let listTitle = "🍳 \(recipe.safeTitle)"
        let calendar = try findOrCreateReminderList(named: listTitle)
        
        AppLog.info("📝 Using reminder list: \(calendar.title)", category: .general)
        
        var addedCount = 0
        
        // Decode ingredient sections from RecipeX
        guard let sectionsData = recipe.ingredientSectionsData,
              let sections = try? JSONDecoder().decode([IngredientSection].self, from: sectionsData) else {
            AppLog.error("Failed to decode ingredient sections", category: .general)
            throw RemindersError.saveFailed
        }
        
        // Iterate through all ingredient sections
        for section in sections {
            // Add section title as a reminder if present
            if let sectionTitle = section.title {
                let sectionReminder = EKReminder(eventStore: eventStore)
                sectionReminder.title = "▪️ \(sectionTitle)"
                sectionReminder.calendar = calendar
                sectionReminder.isCompleted = false
                
                try eventStore.save(sectionReminder, commit: false)
                addedCount += 1
            }
            
            // Add each ingredient
            for ingredient in section.ingredients {
                let reminder = EKReminder(eventStore: eventStore)
                
                // Format ingredient text nicely
                var ingredientText = ""
                
                if let quantity = ingredient.quantity, !quantity.isEmpty {
                    ingredientText += quantity
                }
                
                if let unit = ingredient.unit, !unit.isEmpty {
                    ingredientText += ingredientText.isEmpty ? unit : " \(unit)"
                }
                
                ingredientText += ingredientText.isEmpty ? ingredient.name : " \(ingredient.name)"
                
                if let preparation = ingredient.preparation, !preparation.isEmpty {
                    ingredientText += ", \(preparation)"
                }
                
                // Add metric conversion if available
                if let metricQuantity = ingredient.metricQuantity,
                   let metricUnit = ingredient.metricUnit {
                    ingredientText += " (\(metricQuantity) \(metricUnit))"
                }
                
                reminder.title = ingredientText
                reminder.calendar = calendar
                reminder.isCompleted = false
                
                try eventStore.save(reminder, commit: false)
                addedCount += 1
            }
        }
        
        // Commit all changes at once for better performance
        try eventStore.commit()
        
        AppLog.info("📝 ✅ Successfully added \(addedCount) reminders", category: .general)
        AppLog.info("📝 ========== REMINDERS EXPORT COMPLETE ==========", category: .general)
    }
    
    /// Find an existing reminder list or create a new one
    /// - Parameter name: The name of the reminder list
    /// - Returns: The EKCalendar representing the reminder list
    private func findOrCreateReminderList(named name: String) throws -> EKCalendar {
        // Get all reminder calendars (lists)
        let calendars = eventStore.calendars(for: .reminder)
        
        // Look for existing list with this name
        if let existingCalendar = calendars.first(where: { $0.title == name }) {
            AppLog.info("📝 Found existing reminder list: \(name)", category: .general)
            return existingCalendar
        }
        
        // Create a new list
        AppLog.info("📝 Creating new reminder list: \(name)", category: .general)
        let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
        newCalendar.title = name
        
        // Set the source - use the default source for reminders
        if let source = eventStore.defaultCalendarForNewReminders()?.source {
            newCalendar.source = source
        } else {
            // Fallback: use first available source
            guard let source = eventStore.sources.first(where: { $0.sourceType == .local || $0.sourceType == .calDAV }) else {
                throw RemindersError.noSourceAvailable
            }
            newCalendar.source = source
        }
        
        try eventStore.saveCalendar(newCalendar, commit: true)
        
        return newCalendar
    }
}

// MARK: - Error Types

enum RemindersError: LocalizedError {
    case permissionDenied
    case noSourceAvailable
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permission to access Reminders was denied. Please enable it in Settings > Privacy & Security > Reminders."
        case .noSourceAvailable:
            return "No reminder source is available. Please check your device's reminder settings."
        case .saveFailed:
            return "Failed to save reminders. Please try again."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Go to Settings > Privacy & Security > Reminders and enable access for this app."
        case .noSourceAvailable:
            return "Make sure you have at least one reminder account configured in Settings > Reminders."
        case .saveFailed:
            return "Check your network connection and try again."
        }
    }
}
