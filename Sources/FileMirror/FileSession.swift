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
        // Start watching for changes
    }
}