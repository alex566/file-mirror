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
    /// - Throws: Error if connection fails
    public func connect() async throws {
        let currentState = await stateContainer.getState()
        guard currentState == .disconnected else {
            return
        }
        
        await stateContainer.setState(.connecting)
        
        // Configure connection parameters for TCP
        let parameters = NWParameters.tcp
        
        // Use the endpoint provided during initialization
        let newConnection = NWConnection(to: endpoint, using: parameters)
        await stateContainer.setConnection(newConnection)
        
        return try await withCheckedThrowingContinuation { continuation in
            // Start the connection
            Task { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "DiscoveredService", 
                                                          code: -1, 
                                                          userInfo: [NSLocalizedDescriptionKey: "Connection setup failed"]))
                    return
                }
                
                newConnection.stateUpdateHandler = { state in
                    Task { [weak self] in
                        guard let self = self else { return }
                        
                        switch state {
                        case .ready:
                            await self.stateContainer.setState(.connected)
                            continuation.resume()
                            
                        case .failed(let error):
                            await self.stateContainer.setState(.failed(error.localizedDescription))
                            continuation.resume(throwing: error)
                            
                        case .cancelled:
                            await self.stateContainer.setState(.disconnected)
                            continuation.resume(
                                throwing: NSError(domain: "DiscoveredService",
                                                  code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Connection cancelled"])
                            )
                            
                        default:
                            break
                        }
                    }
                }
                
                newConnection.start(queue: .main)
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
