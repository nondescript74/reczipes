//
//  ReczipesApp.swift
//  Reczipes
//
//  Created by Zahirudeen Premji on 7/6/21.
//

import SwiftUI

@main
struct ReczipesApp: App {
    var body: some Scene {
        WindowGroup {
            ApplicationView()
                .environmentObject(OrderingList())
                .environmentObject(UserData())
                .environmentObject(MyFridge())
                .environmentObject(RecipeRatio())
                .environmentObject(RecipeBeingBuilt())
//                .environmentObject(RecipeIngredients())
//                .environmentObject(RecipeInstructions())
//                .environmentObject(RecipeImages())
        }
    }
}
