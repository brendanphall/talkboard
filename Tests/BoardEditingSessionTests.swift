import Foundation
import Testing
import TalkboardCore
import UIKit
@testable import Talkboard

@Suite("Authenticated editing session", .serialized)
@MainActor
struct BoardEditingSessionTests {
    @Test("begin, revert and cancel only change the draft, never the live board")
    func draftLifecycle() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        let before = f.library.board
        #expect(!f.editor.canSave)
        #expect(f.editor.preview == nil)
        f.editor.saveDraft()
        f.editor.begin(Position(row: 0, column: 0))
        let firstDraft = try #require(f.editor.draft)
        #expect(firstDraft.label == "Cup")
        #expect(firstDraft.original?.id == ConceptID(rawValue: "cup"))
        f.editor.label("Changed"); f.editor.spokenText("Other words")
        #expect(f.editor.preview?.label == "Changed")
        #expect(f.editor.preview?.spokenText == "Other words")
        f.editor.revert()
        #expect(f.editor.draft?.label == "Cup")
        #expect(f.editor.draft?.spokenText == "Cup")
        #expect(f.editor.draft?.id != firstDraft.id)
        f.editor.cancelDraft(); f.editor.revert()
        #expect(f.editor.draft == nil)
        #expect(!f.editor.loadingPhoto)
        #expect(f.editor.failure == nil)
        #expect(f.library.board == before)
        #expect(f.store.attempts == 0)
    }

    @Test("saved label and spoken text stay separate and retain their exact bytes")
    func exactTextSave() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        let before = f.library.board
        f.editor.begin(Position(row: 0, column: 0))
        f.editor.label("  Visible cup  "); f.editor.spokenText("\nPlease give me the cup\t")
        #expect(f.editor.canSave)
        f.editor.saveDraft()
        #expect(f.editor.draft == nil)
        #expect(f.editor.failure == nil)
        #expect(f.store.attempts == 1)
        #expect(f.library.board.concepts[0].label == "  Visible cup  ")
        #expect(f.library.board.concepts[0].spokenText == "\nPlease give me the cup\t")
        #expect(f.library.board.cells == before.cells)
        #expect(f.library.board.concepts.dropFirst() == before.concepts.dropFirst())
    }

    @Test("blank label or words cannot be saved", arguments: [true, false])
    func incompleteText(label: Bool) async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        f.editor.begin(Position(row: 0, column: 0))
        if label { f.editor.label(" \n") } else { f.editor.spokenText(" \t") }
        #expect(!f.editor.canSave)
        f.editor.saveDraft()
        #expect(f.store.attempts == 0)
        #expect(f.editor.draft != nil)
    }

    @Test("a new empty cell receives one concept and its own local image")
    func addPhoto() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        let before = f.library.board
        let position = Position(row: 0, column: 2)
        f.editor.begin(position)
        #expect(f.editor.draft?.original == nil)
        #expect(!f.editor.canSave)
        f.editor.label("New fixture"); f.editor.spokenText("New fixture words")
        let input = try picture()
        await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { input }
        let prepared = try #require(f.editor.draft?.photo)
        #expect(UIImage(data: prepared) != nil)
        f.editor.saveDraft()
        let added = try #require(f.library.board.concepts.last)
        #expect(added.label == "New fixture")
        #expect(added.spokenText == "New fixture words")
        #expect(f.library.board.cells == before.cells + [Cell(position: position, conceptID: added.id)])
        #expect(f.library.board.concepts.dropLast() == before.concepts[...])
        let asset = try #require(f.library.board.assets.first)
        #expect(added.imageID == asset.id)
        #expect(asset.provenance.source == "Caregiver-selected photo")
        #expect(asset.provenance.license.contains("Private photo"))
        #expect(f.store.importedBytes[asset.id] == prepared)
        #expect(f.library.images[asset.id] != nil)
        #expect(f.store.stagedURLs.count == 1)
        #expect(f.store.stagedURLs.values.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("replacing a photo retains the card identity, coordinates and previous asset")
    func replacePhoto() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        let position = Position(row: 0, column: 0)
        let input = try picture()
        f.editor.begin(position); await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { input }; f.editor.saveDraft()
        let oldBoard = f.library.board
        let oldImage = try #require(oldBoard.concepts[0].imageID)
        f.editor.begin(position); await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { input }; f.editor.saveDraft()
        let replacement = try #require(f.library.board.concepts[0].imageID)
        #expect(replacement != oldImage)
        #expect(f.library.board.concepts[0].id == oldBoard.concepts[0].id)
        #expect(f.library.board.cells == oldBoard.cells)
        #expect(f.library.board.assets.count == 2)
        #expect(f.library.board.assets.first?.id == oldImage)
        #expect(f.store.importedBytes.keys.contains(replacement))
        #expect(f.store.stagedURLs.values.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("save failure retains the draft and live board while staging files are cleaned")
    func saveFailure() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        let before = f.library.board
        f.editor.begin(Position(row: 0, column: 0)); f.editor.label("Changed")
        let input = try picture(); await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { input }
        f.store.failSave = true
        f.editor.saveDraft()
        #expect(f.editor.draft?.label == "Changed")
        #expect(f.editor.draft?.photo != nil)
        #expect(f.editor.failure?.contains("could not be saved") == true)
        #expect(f.library.board == before)
        #expect(f.store.saved == nil)
        #expect(f.store.stagedURLs.values.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        f.store.failSave = false
        f.editor.saveDraft()
        #expect(f.editor.draft == nil)
        #expect(f.editor.failure == nil)
        #expect(f.library.board.concepts[0].label == "Changed")
    }

    @Test("a committed save that fails refresh is described honestly and keeps the draft")
    func refreshFailure() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        f.editor.begin(Position(row: 0, column: 0)); f.editor.label("Committed change")
        f.store.failRefresh = true
        f.editor.saveDraft()
        #expect(f.store.saved?.board.concepts[0].label == "Committed change")
        #expect(f.editor.draft?.label == "Committed change")
        #expect(f.editor.failure == f.library.notice)
        #expect(f.editor.failure?.contains("saved") == true)
        #expect(!f.library.canEdit)
        #expect(!f.editor.canSave)
        let notice = f.editor.failure
        f.editor.saveDraft()
        #expect(f.store.attempts == 1)
        #expect(f.editor.failure == notice)
    }

    @Test("photo errors, nil and corrupt bytes leave the prior draft available for retry")
    func photoErrorsAndRetry() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        f.editor.begin(Position(row: 0, column: 0))
        await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { throw EditingTestError.failed }
        #expect(f.editor.failure != nil)
        #expect(!f.editor.loadingPhoto)
        await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { nil }
        #expect(f.editor.failure != nil)
        await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { Data("not an image".utf8) }
        #expect(f.editor.failure != nil)
        #expect(f.editor.draft?.photo == nil)
        let input = try picture(); await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { input }
        #expect(f.editor.failure == nil)
        #expect(f.editor.draft?.photo != nil)
        #expect(!f.editor.loadingPhoto)
        #expect(f.store.attempts == 0)
    }

    @Test("a queued photo request cannot attach itself to a replacement draft")
    func staleQueuedPhoto() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        f.editor.begin(Position(row: 0, column: 0))
        let originalID = try #require(f.editor.draft?.id)
        f.editor.cancelDraft(); f.editor.begin(Position(row: 0, column: 2))
        let replacementID = try #require(f.editor.draft?.id)
        var called = false
        await f.editor.loadPhoto(for: originalID) { called = true; return nil }
        #expect(!called)
        #expect(f.editor.draft?.id == replacementID)
        #expect(f.editor.draft?.photo == nil)
        #expect(!f.editor.loadingPhoto)
        #expect(f.editor.failure == nil)
    }

    @Test("a pending photo disables save and suppresses overlapping photo loads")
    func pendingPhoto() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        f.editor.begin(Position(row: 0, column: 0))
        let gate = PhotoGate()
        let task = Task { await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { try await gate.load() } }
        defer { gate.finish(.success(nil)); task.cancel() }
        try await gate.waitUntilStarted()
        #expect(f.editor.loadingPhoto)
        #expect(!f.editor.canSave)
        var secondCalled = false
        await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { secondCalled = true; return nil }
        #expect(!secondCalled)
        f.editor.saveDraft(); #expect(f.store.attempts == 0)
        gate.finish(.success(try picture())); await task.value
        #expect(!f.editor.loadingPhoto)
        #expect(f.editor.canSave)
    }

    @Test("cancel and revert discard a pending photo result", arguments: [true, false])
    func stalePhotoAfterDraftChange(cancel: Bool) async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        f.editor.begin(Position(row: 0, column: 0))
        let originalID = try #require(f.editor.draft?.id)
        let gate = PhotoGate()
        let task = Task { await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { try await gate.load() } }
        defer { gate.finish(.success(nil)); task.cancel() }
        try await gate.waitUntilStarted()
        if cancel { f.editor.cancelDraft() } else { f.editor.revert() }
        gate.finish(.success(try picture())); await task.value
        #expect(f.editor.draft?.id != originalID)
        #expect(f.editor.draft?.photo == nil)
        #expect(f.editor.failure == nil)
        #expect(!f.editor.loadingPhoto)
        #expect(f.store.attempts == 0)
    }

    @Test("a stale photo error cannot overwrite a newer draft or its loading state")
    func stalePhotoError() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        f.editor.begin(Position(row: 0, column: 0))
        let old = PhotoGate(), current = PhotoGate()
        let oldTask = Task { await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { try await old.load() } }
        defer { old.finish(.success(nil)); oldTask.cancel() }
        try await old.waitUntilStarted()
        f.editor.begin(Position(row: 0, column: 2))
        let currentTask = Task { await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { try await current.load() } }
        defer { current.finish(.success(nil)); currentTask.cancel() }
        try await current.waitUntilStarted()
        old.finish(.failure(EditingTestError.failed)); await oldTask.value
        #expect(f.editor.loadingPhoto)
        #expect(f.editor.failure == nil)
        current.finish(.success(try picture())); await currentTask.value
        #expect(f.editor.draft?.photo != nil)
        #expect(f.editor.draft?.position == Position(row: 0, column: 2))
    }

    @Test("a photo callback from an old caregiver session cannot update or save after reauthentication", arguments: [true, false])
    func stalePhotoAfterReauthentication(success: Bool) async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        f.editor.begin(Position(row: 0, column: 0))
        let gate = PhotoGate()
        let task = Task { await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { try await gate.load() } }
        defer { gate.finish(.success(nil)); task.cancel() }
        try await gate.waitUntilStarted()
        f.auth.lock(); await f.auth.requestUnlock()
        if success { gate.finish(.success(try picture())) } else { gate.finish(.failure(EditingTestError.failed)) }
        await task.value
        #expect(!f.editor.authorized)
        #expect(!f.editor.canSave)
        #expect(f.editor.preview == nil)
        #expect(f.editor.draft?.photo == nil)
        #expect(f.editor.failure == nil)
        f.editor.label("Not allowed"); f.editor.spokenText("Not allowed")
        #expect(f.editor.draft?.label == "Cup")
        f.editor.begin(Position(row: 0, column: 2))
        #expect(f.editor.draft?.position == Position(row: 0, column: 0))
        f.editor.saveDraft(); #expect(f.store.attempts == 0)
    }

    @Test("without a current authorization or draft photo loaders never run")
    func unauthorizedAndMissingDraft() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        var called = false
        await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { called = true; return nil }
        #expect(!called)
        f.editor.begin(Position(row: 0, column: 0)); f.auth.lock()
        await f.editor.loadPhoto(for: f.editor.draft?.id ?? UUID()) { called = true; return nil }
        #expect(!called)
        #expect(!f.editor.canSave)
        #expect(f.editor.preview == nil)
    }

    @Test("canceling Files is quiet and never changes the board")
    func cancelFilePicker() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        let before = f.library.board
        f.editor.loadPacket(.failure(CocoaError(.userCancelled)))
        #expect(f.editor.failure == nil)
        #expect(f.editor.pendingBoard == nil)
        #expect(f.library.board == before)
        #expect(f.store.attempts == 0)
    }

    @Test("invalid, missing and oversized files fail without writes or pending replacement")
    func invalidPacketFiles() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        let bad = f.root.appendingPathComponent("bad.json")
        try Data("invalid JSON".utf8).write(to: bad)
        f.editor.loadPacket(.success(bad))
        #expect(f.editor.failure != nil)
        #expect(f.editor.pendingBoard == nil)
        f.editor.loadPacket(.success(f.root.appendingPathComponent("missing.json")))
        #expect(f.editor.failure != nil)
        let large = f.root.appendingPathComponent("large.json")
        try Data(repeating: 0, count: 20 * 1024 * 1024 + 1).write(to: large)
        f.editor.loadPacket(.success(large))
        #expect(f.editor.failure != nil)
        #expect(f.editor.pendingBoard == nil)
        #expect(f.store.attempts == 0)
    }

    @Test("a valid file previews without writing and cancel discards the candidate")
    func packetPreviewAndCancel() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        let before = f.library.board
        let url = try packetFile(in: f.root)
        f.editor.loadPacket(.success(url))
        #expect(f.editor.pendingBoard?.board.concepts[0].label == "Fixture picture")
        #expect(f.editor.pendingBoard?.board.concepts[0].spokenText == "Fixture spoken words")
        #expect(f.editor.pendingBoard?.board.cells[0].position == Position(row: 1, column: 2))
        #expect(f.library.board == before)
        #expect(f.store.attempts == 0)
        f.editor.cancelPacket(); f.editor.installPacket()
        #expect(f.editor.pendingBoard == nil)
        #expect(f.store.attempts == 0)
    }

    @Test("confirming a valid replacement writes its chosen media and clears the candidate")
    func installPacket() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        f.editor.loadPacket(.success(try packetFile(in: f.root)))
        f.editor.installPacket()
        #expect(f.store.attempts == 1)
        #expect(f.editor.pendingBoard == nil)
        #expect(f.editor.failure == nil)
        #expect(f.library.board.concepts.count == 1)
        #expect(f.library.board.concepts[0].label == "Fixture picture")
        #expect(f.store.importedBytes.count == 1)
        #expect(f.store.stagedURLs.values.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("failed replacement preserves the candidate for retry")
    func packetSaveFailure() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        let before = f.library.board
        f.editor.loadPacket(.success(try packetFile(in: f.root)))
        f.store.failSave = true; f.editor.installPacket()
        #expect(f.editor.pendingBoard != nil)
        #expect(f.editor.failure?.contains("could not be saved") == true)
        #expect(f.library.board == before)
        f.store.failSave = false; f.editor.installPacket()
        #expect(f.editor.pendingBoard == nil)
        #expect(f.editor.failure == nil)
    }

    @Test("a pending replacement cannot install after lock and reauthentication")
    func stalePacketAuthorization() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        let url = try packetFile(in: f.root)
        f.editor.loadPacket(.success(url))
        f.auth.lock(); await f.auth.requestUnlock()
        f.editor.installPacket()
        #expect(f.store.attempts == 0)
        f.editor.cancelPacket(); f.editor.loadPacket(.success(url))
        #expect(f.editor.pendingBoard == nil)
        #expect(f.store.attempts == 0)
    }

    @Test("a new failed file selection clears any older pending candidate")
    func failedPacketClearsCandidate() async throws {
        let f = try await EditingFixture(); defer { f.cleanup() }
        f.editor.loadPacket(.success(try packetFile(in: f.root)))
        #expect(f.editor.pendingBoard != nil)
        f.editor.loadPacket(.failure(EditingTestError.failed))
        #expect(f.editor.pendingBoard == nil)
        #expect(f.editor.failure != nil)
        f.editor.installPacket(); #expect(f.store.attempts == 0)
    }

    private func picture() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 3)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        }
        return try #require(image.pngData())
    }

    private func packetFile(in root: URL) throws -> URL {
        let packet: [String: Any] = ["version": 1, "selections": [[
            "card": ["id": "fixture-picture", "label": "Fixture picture", "spokenText": "Fixture spoken words", "slot": 7],
            "asset": ["data": "data:image/png;base64," + (try picture()).base64EncodedString(), "source": "Fixture source", "author": "Fixture author", "license": "CC0", "modifications": "None"],
        ]]]
        let file = root.appendingPathComponent(UUID().uuidString + ".json")
        try JSONSerialization.data(withJSONObject: packet).write(to: file)
        return file
    }
}

private enum EditingTestError: Error { case failed, neverStarted }

@MainActor
private final class EditingAuth: CaregiverAuthenticating {
    func authenticate() async -> Bool { true }
    func cancel() {}
}

@MainActor
private final class EditingFixture {
    let root: URL
    let auth: CaregiverController
    let store: EditingStore
    let library: BoardLibrary
    let editor: BoardEditingSession
    init() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let controller = CaregiverController(authenticator: EditingAuth())
        await controller.requestUnlock()
        let persistence = EditingStore(directory: directory.appendingPathComponent("committed", isDirectory: true))
        let boardLibrary = BoardLibrary(persistence: persistence, caregiver: controller)
        let editing = BoardEditingSession(library: boardLibrary, authorization: try #require(controller.sessionID))
        root = directory; auth = controller; store = persistence; library = boardLibrary; editor = editing
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class EditingStore: BoardPersistence {
    let directory: URL
    var saved: StoredBoard?
    var attempts = 0
    var failSave = false
    var failRefresh = false
    var stagedURLs: [AssetID: URL] = [:]
    var importedBytes: [AssetID: Data] = [:]
    init(directory: URL) { self.directory = directory }
    func load() throws -> StoredBoard? {
        if failRefresh && saved != nil { throw EditingTestError.failed }
        return saved
    }
    func save(_ board: Board, importing: [AssetID: URL]) throws {
        attempts += 1
        stagedURLs = importing
        importedBytes = try importing.mapValues { try Data(contentsOf: $0) }
        if failSave { throw EditingTestError.failed }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (id, bytes) in importedBytes {
            let asset = try #require(board.assets.first { $0.id == id })
            try bytes.write(to: directory.appendingPathComponent(asset.filename))
        }
        saved = StoredBoard(board: board, mediaDirectory: directory, recovered: false)
    }
}

@MainActor
private final class PhotoGate {
    private var continuation: CheckedContinuation<Data?, any Error>?
    private var result: Result<Data?, any Error>?
    private(set) var started = false
    func load() async throws -> Data? {
        started = true
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ result: Result<Data?, any Error>) {
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
    }
    func waitUntilStarted() async throws {
        for _ in 0..<1000 {
            if started { return }
            await Task.yield()
        }
        Issue.record("Photo loader task did not start")
        throw EditingTestError.neverStarted
    }
}
