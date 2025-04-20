import Foundation
import FileMirrorProtocol

/// A session that monitors a file and emits changes as an async stream of actions
final class FileSession: Sendable {
    let id: String
    let folder: URL
    let url: URL
    let isShared: Bool

    init(id: String, folder: URL, url: URL, isShared: Bool) {
        self.id = id
        self.folder = folder
        self.url = url
        self.isShared = isShared
    }
    
    /// Start monitoring the file and return a stream of file actions
    func start() -> AsyncStream<FileMirrorFileAction> {
        AsyncStream { continuation in
            Task {
                // Calculate the relative path using a more robust method
                let relativePath = url.relativePath(from: folder)

                print("Relative path: \(relativePath)")
                
                // Create initial file action for the file
                do {
                    let fileData = try Data(contentsOf: url)
                    let action = FileSyncManager.createFileActionMessage(
                        id: id, 
                        filePath: relativePath, 
                        content: fileData
                    )
                    continuation.yield(action)
                } catch {
                    print("Error reading file content: \(error)")
                }
                
                // Watch for changes
                let watcher = FileWatcher()
                let stream = watcher.observe(url: url, event: .write)

                let sharedMmap: MemoryMappedFile? = if isShared {
                    try MemoryMappedFile(path: url.path, readOnly: false)
                } else {
                    nil
                }
                
                do {
                    for try await _ in stream {
                        do {
                            let updatedData = try Data(contentsOf: url)
                            let action = FileSyncManager.updateFileActionMessage(
                                id: id, 
                                filePath: relativePath, 
                                content: updatedData,
                                shared: sharedMmap?.readAll()
                            )
                            continuation.yield(action)
                        } catch {
                            print("Error reading updated file content: \(error)")
                        }
                    }
                } catch {
                    print("Error watching file: \(error)")
                    continuation.finish()
                }
            }
            
            continuation.onTermination = { _ in
                // Clean up resources when the stream is terminated
                print("FileSession for \(self.url.lastPathComponent) terminated")
            }
        }
    }
}

// MARK: - URL Path Extensions

extension URL {
    /// Calculate the relative path from a base URL to this URL
    func relativePath(from base: URL) -> String {
        // Ensure both URLs use the same standardization and resolve symlinks
        let destComponents = self.standardized.resolvingSymlinksInPath().pathComponents
        let baseComponents = base.standardized.resolvingSymlinksInPath().pathComponents

        // Find number of common path components
        var i = 0
        while i < destComponents.count && i < baseComponents.count
            && destComponents[i] == baseComponents[i] {
                i += 1
        }

        // Build relative path
        var relComponents = Array(repeating: "..", count: baseComponents.count - i)
        relComponents.append(contentsOf: destComponents[i...])
        let relativePath = relComponents.joined(separator: "/")
        
        // If the path is empty, return "." to indicate current directory
        return relativePath.isEmpty ? "." : relativePath
    }
}
