import Darwin
import Foundation

public enum UTF8TextFileIOError: Error, LocalizedError, Equatable {
    case unsupportedFileType
    case fileTooLarge(actualBytes: Int, maximumBytes: Int)
    case binaryContent
    case invalidUTF8

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Only regular text files can be opened."
        case let .fileTooLarge(actualBytes, maximumBytes):
            return "The selected file is too large to open safely (\(actualBytes) bytes; limit \(maximumBytes) bytes)."
        case .binaryContent:
            return "The selected file appears to be binary, not plain text."
        case .invalidUTF8:
            return "The selected file is not valid UTF-8 text."
        }
    }
}

public struct UTF8TextFileIO: TextFileIO, Sendable {
    public let maximumReadableBytes: Int

    public init(maximumReadableBytes: Int = 20 * 1024 * 1024) {
        self.maximumReadableBytes = max(0, maximumReadableBytes)
    }

    public func readText(from url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try readTextSynchronously(from: url)
        }.value
    }

    private func readTextSynchronously(from url: URL) throws -> String {
        let fileDescriptor = try openReadableFileDescriptor(for: url)
        defer {
            Darwin.close(fileDescriptor)
        }

        try validateReadableRegularFile(fileDescriptor)

        let data = try readDataWithinLimit(fromFileDescriptor: fileDescriptor)

        guard !data.contains(0) else {
            throw UTF8TextFileIOError.binaryContent
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw UTF8TextFileIOError.invalidUTF8
        }

        return text
    }

    public func writeText(_ text: String, to url: URL) throws {
        try validateWritableDestination(at: url)

        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func validateWritableDestination(at url: URL) throws {
        try validateNoSymbolicLink(at: url)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])

        guard resourceValues.isRegularFile == true else {
            throw UTF8TextFileIOError.unsupportedFileType
        }
    }

    private func openReadableFileDescriptor(for url: URL) throws -> CInt {
        try url.withUnsafeFileSystemRepresentation { fileSystemPath in
            guard let fileSystemPath else {
                throw UTF8TextFileIOError.unsupportedFileType
            }

            let fileDescriptor = Darwin.open(fileSystemPath, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)

            guard fileDescriptor >= 0 else {
                throw fileSystemError(errorNumber: errno)
            }

            return fileDescriptor
        }
    }

    private func validateReadableRegularFile(_ fileDescriptor: CInt) throws {
        var fileStatus = stat()

        guard fstat(fileDescriptor, &fileStatus) == 0 else {
            throw fileSystemError(errorNumber: errno)
        }

        guard (fileStatus.st_mode & S_IFMT) == S_IFREG else {
            throw UTF8TextFileIOError.unsupportedFileType
        }

        guard fileStatus.st_size >= 0 else {
            throw UTF8TextFileIOError.unsupportedFileType
        }

        let fileSize = clampedByteCount(fileStatus.st_size)

        guard fileSize <= maximumReadableBytes else {
            throw UTF8TextFileIOError.fileTooLarge(
                actualBytes: fileSize,
                maximumBytes: maximumReadableBytes
            )
        }
    }

    private func readDataWithinLimit(fromFileDescriptor fileDescriptor: CInt) throws -> Data {
        let fileHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: false)

        let readLimit = maximumReadableBytes == Int.max ? maximumReadableBytes : maximumReadableBytes + 1
        let data = try fileHandle.read(upToCount: readLimit) ?? Data()

        guard data.count <= maximumReadableBytes else {
            throw UTF8TextFileIOError.fileTooLarge(
                actualBytes: data.count,
                maximumBytes: maximumReadableBytes
            )
        }

        return data
    }

    private func clampedByteCount(_ byteCount: off_t) -> Int {
        byteCount > off_t(Int.max) ? Int.max : Int(byteCount)
    }

    private func fileSystemError(errorNumber: CInt) -> Error {
        if errorNumber == ELOOP || errorNumber == EISDIR {
            return UTF8TextFileIOError.unsupportedFileType
        }

        return POSIXError(POSIXErrorCode(rawValue: errorNumber) ?? .EIO)
    }

    private func validateNoSymbolicLink(at url: URL) throws {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw UTF8TextFileIOError.unsupportedFileType
        }
    }
}
