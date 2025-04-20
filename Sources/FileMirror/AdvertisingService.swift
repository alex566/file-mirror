//
//  AdvertisingService.swift
//  FileMirror
//
//  Created by Oleksii Oliinyk on 18.04.25.
//

import Foundation
import Network

/// Error types for the AdvertisingService
public enum AdvertisingServiceError: Error {
    case listenerCreationFailed(Error)
    case alreadyAdvertising
    case notAdvertising
}

/// Service for advertising the app's presence on the local network
public actor AdvertisingService {
    
    /// The underlying Network framework listener
    private var listener: NWListener?
    
    /// Queue for listener operations
    private let queue = DispatchQueue(label: "com.filemirror.advertising")
    
    /// Continuation for the connection stream
    private var connectionStreamContinuation: AsyncStream<Connection>.Continuation?
    
    /// Creates a new instance of the advertising service
    public init() {}

    /// Start advertising a service with a custom value in the TXT record
    /// - Parameters:
    ///   - serviceType: DNS-SD service type (e.g. "_myapp-sync._tcp")
    ///   - name: Instance name (e.g. device name)
    /// - Returns: An AsyncStream of Connection objects
    /// - Throws: AdvertisingServiceError if listener creation fails
    public func start(
        serviceType: String,
        name: String
    ) throws(AdvertisingServiceError) -> AsyncStream<Connection> {
        if listener != nil {
            throw .alreadyAdvertising
        }

        // Parameters: TCP transport + peer-to-peer
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        
        let id = UUID().uuidString

        let record = NWTXTRecord(["id": id])
        
        let service = NWListener.Service(
            name: name,
            type: serviceType,
            txtRecord: record
        )

        do {
            listener = try NWListener(service: service, using: parameters)
        } catch {
            throw .listenerCreationFailed(error)
        }
        
        // Create a reference to self for capture in closures
        let advertisingService = self

        return AsyncStream { continuation in
            self.connectionStreamContinuation = continuation
            
            listener?.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    print("🟢 Advertising \(name) on type \(serviceType)")
                case .failed(let error):
                    print("🔴 Listener failed: \(error)")
                    // Handle listener failure gracefully
                    Task { 
                        try? await advertisingService.stop()
                    }
                case .cancelled:
                    print("⚪️ Advertising stopped")
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { nwConnection in
                let connection = Connection(id: id, nwConnection: nwConnection)
                
                // Start the connection
                connection.start()
                
                // Send the connection to the stream
                continuation.yield(connection)
            }

            listener?.start(queue: queue)
            
            continuation.onTermination = { _ in
                Task { 
                    try? await advertisingService.stop()
                }
            }
        }
    }

    /// Stop advertising the service
    /// - Throws: AdvertisingServiceError.notAdvertising if the service is not currently advertising
    public func stop() throws(AdvertisingServiceError) {
        guard listener != nil else {
            throw .notAdvertising
        }
        
        listener?.cancel()
        listener = nil
        connectionStreamContinuation?.finish()
        connectionStreamContinuation = nil
    }
}

