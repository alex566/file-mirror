//
//  FileSyncManager.swift
//  FileMirrorProtocol
//
//  Created by Oleksii Oliinyk on 18.04.25.
//

import Foundation
import SwiftProtobuf

/// Manages file synchronization operations
public class FileSyncManager {
    
    /// Create a file action message for a file creation or update
    /// - Parameters:
    ///   - filePath: Path to the file
    ///   - content: Content of the file
    /// - Returns: A FileAction message
    public static func createFileActionMessage(
        id: String = UUID().uuidString,
        action: FilemirrorFileAction.ActionType,
        filePath: String,
        content: Data? = nil
    ) -> FilemirrorFileAction {
        var message = FilemirrorFileAction()
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
    public static func applyFileAction(_ action: FilemirrorFileAction) throws {
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
    
    /// Check if a file has changed compared to its content in memory
    /// - Parameters:
    ///   - filePath: Path to the file
    ///   - oldContent: Previous content of the file
    /// - Returns: Whether the file has changed and the new content if it has
    public static func hasFileChanged(filePath: String, oldContent: Data?) -> (changed: Bool, newContent: Data?) {
        guard let content = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            // File doesn't exist or can't be read
            return (oldContent != nil, nil)
        }
        
        if let oldContent = oldContent {
            return (content != oldContent, content)
        } else {
            // No old content, so the file is considered changed
            return (true, content)
        }
    }
}

/// Errors related to file operations
public enum FileError: Error {
    case fileNotFound(String)
    case invalidAction(String)
    case writeFailed(String)
} 