import Foundation
import Observation
import TalkboardCore
import UIKit

struct StoredBoard {
    let board: Board
    let mediaDirectory: URL
    let recovered: Bool
}

@MainActor
protocol BoardPersistence {
    func load() throws -> StoredBoard?
    func save(_ board: Board, importing: [AssetID: URL]) throws
}

@MainActor
struct DeviceBoardPersistence: BoardPersistence {
    let root: URL
    private var store: BoardStore { BoardStore(root: root) }
    func load() throws -> StoredBoard? {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: root.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw BoardStoreError.unsafeStorage }
        let loaded = try store.load()
        return StoredBoard(board: loaded.board, mediaDirectory: loaded.mediaDirectory,
                           recovered: loaded.source == .previous)
    }
    func save(_ board: Board, importing: [AssetID: URL]) throws { try store.save(board, importing: importing) }
}

enum BoardLibraryError: Error, Equatable { case locked, unavailable, refreshFailed }

@MainActor
@Observable
final class BoardLibrary {
    private(set) var board: Board
    private(set) var images: [AssetID: UIImage] = [:]
    private(set) var canEdit = true
    private(set) var notice: String?
    private var mediaDirectory: URL?
    private var demonstrationMedia: [AssetID: URL] = [:]
    private let persistence: any BoardPersistence
    private let caregiver: CaregiverController

    init(persistence: any BoardPersistence, caregiver: CaregiverController, demonstration: Board = PreviewBoard.make(), demonstrationMedia: [AssetID: URL] = [:]) {
        self.persistence = persistence
        self.caregiver = caregiver
        board = demonstration
        do {
            if let loaded = try persistence.load() {
                publish(loaded)
            } else {
                let ids = Set(demonstration.assets.map(\.id))
                self.demonstrationMedia = demonstrationMedia.filter { ids.contains($0.key) }
                images = self.demonstrationMedia.compactMapValues { UIImage(contentsOfFile: $0.path) }
            }
        } catch {
            board = Board(id: BoardID(rawValue: "unavailable"), name: "Board unavailable", grid: GridSize(rows: 3, columns: 5))
            canEdit = false
            notice = "The saved board could not open. It has not been replaced. Use your backup board."
        }
    }

    convenience init(caregiver: CaregiverController, storeName: String = "Talkboard", demonstration: Board? = nil) {
        let demo = demonstration ?? PublicDemoBoard.make()
        let media = storeName == "Talkboard" ? AlphaSymbolLibrary.urls : [:]
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--silent-speech-test") {
            let publicDemo = ProcessInfo.processInfo.arguments.contains("--public-demo-test")
            let fixture = storeName == "TalkboardPeople" ? PeopleBoard.testFixture : PreviewBoard.make()
            self.init(persistence: PreviewBoardPersistence(), caregiver: caregiver,
                      demonstration: publicDemo ? demo : fixture,
                      demonstrationMedia: publicDemo ? media : [:])
            return
        }
        #endif
        let support = URL.applicationSupportDirectory.appendingPathComponent(storeName, isDirectory: true)
        self.init(persistence: DeviceBoardPersistence(root: support), caregiver: caregiver,
                  demonstration: demo, demonstrationMedia: media)
    }

    func recordingURL(for conceptID: ConceptID) -> URL? {
        guard let mediaDirectory,
              let id = board.concepts.first(where: { $0.id == conceptID })?.recordingID,
              let asset = board.assets.first(where: { $0.id == id && $0.kind == .recording }) else { return nil }
        return mediaDirectory.appendingPathComponent(asset.filename)
    }

    func isAuthorized(_ session: UUID) -> Bool { caregiver.sessionID == session && caregiver.isUnlocked }

    /// Recheck at the write boundary, including after file/photo picker suspension.
    func save(_ replacement: Board, importing: [AssetID: URL] = [:], session: UUID) throws {
        guard isAuthorized(session) else { throw BoardLibraryError.locked }
        guard canEdit else { throw BoardLibraryError.unavailable }
        let ids = Set(replacement.assets.map(\.id))
        let bundled = demonstrationMedia.filter { ids.contains($0.key) }
        try persistence.save(replacement, importing: bundled.merging(importing) { _, selected in selected })
        do {
            guard let loaded = try persistence.load(), !loaded.recovered, loaded.board == replacement else { throw BoardLibraryError.refreshFailed }
            publish(loaded)
        } catch {
            notice = "Changes were saved, but the board could not refresh. Close and reopen the app."
            canEdit = false
            throw BoardLibraryError.refreshFailed
        }
    }

    private func publish(_ loaded: StoredBoard) {
        demonstrationMedia = [:]
        board = loaded.board
        mediaDirectory = loaded.mediaDirectory
        notice = loaded.recovered ? "Using the previous saved board because the latest copy could not open." : nil
        images = [:]
        var missingImage = false
        let usedImages = Set(board.concepts.compactMap(\.imageID))
        for asset in board.assets where asset.kind == .image && usedImages.contains(asset.id) {
            if let image = UIImage(contentsOfFile: loaded.mediaDirectory.appendingPathComponent(asset.filename).path) {
                images[asset.id] = image
            } else {
                missingImage = true
            }
        }
        if missingImage { notice = [notice, "Some pictures could not open. The words are still available."].compactMap { $0 }.joined(separator: " ") }
    }
}

#if DEBUG
@MainActor
private final class PreviewBoardPersistence: BoardPersistence {
    private var saved: Board?
    func load() throws -> StoredBoard? {
        saved.map { StoredBoard(board: $0, mediaDirectory: URL.temporaryDirectory, recovered: false) }
    }
    func save(_ board: Board, importing: [AssetID: URL]) throws { saved = board }
}
#endif
