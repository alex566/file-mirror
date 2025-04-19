//
//  DiscoveredService.swift
//  FileMirrorDiscovery
//
//  Created by Oleksii Oliinyk on 18.04.25.
//

import Foundation
import Network

/// Connection state for a discovered service
public enum ConnectionState: Sendable, Equatable {
    /// Not connected to the service
    case disconnected
    /// Attempting to connect to the service
    case connecting
    /// Connected to the service
    case connected
    /// Currently mirroring files
    case mirroring(URL)
    /// Connection failed with error
    case failed(String)
}

/// Represents a discovered service for mirroring
public final class DiscoveredService: Sendable {
    
    /// Service name as discovered by Bonjour
    public let name: String
    
    /// Network endpoint for the service
    private let endpoint: NWEndpoint
    
    /// Actor to make connection state access thread-safe
    private actor StateContainer {
        var connectionState: ConnectionState = .disconnected
        var connection: NWConnection?
        
        func setState(_ newState: ConnectionState) {
            connectionState = newState
        }
        
        func getState() -> ConnectionState {
            return connectionState
        }
        
        func setConnection(_ newConnection: NWConnection?) {
            connection = newConnection
        }
        
        func getConnection() -> NWConnection? {
            return connection
        }
    }
    
    /// Thread-safe container for state
    private let stateContainer = StateContainer()
    
    /// Creates a new discovered service
    /// - Parameters:
    ///   - name: The name of the service from Bonjour
    ///   - endpoint: The network endpoint to connect to
    init(name: String, endpoint: NWEndpoint) {
        self.name = name
        self.endpoint = endpoint
    }
    
    deinit {
        // We can't use await here directly in deinit, so we need to detach the task
        // but we should not capture self strongly
        let stateContainer = self.stateContainer
        Task.detached {
            // Cancel any active connection
            if let connection = await stateContainer.getConnection() {
                connection.cancel()
            }
            
            // Update state
            await stateContainer.setState(.disconnected)
        }
    }
    
    /// Get the current connection state
    public func getConnectionState() async -> ConnectionState {
        await stateContainer.getState()
    }
    
    /// Connect to the discovered service
    /// - Returns: An AsyncThrowingStream that emits connection state updates
    /// - Throws: Error if connection fails to start
    public func connect() -> AsyncThrowingStream<ConnectionState, Error> {
        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.finish(throwing: NSError(domain: "DiscoveredService", 
                                                         code: -1, 
                                                         userInfo: [NSLocalizedDescriptionKey: "Service was deallocated"]))
                    return
                }
                
                let currentState = await self.stateContainer.getState()
                guard currentState == .disconnected else {
                    // Already in a non-disconnected state, yield the current state and finish
                    continuation.yield(currentState)
                    continuation.finish()
                    return
                }
                
                await self.stateContainer.setState(.connecting)
                continuation.yield(.connecting)
                
                // Configure connection parameters for TCP
                let parameters = NWParameters.tcp
                
                // Use the endpoint provided during initialization
                let newConnection = NWConnection(to: self.endpoint, using: parameters)
                await self.stateContainer.setConnection(newConnection)
                
                newConnection.stateUpdateHandler = { state in
                    Task { [weak self] in
                        guard let self = self else { 
                            continuation.finish()
                            return 
                        }
                        
                        switch state {
                        case .ready:
                            await self.stateContainer.setState(.connected)
                            continuation.yield(.connected)
                            
                        case .failed(let error):
                            let failedState = ConnectionState.failed(error.localizedDescription)
                            await self.stateContainer.setState(failedState)
                            continuation.yield(failedState)
                            continuation.finish(throwing: error)
                            
                        case .cancelled:
                            await self.stateContainer.setState(.disconnected)
                            continuation.yield(.disconnected)
                            continuation.finish()
                            
                        default:
                            break
                        }
                    }
                }
                
                newConnection.start(queue: .main)
                
                // Set up the continuation's termination handler
                continuation.onTermination = { [weak self] _ in
                    Task { [weak self] in
                        await self?.disconnect()
                    }
                }
            }
        }
    }
    
    /// Disconnect from the service
    public func disconnect() async {
        if let connection = await stateContainer.getConnection() {
            connection.cancel()
        }
        await stateContainer.setConnection(nil)
        
        let currentState = await stateContainer.getState()
        if case .mirroring = currentState {
            // Stop mirroring logic if needed
        }
        
        await stateContainer.setState(.disconnected)
    }

    public func startMirroring(to destinationURL: URL) async throws {
        
    }
    
    /// Stop mirroring files
    public func stopMirroring() async {
        
    }
} 
