//
//  AppStateManager.swift
//  Reczipes2
//
//  Created for state preservation and restoration
//

import SwiftUI
import Combine

/// Tracks the current active tab in the app
enum AppTab: String, Codable, CaseIterable {
    case recipes
    case books
    case extract
    case settings
    case cooking
    case meals
}

/// Tracks the state of long-running operations
struct TaskState: Codable {
    let taskType: TaskType
    let recipeId: UUID?
    let progress: Double
    let startedAt: Date
    let inputData: Data? // Serialized input for resuming
    
    enum TaskType: String, Codable {
        case extraction
        case diabeticAnalysis
    }
}

/// Main app state manager using AppStorage for persistence
@MainActor
class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    // MARK: - Published Properties
    
    @Published var currentTab: AppTab {
        didSet {
            saveCurrentTab(currentTab)
        }
    }
    
    @Published var selectedRecipeId: UUID? {
        didSet {
            saveSelectedRecipeId(selectedRecipeId)
        }
    }
    
    @Published var isFirstLaunch: Bool {
        didSet {
            UserDefaults.standard.set(isFirstLaunch, forKey: "isFirstLaunch")
        }
    }
    
    @Published var activeTask: TaskState? {
        didSet {
            saveActiveTask(activeTask)
        }
    }

    /// URL queued for extraction from another part of the app (e.g.,
    /// the smart course-search sheet). The Extract tab consumes and
    /// clears this when it appears, pre-filling its URL field.
    /// Transient — not persisted across launches.
    @Published var pendingExtractURL: String?

    // MARK: - Scene Phase Tracking
    
    @Published var lastActiveDate: Date?
    
    // MARK: - Initialization
    
    private init() {
        // Load persisted state
        self.currentTab = Self.loadCurrentTab()
        self.selectedRecipeId = Self.loadSelectedRecipeId()
        self.isFirstLaunch = UserDefaults.standard.object(forKey: "isFirstLaunch") as? Bool ?? true
        self.activeTask = Self.loadActiveTask()
        self.lastActiveDate = Self.loadLastActiveDate()
    }
    
    // MARK: - State Persistence
    
    private func saveCurrentTab(_ tab: AppTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: "currentTab")
    }
    
    private static func loadCurrentTab() -> AppTab {
        guard let rawValue = UserDefaults.standard.string(forKey: "currentTab"),
              let tab = AppTab(rawValue: rawValue) else {
            return .recipes // Default tab
        }
        return tab
    }
    
    private func saveSelectedRecipeId(_ id: UUID?) {
        if let id = id {
            UserDefaults.standard.set(id.uuidString, forKey: "selectedRecipeId")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedRecipeId")
        }
    }
    
    private static func loadSelectedRecipeId() -> UUID? {
        guard let uuidString = UserDefaults.standard.string(forKey: "selectedRecipeId") else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }
    
    private func saveActiveTask(_ task: TaskState?) {
        if let task = task {
            if let encoded = try? JSONEncoder().encode(task) {
                UserDefaults.standard.set(encoded, forKey: "activeTask")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: "activeTask")
        }
    }
    
    private static func loadActiveTask() -> TaskState? {
        guard let data = UserDefaults.standard.data(forKey: "activeTask") else {
            return nil
        }
        return try? JSONDecoder().decode(TaskState.self, from: data)
    }
    
    private static func loadLastActiveDate() -> Date? {
        UserDefaults.standard.object(forKey: "lastActiveDate") as? Date
    }
    
    // MARK: - Scene Phase Management
    
    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            logInfo("App became active", category: "state")
            
        case .inactive:
            logInfo("App became inactive", category: "state")
            
        case .background:
            logInfo("App entered background - saving state", category: "state")
            saveStateToBackground()
            
        @unknown default:
            break
        }
    }
    
    private func saveStateToBackground() {
        // Save timestamp when entering background
        UserDefaults.standard.set(Date(), forKey: "lastActiveDate")
        lastActiveDate = Date()
    }
    
    // MARK: - Task Management
    
    func startTask(type: TaskState.TaskType, recipeId: UUID? = nil, inputData: Data? = nil) {
        activeTask = TaskState(
            taskType: type,
            recipeId: recipeId,
            progress: 0.0,
            startedAt: Date(),
            inputData: inputData
        )
    }
    
    func updateTaskProgress(_ progress: Double) {
        guard let task = activeTask else { return }
        
        // Create a new TaskState with updated progress (since it's a struct)
        activeTask = TaskState(
            taskType: task.taskType,
            recipeId: task.recipeId,
            progress: progress,
            startedAt: task.startedAt,
            inputData: task.inputData
        )
    }
    
    func completeTask() {
        activeTask = nil
    }
    
    // MARK: - Reset State
    
    func resetToDefaults() {
        currentTab = .recipes
        selectedRecipeId = nil
        activeTask = nil
        // Don't reset isFirstLaunch here - it's controlled elsewhere
    }
    
    // MARK: - Should Show Launch Screen
    
    func shouldShowLaunchScreen() -> Bool {
        // Show launch screen every time the app launches
        // This allows users to see version updates and what's new
        return true
    }
}

// MARK: - Extraction Input Data

/// Serializable input data for recipe extraction
struct ExtractionInputData: Codable {
    let imageData: Data?
    let textInput: String?
    let timestamp: Date
}
