//
//  SRecipeProvider.swift
//  CRecipes
//
//  Created by Zahirudeen Premji on 7/21/20.
//  Copyright © 2020 Zahirudeen Premji. All rights reserved.
//

import Foundation

public class SRecipeProvider {
    // MARK: - Properties
    fileprivate let operationQueue = OperationQueue()
    var recipeUrl: URL
    // MARK: Required Initializer
    init(recipesUrl: URL, completion: @escaping (SRecipe?) -> ()) {
        self.recipeUrl = recipesUrl
    
        // Create the operations
        let dataLoadSRecipe = DataLoadOperation(url: self.recipeUrl)
        let recipeCreate = SRecipeCreateOperation(data: nil)
        let recipeOut = SRecipeOutputOperation(srecipe: nil, completion: completion)

        let operations = [dataLoadSRecipe, recipeCreate, recipeOut]
        
        // Add dependencies
        recipeCreate.addDependency(dataLoadSRecipe)
        recipeOut.addDependency(recipeCreate)
        
        operationQueue.addOperations(operations, waitUntilFinished: false)
        #if DEBUG
        print("OperationQueue for SRecipeProvider is launched")
        #endif
    }
    
    func cancel() {
        operationQueue.cancelAllOperations()
    }
}

extension SRecipeProvider: Equatable {
    public static func == (lhs: SRecipeProvider, rhs: SRecipeProvider) -> Bool {
        lhs.recipeUrl == rhs.recipeUrl
    }
}

extension SRecipeProvider: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(recipeUrl)
    }
}
