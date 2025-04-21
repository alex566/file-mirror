import Foundation
import Dispatch

/// A class that provides memory-mapped file access
public final class MemoryMappedFile: @unchecked Sendable {
    private let fileDescriptor: Int32
    private let fileSize: Int
    private let pointer: UnsafeMutableRawPointer
    private let isReadOnly: Bool
    private var pollingTask: Task<Void, Never>?
    private let lock = NSLock()
    
    /// Opens a file as memory-mapped
    /// - Parameters:
    ///   - path: Path to the file
    ///   - readOnly: Whether the file should be opened in read-only mode
    /// - Throws: Error if the file cannot be opened or mapped
    public init(path: String, readOnly: Bool = true) throws {
        // Open the file
        let flags = readOnly ? O_RDONLY : O_RDWR
        fileDescriptor = open(path, flags, 0)
        guard fileDescriptor != -1 else {
            throw NSError(domain: "FileError", code: Int(errno), 
                userInfo: [NSLocalizedDescriptionKey: "Failed to open file at \(path)"])
        }
        
        // Get file size
        var status = stat()
        fstat(fileDescriptor, &status)
        fileSize = Int(status.st_size)
        
        // Memory map the file
        let protection = readOnly ? PROT_READ : PROT_READ | PROT_WRITE
        let mapType = MAP_SHARED 
        
        guard let mappedPointer = mmap(nil, fileSize, protection, mapType, fileDescriptor, 0) else {
            close(fileDescriptor)
            throw NSError(domain: "MemoryError", code: Int(errno), 
                userInfo: [NSLocalizedDescriptionKey: "Failed to map memory"])
        }
        
        pointer = mappedPointer
        isReadOnly = readOnly
    }
    
    /// Calculate a simple checksum of the memory content to detect changes
    private func calculateChecksum() -> Int {
        var checksum = 0
        
        // Read memory in chunks to improve performance
        let chunkSize = min(4096, fileSize)
        
        for offset in stride(from: 0, to: fileSize, by: chunkSize) {
            let size = min(chunkSize, fileSize - offset)
            let ptr = pointer.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
            
            for i in 0..<size {
                checksum = ((checksum << 5) &+ checksum) &+ Int(ptr[i])
            }
        }
        
        return checksum
    }
    
    /// Watch for changes in the memory-mapped file using polling
    /// - Parameters:
    ///   - interval: The polling interval in seconds
    /// - Returns: An AsyncStream that emits when changes are detected
    public func watchForChanges(interval: TimeInterval = 0.05) -> AsyncStream<Void> {
        lock.lock()
        defer { lock.unlock() }
        
        // Cancel any existing polling task
        pollingTask?.cancel()
        
        // Create an AsyncStream to notify about changes
        return AsyncStream { continuation in
            var lastChecksum = self.calculateChecksum()
            
            // Start a new polling task
            self.pollingTask = Task { [self] in
                while !Task.isCancelled {
                    do {
                        // Wait for the specified interval
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                        
                        // Check if the content has changed
                        let currentChecksum = self.calculateChecksum()
                        if currentChecksum != lastChecksum {
                            lastChecksum = currentChecksum
                            continuation.yield()
                        }
                    } catch {
                        // Task was likely cancelled
                        break
                    }
                }
                
                continuation.finish()
            }
            
            // Set up cancellation handler
            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                self.lock.lock()
                defer { self.lock.unlock() }
                self.pollingTask?.cancel()
                self.pollingTask = nil
            }
        }
    }
    
    /// Read the entire mapped file content
    /// - Returns: Data from the memory-mapped file
    public func readAll() -> Data {
        return Data(bytes: pointer, count: fileSize)
    }
    
    /// Read a portion of the mapped file
    /// - Parameters:
    ///   - offset: Offset from the beginning of the file
    ///   - length: Length of data to read
    /// - Returns: Data from the specified range
    public func read(offset: Int, length: Int) -> Data {
        guard offset >= 0, length >= 0, offset + length <= fileSize else {
            return Data()
        }
        let offsetPointer = pointer.advanced(by: offset)
        return Data(bytes: offsetPointer, count: length)
    }
    
    /// Write data to the memory-mapped file (changes may not be synchronized to disk immediately)
    /// - Parameters:
    ///   - data: Data to write
    ///   - offset: Offset from the beginning of the file
    /// - Throws: Error if the file is read-only or write fails
    public func write(data: Data, offset: Int) throws {
        guard !isReadOnly else {
            throw NSError(domain: "FileError", code: 0, 
                userInfo: [NSLocalizedDescriptionKey: "Cannot write to read-only mapped file"])
        }
        
        guard offset >= 0, offset + data.count <= fileSize else {
            throw NSError(domain: "FileError", code: 0, 
                userInfo: [NSLocalizedDescriptionKey: "Write operation would exceed file size"])
        }
        
        let offsetPointer = pointer.advanced(by: offset)
        data.withUnsafeBytes { bytes in
            _ = memcpy(offsetPointer, bytes.baseAddress, data.count)
        }
    }

    deinit {
        // Cancel any ongoing polling
        pollingTask?.cancel()
        
        // Unmap the memory
        munmap(pointer, fileSize)
        
        // Close the file
        close(fileDescriptor)
    }
} 