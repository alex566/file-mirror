import Foundation

enum FileWatcher {
    
    enum Event {
        case write
        case delete
    }
    
    enum WatchError: Error {
        case failedToOpenFile(URL)
    }
    
    func observe(url: URL, event: Event) -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { continuation in
            let fileDescriptor = open(url.path(percentEncoded: false), O_EVTONLY)
            guard fileDescriptor >= 0 else {
                continuation.finish(throwing: WatchError.failedToOpenFile(url))
                return
            }
            
            let eventMask: DispatchSource.FileSystemEvent = switch event {
                case .write:
                    .write
                case .delete:
                    .delete
            }
            
            // Create a dispatch source to monitor the file descriptor for events
            let dispatchSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: eventMask,
                queue: .main
            )

            // Set the event handler to respond to changes
            dispatchSource.setEventHandler {
                continuation.yield()
            }

            // Set a cancel handler to close the file descriptor when monitoring stops
            dispatchSource.setCancelHandler {
                close(fileDescriptor)
            }

            // Start monitoring
            dispatchSource.resume()
            
            // Set up cancellation to properly clean up resources
            continuation.onTermination = { _ in
                dispatchSource.cancel()
            }
        }
    }
}
