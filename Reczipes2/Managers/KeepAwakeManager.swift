//
//  KeepAwakeManager.swift
//  reczipes2-imageextract
//
//  Manages device screen idle timer to prevent sleep during long operations
//  Used by cooking mode and batch extraction operations
//

import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Manager for controlling device sleep during long operations
/// Shared singleton ensures consistent state across cooking mode and extraction operations
@MainActor
@Observable
final class KeepAwakeManager {
    /// Shared singleton instance
    static let shared = KeepAwakeManager()
    
    /// Current keep awake state - observable for UI binding
    var isKeepAwakeEnabled = false
    
    private init() {}
    
    /// Enable keep awake - prevents device from sleeping
    func enable() {
        guard !isKeepAwakeEnabled else { return }

        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
        isKeepAwakeEnabled = true
        AppLog.info("Keep awake enabled - device will not sleep", category: .ui)
    }

    /// Disable keep awake - allows normal sleep behavior
    func disable() {
        guard isKeepAwakeEnabled else { return }

        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        isKeepAwakeEnabled = false
        AppLog.info("Keep awake disabled - normal sleep behavior restored", category: .ui)
    }
    
    /// Toggle keep awake state
    func toggle() {
        if isKeepAwakeEnabled {
            disable()
        } else {
            enable()
        }
    }
}
