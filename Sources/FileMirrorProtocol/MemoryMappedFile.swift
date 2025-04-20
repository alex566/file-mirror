import Foundation

/// A class that provides memory-mapped file access
public class MemoryMappedFile {
    private let fileDescriptor: Int32
    private let fileSize: Int
    private let pointer: UnsafeMutableRawPointer
    private let isReadOnly: Bool
    
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
    
    /// Force synchronization of the memory-mapped content to disk
    public func sync() {
        msync(pointer, fileSize, MS_SYNC)
    }
    
    /// Force asynchronous synchronization of the memory-mapped content to disk
    public func asyncSync() {
        msync(pointer, fileSize, MS_ASYNC)
    }
    
    deinit {
        // Unmap the memory
        munmap(pointer, fileSize)
        
        // Close the file
        close(fileDescriptor)
    }
} 