//
//  Connection.swift
//  FileMirror
//
//  Created by Oleksii Oliinyk on 18.04.25.
//

import Network
import Foundation

/// Represents a connection to a peer for file mirroring
public final class Connection: Sendable {
    
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
    internal init(nwConnection: NWConnection) {
        self.nwConnection = nwConnection
        setupConnection()
    }

    /// Start the connection
    public func start() {
        nwConnection.start(queue: queue)
    }

    public func mirrorFiles(urls: [URL]) async {
        await withTaskGroup { group in
            for url in urls {
                group.addTask {
                    let fileSession = FileSession(id: UUID().uuidString, url: url)
                    await fileSession.start()
                }
            }
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
