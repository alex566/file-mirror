//
//  DiscoveredService.swift
//  FileMirrorDiscovery
//
//  Created by Oleksii Oliinyk on 18.04.25.
//

import Foundation
import Network
import FileMirrorProtocol

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
    
    public let id: String
    
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
    init(id: String, name: String, endpoint: NWEndpoint) {
        self.id = id
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
    public func connect(destinationURL: URL) -> AsyncThrowingStream<ConnectionState, Error> {
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
                        
                        print("Connection state: \(state)")
                        
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
    
    /// Start receiving mirrored files
    /// - Parameter destinationURL: The base URL where mirrored files will be saved
    /// - Returns: An async stream of mirroring events
    public func startMirroring(destinationURL: URL) -> AsyncThrowingStream<ConnectionState, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.finish(throwing: NSError(domain: "DiscoveredService", 
                                                        code: -1, 
                                                        userInfo: [NSLocalizedDescriptionKey: "Service was deallocated"]))
                    return
                }
                
                let connection = await self.stateContainer.getConnection()
                guard let connection = connection else {
                    continuation.finish(throwing: NSError(domain: "DiscoveredService", 
                                                        code: -2, 
                                                        userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
                    return
                }
                
                await self.stateContainer.setState(.mirroring(destinationURL))
                continuation.yield(.mirroring(destinationURL))
                
                // Start receiving data
                self.receiveData(connection: connection, destinationURL: destinationURL, continuation: continuation)
            }
        }
    }
    
    /// Receive and process data from the connection
    private func receiveData(connection: NWConnection, destinationURL: URL, continuation: AsyncThrowingStream<ConnectionState, Error>.Continuation) {
        // Create a data buffer to accumulate incoming data chunks
        self.receiveDataBuffer(connection: connection, buffer: Data(), destinationURL: destinationURL, continuation: continuation)
    }
    
    /// Receive and buffer data from the connection until a complete message is received
    private func receiveDataBuffer(connection: NWConnection, buffer: Data, destinationURL: URL, continuation: AsyncThrowingStream<ConnectionState, Error>.Continuation) {
        print("Receiving data chunks")
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, context, isComplete, error) in
            guard let self = self else {
                continuation.finish()
                return
            }
            
            if let error = error {
                let failedState = ConnectionState.failed(error.localizedDescription)
                Task {
                    await self.stateContainer.setState(failedState)
                    continuation.yield(failedState)
                    continuation.finish(throwing: error)
                }
                return
            }
            
            // If we received data, add it to our buffer
            if let data = data, !data.isEmpty {
                var updatedBuffer = buffer
                updatedBuffer.append(data)
                print("Received data chunk: \(data.count) bytes, buffer now: \(updatedBuffer.count) bytes")
                
                // Try to process the buffer as a complete message
                Task {
                    do {
                        if self.isCompleteMessage(updatedBuffer) {
                            print("Complete message received")
                            try await self.processSyncData(data: updatedBuffer, destinationURL: destinationURL)
                            
                            // Start receiving the next message with a fresh buffer
                            self.receiveDataBuffer(connection: connection, buffer: Data(), destinationURL: destinationURL, continuation: continuation)
                        } else {
                            // Message is incomplete, continue receiving more data
                            print("Message incomplete, continuing to receive")
                            self.receiveDataBuffer(connection: connection, buffer: updatedBuffer, destinationURL: destinationURL, continuation: continuation)
                        }
                    } catch {
                        let failedState = ConnectionState.failed(error.localizedDescription)
                        await self.stateContainer.setState(failedState)
                        continuation.yield(failedState)
                        continuation.finish(throwing: error)
                    }
                }
            } else if isComplete {
                // Connection was closed by the remote peer
                Task {
                    await self.stateContainer.setState(.disconnected)
                    continuation.yield(.disconnected)
                    continuation.finish()
                }
            } else {
                // No data received but not complete, continue receiving
                self.receiveDataBuffer(connection: connection, buffer: buffer, destinationURL: destinationURL, continuation: continuation)
            }
        }
    }
    
    /// Check if the data buffer contains a complete message
    private func isCompleteMessage(_ data: Data) -> Bool {
        // Implement message framing check based on your protocol
        // For example, check if the message has a proper header/footer,
        // or if it contains the expected length
        
        do {
            // Try to deserialize the data to see if it's a complete batch
            // This is a simple approach - if it deserializes successfully, it's complete
            _ = try FileMirrorSyncBatch(serializedBytes: data)
            return true
        } catch {
            // If deserialization fails, the message is likely incomplete
            return false
        }
    }
    
    /// Process data received from the connection
    private func processSyncData(data: Data, destinationURL: URL) async throws {
        do {
            // Parse the batch message
            let batch = try FileMirrorSyncBatch(serializedBytes: data)
            
            // Process each action
            for action in batch.actions {
                print("Process action: \(action.actionType)")
                try await applyFileAction(action, destinationURL: destinationURL)
            }
        } catch {
            print("Error processing sync data: \(error)")
            throw error
        }
    }
    
    /// Apply a file action to the local file system
    private func applyFileAction(_ action: FileMirrorFileAction, destinationURL: URL) async throws {
        let fileManager = FileManager.default
        
        // Construct the full file path relative to the destination URL
        let relativePath = action.filePath
        let fileURL = destinationURL.appendingPathComponent(relativePath)
        
        switch action.actionType {
        case .create:
            // Create directory if needed
            let directoryURL = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            
            // Write the file content
            try action.content.write(to: fileURL, options: .atomic)

        case .update:

            let handle = try FileHandle(forUpdating: fileURL)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: action.content)
            try handle.synchronize()
            handle.closeFile()
            
        case .delete:
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        case .UNRECOGNIZED(let value):
            throw NSError(domain: "DiscoveredService", 
                        code: -3, 
                        userInfo: [NSLocalizedDescriptionKey: "Unrecognized action type: \(value)"])
        }
    }
} 
