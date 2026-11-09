//
//  ContentFilterMode.swift
//  Reczipes2
//
//  Created on 1/17/26.
//

import Foundation

/// Enum representing the two content filter modes for recipes and books (Mine/Shared)
/// "All" option has been removed - users can switch between Mine and Shared views
enum ContentFilterMode: String, CaseIterable, Identifiable {
    case mine = "Mine"
    case shared = "Shared"
    
    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .mine:
            return "person.fill"
        case .shared:
            return "person.2.fill"
        }
    }
    
    var description: String {
        switch self {
        case .mine:
            return String(localized: "My Content", bundle: .appLanguage)
        case .shared:
            return String(localized: "Shared by Others", bundle: .appLanguage)
        }
    }
}
