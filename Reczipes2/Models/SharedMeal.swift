//
//  SharedMeal.swift
//  Reczipes2
//
//  Tracks which meals a user has shared to the public CloudKit database.

import Foundation
import SwiftData

/// Tracks which meals a user has shared to the public CloudKit database
@Model
final class SharedMeal {
    var id: UUID = UUID()
    var mealID: UUID?          // ID of the local Meal
    var cloudRecordID: String? // CloudKit record ID in public database
    var sharedByUserID: String?
    var sharedByUserName: String?
    var sharedDate: Date = Date()
    var isActive: Bool = true

    // Cached display data
    var mealName: String = ""
    var courseCount: Int = 0

    init(mealID: UUID,
         cloudRecordID: String? = nil,
         sharedByUserID: String,
         sharedByUserName: String? = nil,
         sharedDate: Date = Date(),
         mealName: String = "",
         courseCount: Int = 0) {
        self.mealID = mealID
        self.cloudRecordID = cloudRecordID
        self.sharedByUserID = sharedByUserID
        self.sharedByUserName = sharedByUserName
        self.sharedDate = sharedDate
        self.mealName = mealName
        self.courseCount = courseCount
    }
}
