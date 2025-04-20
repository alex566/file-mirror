import Foundation
import FileMirrorProtocol

/// A session that monitors a file and emits changes as an async stream of actions
final class FileSession: Sendable {
    let id: String
    let folder: URL
    let url: URL

    init(id: String, folder: URL, url: URL) {
        self.id = id
        self.folder = folder
        self.url = url
    }
    
    /// Start monitoring the file and return a stream of file actions
    func start() -> AsyncStream<FileMirrorFileAction> {
        AsyncStream { continuation in
            Task {
                // Get the relative path by using FileManager's relativePath method
                let absolutePath = url.path(percentEncoded: false)
                let folderPath = folder.path(percentEncoded: false)

                let path: String
                if absolutePath.hasPrefix(folderPath) {
                    path = absolutePath.replacingOccurrences(of: folderPath, with: "")
                } else {
                    print("WARNING: File \(url.lastPathComponent) is not in the folder \(folder.lastPathComponent)")
                    path = absolutePath
                }
                
                // Create initial file action for the file
                do {
                    let fileData = try Data(contentsOf: url)
                    let action = FileSyncManager.createFileActionMessage(
                        id: id, 
                        filePath: path, 
                        content: fileData
                    )
                    continuation.yield(action)
                } catch {
                    print("Error reading file content: \(error)")
                }
                
                // Watch for changes
                let watcher = FileWatcher()
                let stream = watcher.observe(url: url, event: .write)
                
                do {
                    for try await _ in stream {
                        do {
                            let updatedData = try Data(contentsOf: url)
                            let action = FileSyncManager.updateFileActionMessage(
                                id: id, 
                                filePath: path, 
                                content: updatedData
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
