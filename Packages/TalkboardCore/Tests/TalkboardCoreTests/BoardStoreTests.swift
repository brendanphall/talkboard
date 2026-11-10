import Foundation
import Testing
@testable import TalkboardCore

private let imageID = AssetID(rawValue: "placeholder-image")
private func storedBoard(_ name: String = "Cup", media: Bool = false) -> Board {
    let concept = Concept(id: ConceptID(rawValue: "cup"), label: name, spokenText: "cup", imageID: media ? imageID : nil)
    return Board(id: BoardID(rawValue: "sample"), name: name, grid: GridSize(rows: 3, columns: 5),
                 concepts: [concept], cells: [Cell(position: Position(row: 2, column: 4), conceptID: concept.id)],
                 assets: media ? [Asset(id: imageID, kind: .image, filename: "cup.jpg",
                                       provenance: Provenance(source: "invented fixture", license: "CC0"))] : [])
}

private final class Disk {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }
    var storeRoot: URL { root.appendingPathComponent("store") }
    func source(_ bytes: String = "placeholder") throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString)
        try Data(bytes.utf8).write(to: url)
        return url
    }
}

@Suite("Durable board store")
struct BoardStoreTests {
    @Test("a saved board returns unchanged from a new store instance")
    func roundTrip() throws {
        let disk = try Disk()
        try BoardStore(root: disk.storeRoot).save(storedBoard())
        let loaded = try BoardStore(root: disk.storeRoot).load()
        #expect(loaded.board == storedBoard())
        #expect(loaded.source == .current)
    }

    @Test("a damaged current board recovers the previous good board and reports it")
    func fallback() throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard("First"))
        try store.save(storedBoard("Second"))
        let current = try store.load()
        try Data("bad json".utf8).write(to: current.mediaDirectory.deletingLastPathComponent().appendingPathComponent("board.json"))
        let recovered = try store.load()
        #expect(recovered.board == storedBoard("First"))
        #expect(recovered.source == .previous)
    }

    @Test("missing storage throws instead of returning an empty board")
    func missing() throws {
        let disk = try Disk()
        #expect(throws: BoardStoreError.noRecoverableBoard) { try BoardStore(root: disk.storeRoot).load() }
        #expect(!FileManager.default.fileExists(atPath: disk.storeRoot.path))
    }

    @Test("new media commits with its board and is copied rather than borrowed")
    func newMedia() throws {
        let disk = try Disk()
        let source = try disk.source()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard(media: true), importing: [imageID: source])
        try FileManager.default.removeItem(at: source)
        let loaded = try store.load()
        #expect(loaded.board == storedBoard(media: true))
        #expect(try Data(contentsOf: loaded.mediaDirectory.appendingPathComponent("cup.jpg")) == Data("placeholder".utf8))
    }
}

private enum InjectedFailure: Error { case fullDisk }
private final class FaultFiles: BoardStoreFileSystem {
    let local = LocalBoardStoreFileSystem()
    var mutation = 0
    var failAt: Int?
    var failCleanup = false
    var observe: ((URL, Bool) throws -> Void)?
    func exists(_ url: URL) -> Bool { local.exists(url) }
    func contents(_ url: URL) throws -> [String] { try local.contents(url) }
    func read(_ url: URL) throws -> Data { try local.read(url) }
    func validateDirectory(_ url: URL) throws { try local.validateDirectory(url) }
    func createDirectory(_ url: URL) throws {
        mutation += 1
        if mutation == failAt { throw InjectedFailure.fullDisk }
        try local.createDirectory(url)
    }
    func write(_ data: Data, to url: URL, atomically: Bool) throws {
        try observe?(url, atomically)
        mutation += 1
        if mutation == failAt {
            if !atomically { try Data("partial write".utf8).write(to: url) }
            throw InjectedFailure.fullDisk
        }
        try local.write(data, to: url, atomically: atomically)
    }
    func remove(_ url: URL) throws {
        if failCleanup { throw InjectedFailure.fullDisk }
        try local.remove(url)
    }
}

private func tree(_ root: URL) throws -> [String: Data] {
    guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
    var contents: [String: Data] = [:]
    for case let url as URL in iterator {
        if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            contents[String(url.path.dropFirst(root.path.count))] = try Data(contentsOf: url)
        }
    }
    return contents
}
private func boardFile(_ loaded: LoadedBoard) -> URL {
    loaded.mediaDirectory.deletingLastPathComponent().appendingPathComponent("board.json")
}

extension BoardStoreTests {
    @Test("every failed save stage leaves both committed generations byte-for-byte unchanged", arguments: 1...5)
    func failedSave(stage: Int) throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard("First", media: true), importing: [imageID: disk.source("first")])
        try store.save(storedBoard("Second", media: true), importing: [imageID: disk.source("second")])
        let before = try tree(disk.storeRoot)
        let files = FaultFiles()
        files.failAt = stage
        #expect(throws: InjectedFailure.self) {
            try BoardStore(root: disk.storeRoot, files: files).save(storedBoard("Third", media: true), importing: [imageID: disk.source("third")])
        }
        #expect(try tree(disk.storeRoot) == before)
        #expect(try store.load().board == storedBoard("Second", media: true))
    }

    @Test("a failed first save does not publish media or an empty board", arguments: 1...5)
    func failedFirstSave(stage: Int) throws {
        let disk = try Disk()
        let files = FaultFiles()
        files.failAt = stage
        let store = BoardStore(root: disk.storeRoot, files: files)
        #expect(throws: InjectedFailure.self) { try store.save(storedBoard(media: true), importing: [imageID: disk.source()]) }
        #expect(try tree(disk.storeRoot).isEmpty)
        #expect(throws: BoardStoreError.noRecoverableBoard) { try store.load() }
    }

    @Test("the previous board remains loadable at each pre-commit write")
    func publicationBoundary() throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard("First"))
        let files = FaultFiles()
        var checkpoints = 0
        files.observe = { _, atomic in
            checkpoints += 1
            let loaded = try store.load()
            #expect(loaded.board == storedBoard("First"))
            #expect(!FileManager.default.fileExists(atPath: loaded.mediaDirectory.appendingPathComponent("cup.jpg").path))
            if checkpoints == 3 { #expect(atomic) }
        }
        try BoardStore(root: disk.storeRoot, files: files).save(storedBoard("Second", media: true), importing: [imageID: disk.source()])
        #expect(checkpoints == 3)
        #expect(try store.load().board == storedBoard("Second", media: true))
    }

    @Test("failed cleanup leaves ignored private staging and preserves the original error")
    func cleanupFailure() throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard())
        let manifest = try Data(contentsOf: disk.storeRoot.appendingPathComponent("manifest.json"))
        let files = FaultFiles()
        files.failAt = 3
        files.failCleanup = true
        #expect(throws: InjectedFailure.self) { try BoardStore(root: disk.storeRoot, files: files).save(storedBoard("Second")) }
        #expect(try Data(contentsOf: disk.storeRoot.appendingPathComponent("manifest.json")) == manifest)
        #expect(try store.load().board == storedBoard())
    }

    @Test("an invalid save is refused before any filesystem mutation")
    func invalidSave() throws {
        let disk = try Disk()
        let files = FaultFiles()
        var invalid = storedBoard()
        invalid.grid.rows = 0
        #expect(throws: BoardCodecError.invalid([.emptyGrid])) { try BoardStore(root: disk.storeRoot, files: files).save(invalid) }
        #expect(files.mutation == 0)
    }

    @Test("unreferenced imported files are refused")
    func unexpectedMedia() throws {
        let disk = try Disk()
        let files = FaultFiles()
        #expect(throws: BoardStoreError.unexpectedMedia) {
            try BoardStore(root: disk.storeRoot, files: files).save(storedBoard(), importing: [imageID: disk.source()])
        }
        #expect(files.mutation == 0)
    }

    @Test("missing new media refuses the save and removes staging")
    func missingMedia() throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard())
        let before = try tree(disk.storeRoot)
        #expect(throws: BoardStoreError.missingMedia(imageID)) { try store.save(storedBoard(media: true)) }
        #expect(try tree(disk.storeRoot) == before)
    }

    @Test("an unreadable media import leaves the board untouched")
    func missingImport() throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard())
        let before = try tree(disk.storeRoot)
        #expect(throws: (any Error).self) {
            try store.save(storedBoard(media: true), importing: [imageID: disk.root.appendingPathComponent("absent")])
        }
        #expect(try tree(disk.storeRoot) == before)
    }

    @Test("existing media follows its stable identity when its filename changes")
    func reuseMedia() throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard(media: true), importing: [imageID: disk.source()])
        let first = try store.load()
        var edited = storedBoard("Second", media: true)
        edited.assets[0].filename = "renamed.jpg"
        try store.save(edited)
        let current = try store.load()
        #expect(try Data(contentsOf: current.mediaDirectory.appendingPathComponent("renamed.jpg")) == Data("placeholder".utf8))
        #expect(try Data(contentsOf: first.mediaDirectory.appendingPathComponent("cup.jpg")) == Data("placeholder".utf8))
        #expect(current.board == edited)
    }

    @Test("an invalid current board or missing current media triggers explicit recovery", arguments: ["invalid", "missing-media", "missing-board"])
    func damagedGeneration(damage: String) throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard("First", media: true), importing: [imageID: disk.source("first")])
        try store.save(storedBoard("Second", media: true), importing: [imageID: disk.source("second")])
        let current = try store.load()
        if damage == "invalid" {
            var invalid = current.board
            invalid.grid.rows = 0
            try JSONEncoder().encode(invalid).write(to: boardFile(current))
        } else if damage == "missing-media" {
            try FileManager.default.removeItem(at: current.mediaDirectory.appendingPathComponent("cup.jpg"))
        } else {
            try FileManager.default.removeItem(at: boardFile(current))
        }
        let recovered = try store.load()
        #expect(recovered.source == .previous)
        #expect(recovered.board == storedBoard("First", media: true))
        #expect(try Data(contentsOf: recovered.mediaDirectory.appendingPathComponent("cup.jpg")) == Data("first".utf8))
        try store.save(storedBoard("Third", media: true))
        let third = try store.load()
        try Data("corrupt".utf8).write(to: boardFile(third))
        #expect(try store.load().board == storedBoard("First", media: true))
    }

    @Test("two damaged versions throw without overwriting either one")
    func bothDamaged() throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard("First"))
        let first = try store.load()
        try store.save(storedBoard("Second"))
        let second = try store.load()
        try Data("first corruption".utf8).write(to: boardFile(first))
        try Data("second corruption".utf8).write(to: boardFile(second))
        let before = try tree(disk.storeRoot)
        #expect(throws: BoardStoreError.noRecoverableBoard) { try store.load() }
        #expect(throws: BoardStoreError.noRecoverableBoard) { try store.save(storedBoard("Third")) }
        #expect(try tree(disk.storeRoot) == before)
    }

    @Test("a damaged first version cannot be silently replaced")
    func onlyVersionDamaged() throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard())
        try Data("bad".utf8).write(to: boardFile(store.load()))
        #expect(throws: BoardStoreError.noRecoverableBoard) { try store.load() }
        #expect(throws: BoardStoreError.noRecoverableBoard) { try store.save(storedBoard()) }
    }

    @Test("newer schemas and unknown fields are never downgraded by fallback", arguments: [true, false])
    func newerVersion(schema: Bool) throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard("First"))
        try store.save(storedBoard("Second"))
        let current = try store.load()
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: boardFile(current))) as? [String: Any])
        if schema { json["schemaVersion"] = 2 } else { json["future"] = "preserve me" }
        try JSONSerialization.data(withJSONObject: json).write(to: boardFile(current))
        let before = try tree(disk.storeRoot)
        let expected: BoardCodecError = schema ? .unsupportedSchemaVersion(2) : .unknownFields(["future"])
        #expect(throws: expected) { try store.load() }
        #expect(throws: expected) { try store.save(storedBoard()) }
        #expect(try tree(disk.storeRoot) == before)
    }

    @Test("navigation references are checked using the caller's known boards")
    func knownBoards() throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        let other = BoardID(rawValue: "other")
        var board = storedBoard()
        board.concepts[0].destinationID = other
        try store.save(board, knownBoards: [other])
        #expect(try store.load(knownBoards: [other]).board == board)
        #expect(throws: BoardStoreError.noRecoverableBoard) { try store.load() }
        try store.save(board, knownBoards: [other])
        #expect(try store.load(knownBoards: [other]).board == board)
    }

    @Test("malformed manifest and traversal identifiers are refused", arguments: [
        "not json", "{\"current\":\"../elsewhere\"}",
        "{\"current\":\"00000000-0000-0000-0000-000000000001\",\"previous\":\"../elsewhere\"}"
    ])
    func invalidManifest(contents: String) throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard())
        try Data(contents.utf8).write(to: disk.storeRoot.appendingPathComponent("manifest.json"))
        let before = try tree(disk.storeRoot)
        #expect(throws: BoardStoreError.invalidManifest) { try store.load() }
        #expect(throws: BoardStoreError.invalidManifest) { try store.save(storedBoard()) }
        #expect(try tree(disk.storeRoot) == before)
    }

    @Test("symlinked media is not read from outside the generation")
    func mediaSymlink() throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard(media: true), importing: [imageID: disk.source()])
        let loaded = try store.load()
        let media = loaded.mediaDirectory.appendingPathComponent("cup.jpg")
        try FileManager.default.removeItem(at: media)
        try FileManager.default.createSymbolicLink(at: media, withDestinationURL: disk.source("outside"))
        #expect(throws: BoardStoreError.noRecoverableBoard) { try store.load() }
    }

    @Test("symlinked store and generation directories are refused", arguments: ["root", "generation", "media"])
    func directorySymlink(component: String) throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard())
        let loaded = try store.load()
        let target = component == "root" ? disk.storeRoot : (component == "media" ? loaded.mediaDirectory : loaded.mediaDirectory.deletingLastPathComponent())
        let moved = disk.root.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: target, to: moved)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: moved)
        if component == "root" {
            #expect(throws: BoardStoreError.unsafeStorage) { try store.load() }
        } else {
            #expect(throws: BoardStoreError.noRecoverableBoard) { try store.load() }
        }
    }

    @Test("directories cannot be imported as media files")
    func directoryImport() throws {
        let disk = try Disk()
        #expect(throws: BoardStoreError.unsafeStorage) {
            try BoardStore(root: disk.storeRoot).save(storedBoard(media: true), importing: [imageID: disk.root])
        }
    }
}


extension BoardStoreTests {
    @Test("an empty existing root can receive its first board")
    func emptyRoot() throws {
        let disk = try Disk()
        try FileManager.default.createDirectory(at: disk.storeRoot, withIntermediateDirectories: true)
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard())
        #expect(try store.load().board == storedBoard())
    }

    @Test("a lost manifest never promotes orphan generations or silently resets storage")
    func lostManifest() throws {
        let disk = try Disk()
        let store = BoardStore(root: disk.storeRoot)
        try store.save(storedBoard())
        try FileManager.default.removeItem(at: disk.storeRoot.appendingPathComponent("manifest.json"))
        let before = try tree(disk.storeRoot)
        #expect(throws: BoardStoreError.noRecoverableBoard) { try store.load() }
        #expect(throws: BoardStoreError.invalidManifest) { try store.save(storedBoard("replacement")) }
        #expect(try tree(disk.storeRoot) == before)
    }
}

extension BoardStoreTests {
    @Test("atomic replacement publishes a new inode without modifying a reader's old hard link")
    func atomicReplacement() throws {
        let disk = try Disk()
        let destination = try disk.source("old")
        let oldReader = disk.root.appendingPathComponent("old-reader")
        try FileManager.default.linkItem(at: destination, to: oldReader)
        try LocalBoardStoreFileSystem().write(Data("new".utf8), to: destination, atomically: true)
        #expect(try Data(contentsOf: destination) == Data("new".utf8))
        #expect(try Data(contentsOf: oldReader) == Data("old".utf8))
    }

}
