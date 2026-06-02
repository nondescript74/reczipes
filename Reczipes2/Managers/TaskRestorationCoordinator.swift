//
//  TaskRestorationCoordinator.swift
//  Reczipes2
//
//  Created for restoring long-running tasks
//

import SwiftUI
import SwiftData
import Combine

/// Coordinates restoration of long-running tasks when app returns from background
@MainActor
class TaskRestorationCoordinator: ObservableObject {
    static let shared = TaskRestorationCoordinator()
    
    @Published var showRestorationPrompt = false
    @Published var restorationMessage: String = ""
    @Published var pendingTask: TaskState?
    
    private init() {}
    
    /// Check if there's a task to restore when app becomes active
    func checkForTaskRestoration() {
        guard let task = AppStateManager.shared.activeTask else {
            return
        }
        
        // Calculate how long the task has been running
        let elapsed = Date().timeIntervalSince(task.startedAt)
        
        // If task was started recently (within last 2 hours), offer to restore it
        if elapsed < 7200 { // 2 hours
            pendingTask = task
            
            switch task.taskType {
            case .extraction:
                restorationMessage = "You were extracting a recipe. Would you like to continue?"
            case .diabeticAnalysis:
                restorationMessage = "You were analyzing a recipe for diabetic information. Would you like to continue?"
            }
            
            showRestorationPrompt = true
        } else {
            // Task is too old, clear it
            AppStateManager.shared.completeTask()
        }
    }
    
    /// User chose to restore the task
    func restoreTask(modelContainer: ModelContainer) async {
        guard let task = pendingTask else { return }
        
        switch task.taskType {
        case .extraction:
            await restoreExtractionTask(task)
            
        case .diabeticAnalysis:
            await restoreDiabeticAnalysisTask(task, modelContainer: modelContainer)
        }
        
        pendingTask = nil
        showRestorationPrompt = false
    }
    
    /// User chose to cancel the task
    func cancelRestoration() {
        AppStateManager.shared.completeTask()
        pendingTask = nil
        showRestorationPrompt = false
    }
    
    // MARK: - Private Task Restoration
    
    private func restoreExtractionTask(_ task: TaskState) async {
        AppLog.info("Restoring extraction task", category: .state)
        
        // The extraction view will pick up the task state from AppStateManager
        // and show appropriate UI (e.g., "Resuming extraction...")
        
        // Navigate to extract tab
        AppStateManager.shared.currentTab = .extract
    }
    
    private func restoreDiabeticAnalysisTask(_ task: TaskState, modelContainer: ModelContainer) async {
        AppLog.info("Restoring diabetic analysis task for recipe: \(task.recipeId?.uuidString ?? "unknown")", category: .state)
        
        // Navigate to recipes tab and select the recipe being analyzed
        AppStateManager.shared.currentTab = .recipes
        
        if let recipeId = task.recipeId {
            AppStateManager.shared.selectedRecipeId = recipeId
        }
        
        // The recipe detail view will check for active analysis task and show progress UI
    }
}

// MARK: - Task Restoration View

/// View that shows a prompt to restore an interrupted task
struct TaskRestorationPromptView: View {
    @ObservedObject var coordinator: TaskRestorationCoordinator
    let modelContainer: ModelContainer
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("Resume Task?")
                .font(.title2)
                .bold()
            
            Text(coordinator.restorationMessage)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    coordinator.cancelRestoration()
                }
                .buttonStyle(.bordered)
                
                Button("Resume") {
                    Task {
                        await coordinator.restoreTask(modelContainer: modelContainer)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        .shadow(radius: 20)
    }
}
