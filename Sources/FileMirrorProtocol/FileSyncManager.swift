//
//  FileSyncManager.swift
//  FileMirrorProtocol
//
//  Created by Oleksii Oliinyk on 18.04.25.
//

import Foundation
import SwiftProtobuf
import librsync

/// Manages file synchronization operations
public enum FileSyncManager {
    
    /// Create a file action message for a file creation or update
    /// - Parameters:
    ///   - filePath: Path to the file
    ///   - content: Content of the file
    /// - Returns: A FileAction message
    public static func createFileActionMessage(
        id: String = UUID().uuidString,
        action: FileMirrorFileAction.ActionType,
        filePath: String,
        content: Data? = nil
    ) -> FileMirrorFileAction {
        var message = FileMirrorFileAction()
        message.id = id
        message.actionType = action
        message.filePath = filePath
        if let content = content {
            message.content = content
        }
        return message
    }
    
    /// Apply a file action to the file system
    /// - Parameter action: The FileAction to apply
    /// - Throws: FileError if the operation fails
    public static func applyFileAction(_ action: FileMirrorFileAction) throws {
        let fileManager = FileManager.default
        let filePath = action.filePath
        
        switch action.actionType {
        case .create, .update:
            // Create directory if needed
            let directoryURL = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            
            // Write the file content
            try action.content.write(to: URL(fileURLWithPath: filePath))
            
        case .delete:
            if fileManager.fileExists(atPath: filePath) {
                try fileManager.removeItem(atPath: filePath)
            }
        case .UNRECOGNIZED(let value):
            throw FileError.invalidAction("Unrecognized action type: \(value)")
        }
    }
}

/// Errors related to file operations
public enum FileError: Error {
    case fileNotFound(String)
    case invalidAction(String)
    case writeFailed(String)
} 