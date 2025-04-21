//
//  Connection.swift
//  FileMirror
//
//  Created by Oleksii Oliinyk on 18.04.25.
//

import Network
import Foundation
import AsyncAlgorithms
import FileMirrorProtocol

public struct MirrorFile: Sendable {
    let url: URL
    let isShared: Bool

    init(url: URL, isShared: Bool) {
        self.url = url
        self.isShared = isShared
    }
}

/// Represents a connection to a peer for file mirroring
public final class Connection: Sendable {
    
    let id: String
    
    /// The underlying Network framework connection
    private let nwConnection: NWConnection
    
    /// State of the connection
    public enum State: Sendable {
        case setup
        case preparing
        case ready
        case failed(Error)
        case cancelled
        case waiting(NWError)
    }
    
    /// Actor to make connection state access thread-safe
    private actor StateContainer {
        var state: State = .setup
        
        func setState(_ newState: State) {
            state = newState
        }
        
        func getState() -> State {
            return state
        }
    }
    
    /// Thread-safe container for state
    private let stateContainer = StateContainer()
    
    /// Queue for connection operations
    private let queue = DispatchQueue(label: "com.filemirror.connection")
    
    /// Initialize with an NWConnection
    internal init(id: String, nwConnection: NWConnection) {
        self.id = id
        self.nwConnection = nwConnection
        setupConnection()
    }

    /// Start the connection
    public func start() {
        nwConnection.start(queue: queue)
    }

    /// Mirror multiple files, collecting changes into batches
    public func mirrorFiles(folder: URL, files: [MirrorFile]) async {
        let actionChannel = AsyncChannel<FileMirrorFileAction>()
        await withTaskGroup { group in
            // Start a file session for each URL
            for file in files {
                let id = UUID().uuidString
                let session = FileSession(id: id, folder: folder, url: file.url, isShared: file.isShared)
                
                // Add a task to monitor file changes
                group.addTask {
                    for await action in session.start() {
                        await actionChannel.send(action)
                    }
                }
            }
            
            // Add a task to process debounced actions
            group.addTask {
                for await actions in actionChannel.chunked(by: .repeating(every: .milliseconds(100))) {
                    print("Sending batch of \(actions.count) actions")
                    
                    let batch = FileSyncManager.batchMessage(
                        sessionId: self.id,
                        actions: actions
                    )
                    
                    do {
                        let data = try batch.serializedData()
                        await self.sendData(data)
                    } catch {
                        print("Error encoding batch: \(error)")
                    }
                }
            }
        }
    }
    
    /// Send data over the connection
    private func sendData(_ data: Data) async {
        await withCheckedContinuation { continuation in
            nwConnection.send(
                content: data,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error = error {
                        print("Error sending data: \(error)")
                    }
                    continuation.resume()
                }
            )
        }
    }
    
    /// Get the current state of the connection
    public func getState() async -> State {
        await stateContainer.getState()
    }
    
    /// Cancel the connection
    public func cancel() {
        nwConnection.cancel()
    }
    
    /// Get the remote endpoint's description
    public var endpointDescription: String {
        nwConnection.endpoint.debugDescription
    }

    /// Set up connection monitoring
    private func setupConnection() {
        nwConnection.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            
            Task {
                switch newState {
                case .setup:
                    await self.stateContainer.setState(.setup)
                case .preparing:
                    await self.stateContainer.setState(.preparing)
                case .ready:
                    await self.stateContainer.setState(.ready)
                case .failed(let error):
                    await self.stateContainer.setState(.failed(error))
                case .cancelled:
                    await self.stateContainer.setState(.cancelled)
                case .waiting(let error):
                    await self.stateContainer.setState(.waiting(error))
                @unknown default:
                    await self.stateContainer.setState(.failed(NSError(domain: "com.filemirror", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown connection state"])))
                }
            }
        }
    }
} 
