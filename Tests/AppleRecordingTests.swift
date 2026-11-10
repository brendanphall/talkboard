import AVFoundation
import Foundation
import Testing
import TalkboardCore
@testable import Talkboard

@Suite("Recorded tile audio", .serialized)
@MainActor
struct AppleRecordingTests {
    @Test("each tap replaces the previous player and starts the selected file once")
    func replacement() throws {
        var players: [RecordingPlayerSpy] = []
        var urls: [URL] = []
        let engine = AppleRecordingEngine(makePlayer: { url in
            urls.append(url)
            let player = RecordingPlayerSpy(); players.append(player); return player
        })
        let first = URL(fileURLWithPath: "/fixture/one.m4a")
        let second = URL(fileURLWithPath: "/fixture/two.m4a")
        try engine.play(url: first); try engine.play(url: second)
        #expect(urls == [first, second])
        #expect(players.map(\.plays) == [1, 1])
        #expect(players[0].stops == 1)
        #expect(players[1].stops == 0)
        engine.stop(); #expect(players[1].stops == 1)
        engine.stop(); #expect(players[1].stops == 1)
    }

    @Test("a refused playback and a decoding error leave no player running")
    func failures() throws {
        let player = RecordingPlayerSpy(); player.accepts = false
        let engine = AppleRecordingEngine(makePlayer: { _ in player })
        #expect(throws: SpeechIssue.audioUnavailable) { try engine.play(url: .temporaryDirectory) }
        #expect(player.stops == 1)
        engine.stop(); #expect(player.stops == 1)
        let bad = AppleRecordingEngine(makePlayer: { _ in throw SpeechIssue.audioUnavailable })
        #expect(throws: SpeechIssue.audioUnavailable) { try bad.play(url: .temporaryDirectory) }
    }

    @Test("reset stops and releases native state; a later tap creates a fresh player")
    func reset() throws {
        var count = 0
        let player = RecordingPlayerSpy()
        let engine = AppleRecordingEngine(makePlayer: { _ in count += 1; return player })
        try engine.play(url: .temporaryDirectory); engine.reset()
        #expect(player.stops == 1)
        try engine.play(url: .temporaryDirectory)
        #expect(count == 2); #expect(player.plays == 2)
    }

    @Test("the native decoder rejects unavailable recordings without audible output")
    func nativeMissingFile() {
        let engine = AppleRecordingEngine()
        #expect(throws: (any Error).self) { try engine.play(url: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)) }
    }

    @Test("the service forwards the selected local recording and ignores unknown concepts")
    func serviceRouting() {
        let output = RoutingRecordingSpy()
        let controller = SpeechController(engine: RoutingSpeechSpy(), audio: RoutingAudio(),
                                          preferences: RoutingPreferences(), recordings: output)
        let service = AppleSpeechService(controller: controller)
        let board = PreviewBoard.make()
        let url = URL(fileURLWithPath: "/fixture/selected.m4a")
        service.speak(conceptID: board.concepts[0].id, in: board, recordingURL: url)
        #expect(output.urls == [url])
        service.speak(conceptID: ConceptID(), in: board, recordingURL: url)
        #expect(output.urls == [url])
        service.background()
        #expect(output.stops == 2)
    }

    @Test("only the selected concept's recording asset resolves inside its stored generation")
    func resolution() {
        let store = RecordingStore()
        var board = PreviewBoard.make()
        let recording = Asset(kind: .recording, filename: "fixture.m4a", provenance: Provenance(source: "test", license: "test"))
        board.assets.append(recording); board.concepts[0].recordingID = recording.id
        store.saved = StoredBoard(board: board, mediaDirectory: URL(fileURLWithPath: "/fixture/generation"), recovered: false)
        let library = BoardLibrary(persistence: store, caregiver: CaregiverController(authenticator: RecordingAuth()))
        #expect(library.recordingURL(for: board.concepts[0].id) == URL(fileURLWithPath: "/fixture/generation/fixture.m4a"))
        #expect(library.recordingURL(for: board.concepts[1].id) == nil)
        #expect(library.recordingURL(for: ConceptID()) == nil)
        var invalid = board; invalid.assets[0].kind = .image
        store.saved = StoredBoard(board: invalid, mediaDirectory: URL(fileURLWithPath: "/fixture/generation"), recovered: false)
        let wrongKind = BoardLibrary(persistence: store, caregiver: CaregiverController(authenticator: RecordingAuth()))
        #expect(wrongKind.recordingURL(for: board.concepts[0].id) == nil)
        let empty = BoardLibrary(persistence: RecordingStore(), caregiver: CaregiverController(authenticator: RecordingAuth()))
        #expect(empty.recordingURL(for: board.concepts[0].id) == nil)
    }
}

@MainActor
private final class RecordingPlayerSpy: NativeRecordingPlaying {
    var accepts = true
    var plays = 0
    var stops = 0
    func play() -> Bool { plays += 1; return accepts }
    func stop() { stops += 1 }
}

@MainActor
private final class RoutingRecordingSpy: SpeechRecordingEngine {
    var urls: [URL] = []
    var stops = 0
    func play(url: URL) throws { urls.append(url) }
    func stop() { stops += 1 }
    func reset() {}
}
@MainActor
private final class RoutingSpeechSpy: SpeechEngine {
    var installedVoices: [SpeechVoice] { [] }
    func speak(text: String, voiceID: String) throws { Issue.record("Recording should bypass synthesis") }
    func stop() {}
    func reset() {}
}
@MainActor
private final class RoutingAudio: SpeechAudio {
    func activate() throws {}
    func deactivate() throws {}
}
@MainActor
private final class RoutingPreferences: SpeechPreferences { var preferredVoiceID: String? }

@MainActor
private final class RecordingAuth: CaregiverAuthenticating {
    func authenticate() async -> Bool { true }
    func cancel() {}
}
@MainActor
private final class RecordingStore: BoardPersistence {
    var saved: StoredBoard?
    func load() throws -> StoredBoard? { saved }
    func save(_ board: Board, importing: [AssetID: URL]) throws { Issue.record("No writes expected") }
}
