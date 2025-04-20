import Foundation

final class FileSession: Sendable {
    let id: String
    let url: URL

    init(id: String, url: URL) {
        self.id = id
        self.url = url
    }
    
    func start() async {
        // Send initial file data

        let watcher = FileWatcher()
        let stream = watcher.observe(url: url, event: .write)

        do {
            for try await _ in stream {
                // Calculate diff and send it to the connection
            }
        } catch {
            print("Error watching file: \(error)")
        }
    }
}