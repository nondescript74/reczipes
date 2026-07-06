//
//  MealBackupUTType.swift
//  Reczipes2
//

import UniformTypeIdentifiers

extension UTType {
    /// Custom UTType for meal backup export files (.mealbackup)
    static let mealBackup = UTType(exportedAs: "com.headydiscy.reczipes.mealbackup",
                                   conformingTo: .json)
}

struct MealBackupFileType {
    static let fileExtension = "mealbackup"
    static let mimeType = "application/x-mealbackup"
    static let typeDescription = "Meals Backup"
    static let iconName = "fork.knife.circle.fill"
}
