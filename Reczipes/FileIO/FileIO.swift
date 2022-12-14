//
//  FileIO.swift
//  Reczipes
//
//  Created by Zahirudeen Premji on 7/18/21.
//

import Foundation
import UIKit
import SwiftUI
import CoreData

class FileIO: NSObject {
    // MARK: - Debug local
    private var zBug:Bool = false
    // MARK: - Properties
    var fileManager: FileManager = FileManager.default
    fileprivate enum msgs:String {
        case fileIO = "FileIO: "
        case read = "Read "
        case docudir = "Documents Debug Descrip, qty"
        case write = "Write "
        case contents = "Contents after write "
        case success = "Succeeded "
        case fail = "Failed "
        case empty = " or Empty Folder"
        case wtf = "WTF????? "
        case fileUrls = "URL found in Documents "
//        case note = "a note "
        case noteimage = "Note or Image "
        case tempz = "Temp URL "
        case count = "Count "
//        case commonCreate = "CommonCreate "
        case commonCreateReturn = "Returned Success from Commoncreate"
        case reczipesFolderExists = "Reczipes folder already exists"
        case reczipesFolderCreated = "Reczipes folder created "
        case recipeNotesFolderCreated = "RecipeNotes Folder created "
        case recipeNotesFolderExists = "RecipeNotes Folder already exists "
        case recipeImagesFolderCreated = "RecipeImages Folder created "
        case recipeImagesFolderExists = "RecipeImages Folder already exists "
        case wrotenoteorimage = "Wrote a note or an image"
//        case recNoteFldrExists = "RecipeFolder exists, contents: "
//        case cannotCreateRNotesFolder = "Cannot create Folder"
//        case cannotCreateRecipeFolder = "Cannot create Recipe Folder"
        case cannotFindFolder = "Cannot find requested folder"
//        case createdRecipeNotesFolder = "Created RecipeNotesFolder or already exists"
//        case createdRecipeNotesFolder = "Created RecipeNotesFolder"
//        case recNotesFolderExists = "RecipeNotesFolder or already exists"
//        case createdRecipeFolder = "Created the RecipeFolder or already exists"
        
//        case recipeFolderExists = "The folder requested already exists"
        case checkContentsRecipeFolder = "checkContentsRecFolder"
        case foldercontents = "Contents of Folder "
//        case xcassets = "Contents of Assets.xcassets"
    }
    // MARK: Methods
    
    //    var isDir : ObjCBool = false
    //    func checkFileExists(fullPath: URL) {
    //        if fileManager.fileExists(atPath: fullPath.absoluteString, isDirectory:&isDir) {
    //            if isDir.boolValue {
    //                // file exists and is a directory
    //            } else {
    //                // file exists and is not a directory
    //            }
    //        } else {
    //            // file does not exist
    //
    //        }}
    func checkDocuDirContents() -> [URL] {
        do {
            let myDocuDirUrl = try fileManager.url(for: .documentDirectory,
                                                   in: .userDomainMask,
                                                   appropriateFor: nil,
                                                   create: false)
            
            
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: myDocuDirUrl, includingPropertiesForKeys: nil)
                
                
                if zBug { print(msgs.fileIO.rawValue + msgs.docudir.rawValue + fileURLs.debugDescription, fileURLs.count.description)}
                
                
                return fileURLs
            } catch {
                fatalError(msgs.fileIO.rawValue + msgs.fail.rawValue)
            }
        } catch {
            fatalError(msgs.fileIO.rawValue + msgs.wtf.rawValue)
        }
    }
    
    //    func checkContentsOfDir(dirname: String) -> [URL] {
    //        do {
    //            var myDocumentsUrl = try fileManager.url(for: .documentDirectory,
    //                                                     in: .userDomainMask,
    //                                                     appropriateFor: nil,
    //                                                     create: true)
    //            myDocumentsUrl.appendPathComponent(dirname, isDirectory: true)
    //            let contents = try fileManager.contentsOfDirectory(at: myDocumentsUrl, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
    //
    //
    //            if zBug { print(msgs.fileIO.rawValue + msgs.foldercontents.rawValue + msgs.xcassets.rawValue + contents.count.description)}
    //
    //
    //            return contents
    //
    //        } catch {
    //
    //
    //            if zBug { print(msgs.fileIO.rawValue + msgs.foldercontents.rawValue + msgs.cannotFindFolder.rawValue)}
    //
    //            return []
    //        }
    //    }
    
    func getFileDataAtUrl(url: URL) -> Data {
        do {
            let data = try Data(contentsOf: url)
            return data
            
        } catch {
            fatalError(msgs.fileIO.rawValue + msgs.fail.rawValue)
        }
    }
    //
    //    func getContentsOfXCAssetsDir() -> [URL] {
    //        do {
    //            var myxcassetsUrl = try fileManager.url(for: .applicationDirectory,
    //                                                    in: .userDomainMask,
    //                                                    appropriateFor: nil,
    //                                                    create: true)
    //            myxcassetsUrl.appendPathComponent("Assets.xcassets", isDirectory: true)
    //            let contents = try fileManager.contentsOfDirectory(at: myxcassetsUrl, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
    //
    //
    //            if zBug { print(msgs.fileIO.rawValue + msgs.foldercontents.rawValue + msgs.xcassets.rawValue + contents.count.description)}
    //
    //
    //            return contents
    //
    //        } catch {
    //            fatalError(msgs.fileIO.rawValue + msgs.foldercontents.rawValue + msgs.wtf.rawValue)
    //        }
    //    }
    
    func writeFileInFolderInDocuments(folderName: String, fileNameToSave: String, fileType: String, data: Data) -> Bool {
        do {
            var myDocumentsUrl = try fileManager.url(for: .documentDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)
            myDocumentsUrl.appendPathComponent(folderName)
            
            try data.write(to: myDocumentsUrl.appendingPathComponent(fileNameToSave + delimiterFiletype + fileType))
            
            
            if zBug { print(msgs.fileIO.rawValue + msgs.write.rawValue + msgs.success.rawValue, myDocumentsUrl.debugDescription)}
            
            
            let contents = try fileManager.contentsOfDirectory(at: myDocumentsUrl, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
            
            if contents.count >= 0  {
                return true
            } else {
                return false
            }
        } catch {
            fatalError(msgs.fileIO.rawValue + msgs.write.rawValue + msgs.wtf.rawValue)
        }
    }
    
    func readFilesInFolderInDocuments(folderName: String) -> [URL] {
        do {
            var myDocumentsUrl = try fileManager.url(for: .documentDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)
            myDocumentsUrl.appendPathComponent(folderName)
            
            let contents = try fileManager.contentsOfDirectory(at: myDocumentsUrl, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
            
            if zBug { print(msgs.fileIO.rawValue + msgs.read.rawValue + msgs.success.rawValue, myDocumentsUrl.debugDescription)}
            
            
            return contents
        } catch {
            fatalError(msgs.fileIO.rawValue + msgs.read.rawValue + msgs.wtf.rawValue)
        }
        
    }
    
    func readFileInRecipeNotesOrImagesFolderInDocuments(folderName: String) -> [URL] {
        var myReturnFilesUrls:[URL] = []
        do {
            var myDocumentsUrl = try fileManager.url(for: .documentDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)
            myDocumentsUrl.appendPathComponent(recipesName)
            myDocumentsUrl.appendPathComponent(folderName)
            
            let contents = try fileManager.contentsOfDirectory(at: myDocumentsUrl, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
            
            myReturnFilesUrls = contents
            
            
            if zBug { print(msgs.fileIO.rawValue + msgs.read.rawValue + msgs.foldercontents.rawValue + " " + myReturnFilesUrls.count.description)}
            
            
        } catch {
            if zBug { print(msgs.fileIO.rawValue + msgs.read.rawValue + msgs.cannotFindFolder.rawValue)}
            
        }
        
        
        if zBug { print(msgs.fileIO.rawValue + msgs.read.rawValue + msgs.foldercontents.rawValue + msgs.count.rawValue + myReturnFilesUrls.count.description)}
        
        return myReturnFilesUrls  // can be empty
    }
    
    
    func writeFileInRecipeNotesOrImagesFolderInDocuments(folderName: String, fileNameToSave: String, fileType: String, data: Data) -> Bool {
        do {
            var myDocumentsUrl = try fileManager.url(for: .documentDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)
            myDocumentsUrl.appendPathComponent(recipesName)
            myDocumentsUrl.appendPathComponent(folderName)
            let tempz = myDocumentsUrl.appendingPathComponent(fileNameToSave.replacingOccurrences(of: " ", with: "_") + delimiterFiletype + fileType)
            
            try data.write(to: tempz)
            if zBug { print(msgs.fileIO.rawValue + msgs.write.rawValue + msgs.tempz.rawValue + tempz.absoluteString)}
            let contents = try fileManager.contentsOfDirectory(at: myDocumentsUrl, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
            if zBug { print(msgs.fileIO.rawValue + msgs.contents.rawValue + msgs.tempz.rawValue + tempz.absoluteString)}
            
            if contents.count > 0  {
                if zBug { print(msgs.fileIO.rawValue + msgs.write.rawValue + folderName + msgs.success.rawValue)}
                return true
            } else {
                if zBug { print(msgs.fileIO.rawValue + msgs.write.rawValue + folderName + msgs.fail.rawValue)}
                return false
            }
        } catch {
            if zBug { print(msgs.fileIO.rawValue + msgs.write.rawValue + folderName + msgs.wtf.rawValue)}
            return false
        }
    }
    
    func checkContentsReczipesFolder() -> [URL] {
        do {
            var myDocumentsUrl = try fileManager.url(for: .documentDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)
            myDocumentsUrl.appendPathComponent(recipesName)
            let contentsRFD = try FileManager.default.contentsOfDirectory(at: myDocumentsUrl, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
            if zBug { print(msgs.fileIO.rawValue + msgs.reczipesFolderExists.rawValue, contentsRFD.count)}
            return contentsRFD
        } catch {
            if zBug { print(msgs.fileIO.rawValue + msgs.checkContentsRecipeFolder.rawValue + recipesName + " " + msgs.cannotFindFolder.rawValue)}
            return []
        }
    }
    
    func checkContentsRecipeFolder(recipeFolder: String) -> [URL] {
        do {
            var myDocumentsUrl = try fileManager.url(for: .documentDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)
            myDocumentsUrl.appendPathComponent(recipesName)
            myDocumentsUrl.appendPathComponent(recipeFolder)
            let contentsRFD = try FileManager.default.contentsOfDirectory(at: myDocumentsUrl, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
            if zBug { print(msgs.fileIO.rawValue + msgs.reczipesFolderExists.rawValue, contentsRFD.count)}
            return contentsRFD
        } catch {
            if zBug { print(msgs.fileIO.rawValue + msgs.checkContentsRecipeFolder.rawValue + recipeFolder + " " + msgs.cannotFindFolder.rawValue)}
            return []
        }
    }
    
//    func doesFileNameExistInRecipeFolder(recipeFolder: String, fileName: String) -> Bool   {
//        var myReturn = false
//        let contentsRF = checkContentsRecipeFolder(recipeFolder: recipeFolder)
//        for aUrl in contentsRF {
//            if aUrl.description.contains(fileName) {
//                myReturn = true
//            }
//        }
//        return myReturn
//    }
    
    func createRecipeFolders() -> Bool {
        var myReturn:Bool = false
        do {
            let myUrl = try fileManager.url(for: .documentDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil,
                                            create: true)
            var fullUrl = myUrl.appending(path: recipesName)
            myReturn = fileManager.fileExists(atPath: fullUrl.absoluteString)
            if !myReturn {
                do {
                    try fileManager.createDirectory(at: fullUrl, withIntermediateDirectories: true)
                    if zBug { print(msgs.fileIO.rawValue + msgs.reczipesFolderCreated.rawValue + msgs.success.rawValue)}
                } catch {
                    // could not create directory fatal
                    fatalError("Could not create Reczipes folder????")
                }
            }
            if zBug { print(msgs.fileIO.rawValue + msgs.reczipesFolderExists.rawValue)}
                // Reczipes directory already exists, continue for check of where notes or images also exists, if not creat them
            
            fullUrl = fullUrl.appending(path: recipeNotesFolderName)
            myReturn = fileManager.fileExists(atPath: fullUrl.absoluteString)
            if !myReturn {
                do {
                    try fileManager.createDirectory(at: fullUrl, withIntermediateDirectories: true)
                    if zBug { print(msgs.fileIO.rawValue + msgs.recipeNotesFolderCreated.rawValue + msgs.success.rawValue)}
                } catch {
                    // could not create directory fatal
                    fatalError("Could not create Recipe Notes Folder folder????")
                }
            }
            if zBug { print(msgs.fileIO.rawValue + msgs.recipeNotesFolderExists.rawValue)}
                // Reczipes/RecipeNotes directory already exists, continue for check of where images also exists, if not create it
            fullUrl = myUrl.appending(path: recipesName)
            fullUrl = fullUrl.appending(path: recipeImagesFolderName)
            myReturn = fileManager.fileExists(atPath: fullUrl.absoluteString)
            if !myReturn {
                do {
                    try fileManager.createDirectory(at: fullUrl, withIntermediateDirectories: true)
                    if zBug { print(msgs.fileIO.rawValue + msgs.recipeImagesFolderCreated.rawValue + msgs.success.rawValue)}
                } catch {
                    // could not create directory fatal
                    fatalError("Could not create Recipe Images folder????")
                }
            }
            if zBug { print(msgs.fileIO.rawValue + msgs.recipeImagesFolderExists.rawValue )}
                // Reczipes/RecipeImages directory already exists, all done
            myReturn = true
        
        } catch {
            fatalError("No Documents Folder????")
        }
        
        return myReturn
    }
    
    //    func createRecipeFolders(folderName: String)  -> Bool  {
    //
    //        do {
    //            var myDocumentsUrl = try fileManager.url(for: .documentDirectory,
    //                                                     in: .userDomainMask,
    //                                                     appropriateFor: nil,
    //                                                     create: true)
    //            if folderName != recipesName {
    //                myDocumentsUrl.appendPathComponent(recipesName)
    //            }
    //
    //            myDocumentsUrl.appendPathComponent(folderName)
    //
    //            try FileManager.default.createDirectory(at: myDocumentsUrl, withIntermediateDirectories: true)
    //
    //
    //            if zBug { print(msgs.fileIO.rawValue + msgs.recipeFolderExists.rawValue + msgs.success.rawValue)}
    //
    //            return true
    //        } catch {
    //            // could not create the folder or folder exists
    //            do {
    //                var myDocumentsUrl = try fileManager.url(for: .documentDirectory,
    //                                                         in: .userDomainMask,
    //                                                         appropriateFor: nil,
    //                                                         create: true)
    //                if folderName != recipesName {
    //                    myDocumentsUrl.appendPathComponent(recipesName)
    //                }
    //                myDocumentsUrl.appendPathComponent(folderName)
    //
    //                _ = try FileManager.default.contentsOfDirectory(at: myDocumentsUrl, includingPropertiesForKeys: nil)
    //                // folder exists
    //                if zBug { print(msgs.fileIO.rawValue + msgs.recipeFolderExists.rawValue)}
    //                    return true
    //            } catch {
    //                // could not create folder
    //                if zBug { print(msgs.fileIO.rawValue + msgs.createdRecipeFolder.rawValue + msgs.fail.rawValue)}
    //                    fatalError("Could not create the folder")
    //            }
    //        }
    //    }
    
    func removeFileInRecipeFolder(recipeFolder: String, fileName: String) {
        
        do {
            var myDocumentsUrl = try fileManager.url(for: .documentDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)
            myDocumentsUrl.appendPathComponent(recipesName)
            let contents = try fileManager.contentsOfDirectory(at: myDocumentsUrl, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
            
            for aUrl in contents {
                if aUrl.description.contains(fileName) {
                    do {
                        try fileManager.removeItem(at: aUrl)
                    } catch {
                        if zBug { print(msgs.fileIO.rawValue + " Failed remove of aUrl in recipeFolder")}
                    }
                }
            }
        } catch {
            // does not exist
            return
        }
    }
}

