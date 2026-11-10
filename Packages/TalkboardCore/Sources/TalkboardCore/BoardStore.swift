import Foundation

public enum BoardStoreError: Error, Equatable, Sendable {
    case noRecoverableBoard
    case invalidManifest
    case missingMedia(AssetID)
    case unexpectedMedia
    case unsafeStorage
}

public struct LoadedBoard: Sendable {
    public enum Source: Sendable { case current, previous }
    public let board: Board
    public let mediaDirectory: URL
    /// Recovery is explicit; the app must tell the caregiver when this is `.previous`.
    public let source: Source
}

/// A single board with its last good version, including each version's media (AAC-008).
/// Use one serial owner and a dedicated, trusted Application Support directory. Concurrent
/// stores and hostile filesystem mutation are unsupported. This provides process-crash
/// atomicity through same-volume atomic file replacement, not a power-loss/fsync guarantee.
///
/// Generations stay private until the manifest commits. A killed writer may leave an
/// unreferenced generation, but it can never become the live board. Generations are kept
/// rather than garbage-collected so media URLs held by readers remain valid.
public final class BoardStore {
    private let root: URL
    private let files: any BoardStoreFileSystem
    private var manifestURL: URL { root.appendingPathComponent("manifest.json") }

    public convenience init(root: URL) {
        self.init(root: root, files: LocalBoardStoreFileSystem())
    }

    init(root: URL, files: any BoardStoreFileSystem) {
        self.root = root
        self.files = files
    }

    public func load(knownBoards: Set<BoardID> = []) throws -> LoadedBoard {
        guard files.exists(manifestURL) else { throw BoardStoreError.noRecoverableBoard }
        let manifest = try readManifest()
        return try recover(manifest, knownBoards: knownBoards).loaded
    }

    /// Import only new/replacement assets. Other assets are copied from the last good
    /// generation by stable asset ID. No committed media file is ever overwritten.
    public func save(_ board: Board, importing: [AssetID: URL] = [:], knownBoards: Set<BoardID> = []) throws {
        let data = try BoardCodec.encode(board, knownBoards: knownBoards)
        guard Set(importing.keys).isSubset(of: Set(board.assets.map(\.id))) else {
            throw BoardStoreError.unexpectedMedia
        }
        let previous = try previousForSave(knownBoards: knownBoards)
        try files.createDirectory(root)
        try files.validateDirectory(root)
        let id = UUID().uuidString
        let directory = generationURL(id)
        do {
            try prepare(board, data: data, importing: importing, previous: previous?.loaded, directory: directory)
            let manifest = Manifest(current: id, previous: previous?.id)
            try files.write(JSONEncoder().encode(manifest), to: manifestURL, atomically: true)
        } catch {
            // Cleanup failure leaves only an unreferenced private generation. Never mask
            // the save error or delete a committed version while trying to recover space.
            try? files.remove(directory)
            throw error
        }
    }

    private struct Manifest: Codable {
        let current: String
        let previous: String?
    }

    private struct Recovery {
        let id: String
        let loaded: LoadedBoard
    }

    private func previousForSave(knownBoards: Set<BoardID>) throws -> Recovery? {
        if files.exists(manifestURL) { return try recover(readManifest(), knownBoards: knownBoards) }
        if files.exists(root) {
            try files.validateDirectory(root)
            guard try files.contents(root).isEmpty else { throw BoardStoreError.invalidManifest }
        }
        return nil
    }

    private func generationURL(_ id: String) -> URL { root.appendingPathComponent(".generation-\(id)") }

    private func readManifest() throws -> Manifest {
        try files.validateDirectory(root)
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: files.read(manifestURL)),
              UUID(uuidString: manifest.current) != nil,
              manifest.previous.map({ UUID(uuidString: $0) != nil }) ?? true else {
            throw BoardStoreError.invalidManifest
        }
        return manifest
    }

    private func recover(_ manifest: Manifest, knownBoards: Set<BoardID>) throws -> Recovery {
        if let loaded = try readRecoverable(manifest.current, source: .current, knownBoards: knownBoards) {
            return Recovery(id: manifest.current, loaded: loaded)
        }
        if let id = manifest.previous,
           let loaded = try readRecoverable(id, source: .previous, knownBoards: knownBoards) {
            return Recovery(id: id, loaded: loaded)
        }
        throw BoardStoreError.noRecoverableBoard
    }

    private func readRecoverable(_ id: String, source: LoadedBoard.Source, knownBoards: Set<BoardID>) throws -> LoadedBoard? {
        do {
            let directory = generationURL(id)
            let media = directory.appendingPathComponent("media")
            try files.validateDirectory(directory)
            try files.validateDirectory(media)
            let board = try BoardCodec.decode(files.read(directory.appendingPathComponent("board.json")), knownBoards: knownBoards)
            for asset in board.assets { _ = try files.read(media.appendingPathComponent(asset.filename)) }
            return LoadedBoard(board: board, mediaDirectory: media, source: source)
        } catch BoardCodecError.unsupportedSchemaVersion(let version) {
            throw BoardCodecError.unsupportedSchemaVersion(version)
        } catch BoardCodecError.unknownFields(let fields) {
            throw BoardCodecError.unknownFields(fields)
        } catch {
            return nil
        }
    }

    private func prepare(_ board: Board, data: Data, importing: [AssetID: URL], previous: LoadedBoard?, directory: URL) throws {
        let media = directory.appendingPathComponent("media")
        try files.createDirectory(media)
        for asset in board.assets {
            let source: URL
            if let imported = importing[asset.id] {
                source = imported
            } else if let old = previous?.board.assets.first(where: { $0.id == asset.id }), let previous {
                source = previous.mediaDirectory.appendingPathComponent(old.filename)
            } else {
                throw BoardStoreError.missingMedia(asset.id)
            }
            try files.write(files.read(source), to: media.appendingPathComponent(asset.filename), atomically: false)
        }
        try files.write(data, to: directory.appendingPathComponent("board.json"), atomically: false)
    }
}
