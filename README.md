# FileMirror

FileMirror is a Swift library for mirroring files between devices over a local network. It uses Bonjour for service discovery and real-time file synchronization with rsync-like delta updates.

## Features

- Automatic service discovery using Bonjour
- Real-time file monitoring
- Efficient file synchronization using rsync delta algorithm
- Support for creating, updating, and deleting files
- SwiftProtobuf-based communication protocol

## Requirements

- Swift 6.1+
- iOS 16.0+ / macOS 13.0+
- Network framework
- SwiftProtobuf

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/FileMirror.git", from: "1.0.0")
]
```

## Usage

### Basic Example

```swift
import FileMirror

// Start the advertising service
let advertisingService = AdvertisingService()

// Start advertising with a specific service type and name
try await advertisingService.startAdvertising(
    serviceType: "_myapp-sync._tcp",
    name: "MyDevice",
    connectionHandler: { connection in
        // This closure is called when a new connection is established
        
        // Define files to mirror with this specific connection
        let files = [
            URL(fileURLWithPath: "/path/to/file1.txt"),
            URL(fileURLWithPath: "/path/to/file2.txt")
        ]
        
        // Start mirroring these files with the connected peer
        try await connection.startMirroring(files: files)
        
        // Later, you can stop mirroring specific files
        await connection.stopMirroring(files: [URL(fileURLWithPath: "/path/to/file1.txt")])
        
        // Or add new files to the existing connection
        await connection.startMirroring(files: [URL(fileURLWithPath: "/path/to/file3.txt")])
    }
)

// To stop advertising completely
await advertisingService.stopAdvertising()
```

### Discovering and Connecting to Services

```swift
import FileMirror

// Create a discovery service
let discoveryService = DiscoveryService()

// Start discovering peers
try await discoveryService.startDiscovery(
    serviceType: "_myapp-sync._tcp",
    discoveryHandler: { peerService in
        // This closure is called when a new peer service is discovered
        
        // Connect to the discovered peer
        let connection = try await discoveryService.connect(to: peerService)
        
        // Define files to mirror with this connection
        let files = [
            URL(fileURLWithPath: "/path/to/local/file.txt")
        ]
        
        // Start mirroring files
        try await connection.startMirroring(files: files)
    }
)

// To stop discovery
await discoveryService.stopDiscovery()
```

### Advanced Usage

See the Examples directory for more detailed examples.

## How It Works

1. **Service Discovery**: FileMirror uses Bonjour to advertise its presence on the local network.
2. **Connection Establishment**: When a peer discovers the service, it establishes a TCP connection.
3. **Connection Management**: Each connection is managed by a dedicated Connection instance.
4. **File Mirroring**: For each connection, you can specify which files to mirror.
5. **Initial Sync**: Upon starting to mirror files, FileMirror sends the current state of all monitored files.
6. **Real-time Updates**: Changes to files are detected using `DispatchSource.makeFileSystemObjectSource`.
7. **Delta Calculation**: When a file changes, only the differences (deltas) are sent, using an rsync-like algorithm.
8. **Protocol Buffers**: All messages are encoded using SwiftProtobuf for efficient serialization.

## Architecture

FileMirror consists of several key components:

- **AdvertisingService**: Handles Bonjour service registration and advertising your presence.
- **DiscoveryService**: Discovers other FileMirror services on the local network.
- **Connection**: Manages a specific connection with a peer and handles file mirroring for that connection.
- **FileSession**: Monitors and synchronizes individual files within a connection.
- **DeltaEngine**: Calculates and applies file differences using rsync-like algorithms.

## License

This project is available under the Apache License. See the LICENSE file for more info. 