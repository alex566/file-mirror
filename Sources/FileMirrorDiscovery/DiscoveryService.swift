//
//  DiscoveryService.swift
//  FileMirrorDiscovery
//
//  Created by Oleksii Oliinyk on 18.04.25.
//

import Foundation
import Network

/// Errors that can occur during service discovery
public enum DiscoveryError: Error, Sendable {
    /// Browser failed to start
    case browserFailedToStart(Error?)
    /// Browser was interrupted
    case browserInterrupted(Error?)
    /// Invalid service data received
    case invalidServiceData
    /// General network error
    case networkError(Error)
}

/// Service responsible for discovering mirroring sessions on the local network
public actor DiscoveryService {
    
    private var browser: NWBrowser?
    
    /// Creates a new discovery service
    public init() {}
    
    deinit {
        browser?.cancel()
    }

    /// Start browsing for mirroring services on the network
    /// - Parameter serviceType: The Bonjour service type to browse for
    /// - Returns: An AsyncStream of discovered services that updates when services change
    /// - Throws: DiscoveryError if browsing fails to start
    public func start(serviceType: String) -> AsyncThrowingStream<[DiscoveredService], any Error> {
        // Tear down any existing browser
        stop()
        
        return AsyncThrowingStream<[DiscoveredService], any Error> { continuation in
            // Configure parameters for TCP + peer-to-peer
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            // Describe the DNS-SD service
            let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
                type: serviceType,
                domain: nil
            )
            self.browser = NWBrowser(for: descriptor, using: parameters)
            
            // Set up the state update handler
            self.browser?.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    // Browser is ready, do nothing special as results will come in
                    break
                    
                case .failed(let error):
                    // Finish the stream with error
                    continuation.finish(throwing: DiscoveryError.browserFailedToStart(error))
                    
                    // Log the error for debugging
                    print("Browser failed: \(error.localizedDescription)")
                    
                case .cancelled:
                    // Browser was cancelled, finish the stream
                    continuation.finish()
                    
                case .waiting(let error):
                    // Browser is waiting, log the issue but don't terminate
                    print("Browser waiting: \(error.localizedDescription)")
                    
                default:
                    break
                }
            }
            
            // Set up the browse results handler to directly yield to the stream
            self.browser?.browseResultsChangedHandler = { results, changes in
                Task {
                    let services = processResults(results)
                    continuation.yield(services)
                }
            }
            
            // Start browsing
            self.browser?.start(queue: .main)
            
            // Handle stream termination
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.stop()
                }
            }
        }
    }

    /// Stop browsing for mirroring services
    public func stop() {
        browser?.cancel()
        browser = nil
    }
}

private func processResults(_ results: Set<NWBrowser.Result>) -> [DiscoveredService] {
    var services: [DiscoveredService] = []
    
    for result in results {
        switch result.endpoint {
        case let .service(name, _, _, _):
            let metadata = result.metadata
            switch metadata {
            case .none:
                break
            case .bonjour(let txt):
                let txtData = txt.dictionary
                
                let svc = DiscoveredService(
                    name: name,
                    endpoint: result.endpoint
                )
                services.append(svc)
            @unknown default:
                break
            }
            
        case .hostPort, .unix, .url, .opaque:
            // We're only interested in service endpoints
            break
            
        @unknown default:
            break
        }
    }
    
    return services
}
