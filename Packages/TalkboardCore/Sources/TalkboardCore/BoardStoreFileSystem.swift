import Foundation

/// Atomic replacement must leave the destination unchanged if it throws.
/// Injection is internal: callers use the real filesystem, tests inject storage faults.
protocol BoardStoreFileSystem {
    func exists(_ url: URL) -> Bool
    func read(_ url: URL) throws -> Data
    func contents(_ url: URL) throws -> [String]
    func write(_ data: Data, to url: URL, atomically: Bool) throws
    func createDirectory(_ url: URL) throws
    func validateDirectory(_ url: URL) throws
    func remove(_ url: URL) throws
}

struct LocalBoardStoreFileSystem: BoardStoreFileSystem {
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func read(_ url: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw BoardStoreError.unsafeStorage
        }
        return try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL, atomically: Bool) throws {
        try data.write(to: url, options: atomically ? .atomic : [])
    }

    func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func validateDirectory(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw BoardStoreError.unsafeStorage
        }
    }

    func contents(_ url: URL) throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: url.path) }

    func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
}
