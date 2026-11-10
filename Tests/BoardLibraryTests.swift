import Foundation
import Testing
import TalkboardCore
import UIKit
@testable import Talkboard

@Suite("Persistent board and caregiver boundary", .serialized)
@MainActor
struct BoardLibraryTests {
    @Test("only a missing store shows the demo; corrupt storage never resets it")
    func startup() {
        let auth = CaregiverController(authenticator: EditorAuth())
        let store = EditorStore()
        let fresh = BoardLibrary(persistence: store, caregiver: auth)
        #expect(fresh.board == PreviewBoard.make())
        #expect(fresh.canEdit)
        store.failLoad = true
        let broken = BoardLibrary(persistence: store, caregiver: auth)
        #expect(broken.board.concepts.isEmpty)
        #expect(!broken.canEdit)
        #expect(broken.notice != nil)
        #expect(store.writes == 0)
    }

    @Test("saved labels load and previous-generation recovery is visible")
    func recovery() {
        let store = EditorStore()
        var board = PreviewBoard.make(); board.name = "Saved fixture"
        store.saved = StoredBoard(board: board, mediaDirectory: .temporaryDirectory, recovered: true)
        let library = BoardLibrary(persistence: store, caregiver: CaregiverController(authenticator: EditorAuth()))
        #expect(library.board == board)
        #expect(library.notice?.contains("previous") == true)
    }

    @Test("an old caregiver session cannot write after lock and reauthentication")
    func staleAuthorization() async throws {
        let auth = CaregiverController(authenticator: EditorAuth())
        let store = EditorStore()
        let library = BoardLibrary(persistence: store, caregiver: auth)
        #expect(auth.sessionID == nil)
        await auth.requestUnlock()
        let old = try #require(auth.sessionID)
        auth.lock(); #expect(auth.sessionID == nil)
        await auth.requestUnlock()
        let current = try #require(auth.sessionID)
        #expect(current != old)
        #expect(throws: BoardLibraryError.locked) { try library.save(library.board, session: old) }
        #expect(store.writes == 0)
        try library.save(library.board, session: current)
        #expect(store.writes == 1)
        auth.setApplicationActive(false)
        #expect(throws: BoardLibraryError.locked) { try library.save(library.board, session: current) }
        #expect(store.writes == 1)
    }

    @Test("save failures keep the live board and committed media unchanged")
    func failedSave() async throws {
        let auth = CaregiverController(authenticator: EditorAuth()); await auth.requestUnlock()
        let store = EditorStore(); let library = BoardLibrary(persistence: store, caregiver: auth)
        let old = library.board; var replacement = old; replacement.concepts[0].label = "Changed fixture"
        store.failSave = true
        #expect(throws: EditorError.failed) { try library.save(replacement, session: try #require(auth.sessionID)) }
        #expect(library.board == old)
        #expect(library.canEdit)
    }

    @Test("failure to refresh a committed save is explicit and prevents further writes")
    func failedRefresh() async throws {
        let auth = CaregiverController(authenticator: EditorAuth()); await auth.requestUnlock()
        let store = EditorStore(); let library = BoardLibrary(persistence: store, caregiver: auth)
        store.failAfterSave = true
        #expect(throws: BoardLibraryError.refreshFailed) { try library.save(library.board, session: try #require(auth.sessionID)) }
        #expect(!library.canEdit)
        #expect(library.notice?.contains("saved") == true)
        #expect(throws: BoardLibraryError.unavailable) { try library.save(library.board, session: try #require(auth.sessionID)) }
        #expect(store.writes == 1)
    }

    @Test("a recovered or different post-save board is not reported as a successful save", arguments: [true, false])
    func wrongRefresh(recovered: Bool) async throws {
        let auth = CaregiverController(authenticator: EditorAuth()); await auth.requestUnlock()
        let store = EditorStore(); let library = BoardLibrary(persistence: store, caregiver: auth)
        let old = library.board
        var replacement = old; replacement.concepts[0].label = "Changed fixture"
        store.loadAfterSaveOverride = StoredBoard(board: old, mediaDirectory: .temporaryDirectory, recovered: recovered)
        #expect(throws: BoardLibraryError.refreshFailed) { try library.save(replacement, session: try #require(auth.sessionID)) }
        #expect(library.board == old)
        #expect(!library.canEdit)
    }

    @Test("a missing post-save result is not treated as a successful refresh")
    func missingRefresh() async throws {
        let auth = CaregiverController(authenticator: EditorAuth()); await auth.requestUnlock()
        let store = EditorStore(); store.forgetSave = true
        let library = BoardLibrary(persistence: store, caregiver: auth)
        #expect(throws: BoardLibraryError.refreshFailed) { try library.save(library.board, session: try #require(auth.sessionID)) }
        #expect(!library.canEdit)
    }

    @Test("the native store survives a new owner without moving cells")
    func diskRoundTrip() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DeviceBoardPersistence(root: root)
        #expect(try store.load() == nil)
        let board = PreviewBoard.make()
        try store.save(board, importing: [:])
        let loaded = try #require(try DeviceBoardPersistence(root: root).load())
        #expect(loaded.board == board)
        #expect(!loaded.recovered)
    }

    @Test("a dangling storage symlink is not mistaken for a new installation")
    func unsafeRoot() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: root.appendingPathComponent("missing"))
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) { try DeviceBoardPersistence(root: root).load() }
        let library = BoardLibrary(persistence: DeviceBoardPersistence(root: root), caregiver: CaregiverController(authenticator: EditorAuth()))
        #expect(!library.canEdit)
        #expect(library.board.concepts.isEmpty)
    }

    @Test("local images render and missing image bytes produce an explicit notice")
    func images() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let asset = Asset(id: AssetID(rawValue: "fixture"), kind: .image, filename: "sample.png",
                          provenance: Provenance(source: "test", license: "test"))
        var board = PreviewBoard.make(); board.assets = [asset, Asset(id: AssetID(rawValue: "unused"), kind: .image, filename: "unused.png", provenance: asset.provenance)]; board.concepts[0].imageID = asset.id
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        try #require(image.pngData()).write(to: directory.appendingPathComponent(asset.filename))
        let store = EditorStore(); store.saved = StoredBoard(board: board, mediaDirectory: directory, recovered: false)
        let auth = CaregiverController(authenticator: EditorAuth())
        let library = BoardLibrary(persistence: store, caregiver: auth)
        #expect(library.images[asset.id] != nil)
        #expect(library.notice == nil)
        try FileManager.default.removeItem(at: directory.appendingPathComponent(asset.filename))
        let missing = BoardLibrary(persistence: store, caregiver: auth)
        #expect(missing.images.isEmpty)
        #expect(missing.notice != nil)
        store.saved = StoredBoard(board: board, mediaDirectory: directory, recovered: true)
        let both = BoardLibrary(persistence: store, caregiver: auth)
        #expect(both.notice?.contains("previous") == true)
        #expect(both.notice?.contains("pictures") == true)
        #expect(missing.board.concepts[0].spokenText == board.concepts[0].spokenText)
    }
}

@MainActor
private final class EditorAuth: CaregiverAuthenticating {
    func authenticate() async -> Bool { true }
    func cancel() {}
}
private enum EditorError: Error { case failed }
@MainActor
private final class EditorStore: BoardPersistence {
    var saved: StoredBoard?
    var failLoad = false
    var failSave = false
    var failAfterSave = false
    var forgetSave = false
    var writes = 0
    var loadAfterSaveOverride: StoredBoard?
    func load() throws -> StoredBoard? {
        if failLoad { throw EditorError.failed }
        return saved
    }
    func save(_ board: Board, importing: [AssetID: URL]) throws {
        if failSave { throw EditorError.failed }
        writes += 1
        if !forgetSave { saved = StoredBoard(board: board, mediaDirectory: .temporaryDirectory, recovered: false) }
        if let loadAfterSaveOverride { saved = loadAfterSaveOverride }
        if failAfterSave { failLoad = true }
    }
}
