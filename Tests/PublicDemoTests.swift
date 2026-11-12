import Foundation
import Testing
import UIKit
import TalkboardCore
@testable import Talkboard

@MainActor
struct PublicDemoTests {
    @Test func genericDemoHasIllustrationsAndNoPersonalMedia() throws {
        let board = PublicDemoBoard.make()
        #expect(board.concepts.map(\.id.rawValue) == ["dog", "stop", "no", "food", "hungry", "go", "night-night", "yes", "help", "bath", "water"])
        #expect(board.concepts.allSatisfy { $0.recordingID == nil && $0.imageID != nil })
        #expect(board.cells.count == 11)
        #expect(!board.cells.contains { $0.position == Position(row: 0, column: 2) })
        #expect(PeopleBoard.empty.concepts.isEmpty)
        #expect(AlphaSymbolLibrary.assets.count == 21)
        for asset in AlphaSymbolLibrary.assets {
            let url = try #require(AlphaSymbolLibrary.urls[asset.id])
            #expect(UIImage(contentsOfFile: url.path) != nil)
            #expect(!asset.provenance.license.isEmpty)
        }
        _ = try BoardCodec.encode(board)
    }

    @Test func firstEditCopiesDemoArtworkAndLaterSavesPreserveStoredArtwork() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let auth = CaregiverController(authenticator: DemoAuthenticator())
        await auth.requestUnlock()
        let session = try #require(auth.sessionID)
        let persistence = DeviceBoardPersistence(root: root)
        let demo = PublicDemoBoard.make()
        let library = BoardLibrary(persistence: persistence, caregiver: auth, demonstration: demo,
                                   demonstrationMedia: AlphaSymbolLibrary.urls)
        #expect(library.images.count == 11)
        var edited = demo; edited.concepts[0].label = "Example animal"
        try library.save(edited, session: session)
        #expect(library.images.count == 11)
        let saved = try #require(try persistence.load())
        let asset = try #require(edited.assets.first)
        let replacement = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let bytes = try #require(replacement.pngData())
        try bytes.write(to: saved.mediaDirectory.appendingPathComponent(asset.filename))
        let reopened = BoardLibrary(persistence: persistence, caregiver: auth, demonstration: demo,
                                    demonstrationMedia: AlphaSymbolLibrary.urls)
        #expect(reopened.board == edited)
        try reopened.save(edited, session: session)
        let resaved = try #require(try persistence.load())
        #expect(try Data(contentsOf: resaved.mediaDirectory.appendingPathComponent(asset.filename)) == bytes)
    }
}

@MainActor
private final class DemoAuthenticator: CaregiverAuthenticating {
    func authenticate() async -> Bool { true }
    func cancel() {}
}
