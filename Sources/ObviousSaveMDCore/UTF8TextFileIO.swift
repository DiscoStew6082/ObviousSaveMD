import Foundation

public struct UTF8TextFileIO: TextFileIO {
    public init() {}

    public func readText(from url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    public func writeText(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
