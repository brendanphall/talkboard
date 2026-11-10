import Foundation
import Observation
import TalkboardCore

struct TileDraft: Identifiable {
    let id = UUID()
    let position: Position
    let original: Concept?
    var label: String
    var spokenText: String
    var photo: Data?
}

@MainActor
@Observable
final class BoardEditingSession {
    let library: BoardLibrary
    let authorization: UUID
    private(set) var draft: TileDraft?
    private(set) var loadingPhoto = false
    private(set) var failure: String?
    private(set) var pendingBoard: PreparedPictureBoard?

    init(library: BoardLibrary, authorization: UUID) { self.library = library; self.authorization = authorization }
    var authorized: Bool { library.isAuthorized(authorization) && library.canEdit }
    var canSave: Bool {
        guard authorized, !loadingPhoto, let draft else { return false }
        return !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var preview: Concept? {
        guard authorized, let draft else { return nil }
        return Concept(label: draft.label, spokenText: draft.spokenText)
    }
    func begin(_ position: Position) {
        guard authorized else { return }
        let concept = library.board.cells.first(where: { $0.position == position })
            .flatMap { cell in library.board.concepts.first(where: { $0.id == cell.conceptID }) }
        draft = TileDraft(position: position, original: concept, label: concept?.label ?? "", spokenText: concept?.spokenText ?? "")
        loadingPhoto = false; failure = nil
    }
    func label(_ value: String) { if authorized { draft?.label = value } }
    func spokenText(_ value: String) { if authorized { draft?.spokenText = value } }
    func cancelDraft() { draft = nil; loadingPhoto = false; failure = nil }
    func revert() { if let draft { begin(draft.position) } }

    func loadPhoto(for id: UUID, _ load: () async throws -> Data?) async {
        guard authorized, draft?.id == id, !loadingPhoto else { return }
        loadingPhoto = true
        defer { if draft?.id == id { loadingPhoto = false } }
        do {
            guard let bytes = try await load() else { throw PhotoImportError.invalidImage }
            guard authorized, draft?.id == id else { return }
            let prepared = try PhotoImport.prepare(bytes)
            draft?.photo = prepared; failure = nil
        } catch {
            guard authorized, draft?.id == id else { return }
            failure = "The photo could not open. Try a downloaded photo or another image."
        }
    }

    func saveDraft() {
        guard canSave, let draft else { return }
        do {
            let image: Asset? = draft.photo.map { _ in
                let id = AssetID()
                return Asset(id: id, kind: .image, filename: id.rawValue + ".jpg", provenance: Provenance(
                    source: "Caregiver-selected photo", license: "Private photo; permission controlled by caregiver",
                    modifications: "Resized upright JPEG; original metadata omitted"))
            }
            let replacement: Board
            if let original = draft.original {
                replacement = try BoardEditor.replaceConcept(in: library.board, id: original.id, label: draft.label,
                    spokenText: draft.spokenText, image: image.map(BoardImageEdit.replace) ?? .keep)
            } else {
                replacement = try BoardEditor.addConcept(to: library.board, at: draft.position,
                    concept: Concept(label: draft.label, spokenText: draft.spokenText, imageID: image?.id), image: image)
            }
            var media: [AssetID: Data] = [:]
            if let image, let bytes = draft.photo { media[image.id] = bytes }
            try save(replacement, media: media)
            cancelDraft()
        } catch { saveFailure(error) }
    }

    func loadPacket(_ result: Result<URL, any Error>) {
        guard authorized else { return }
        pendingBoard = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20 * 1024 * 1024 else { throw PicturePacketError.invalid }
            pendingBoard = try PicturePacket.prepare(Data(contentsOf: url, options: .mappedIfSafe))
            failure = nil
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch { failure = "The picture file could not open. Use a prepared picture-choices JSON file with PNG or JPEG images." }
    }
    func cancelPacket() { pendingBoard = nil }
    func installPacket() {
        guard authorized, let pendingBoard else { return }
        do { try save(pendingBoard.board, media: pendingBoard.media); self.pendingBoard = nil; failure = nil }
        catch { saveFailure(error) }
    }
    private func saveFailure(_ error: any Error) {
        if case BoardLibraryError.refreshFailed = error { failure = library.notice ?? "Changes saved. Reopen the app to refresh." }
        else { failure = "The changes could not be saved. Your previous board is kept. Try again." }
    }
    private func save(_ board: Board, media: [AssetID: Data]) throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var files: [AssetID: URL] = [:]
        for (id, bytes) in media {
            let file = directory.appendingPathComponent(id.rawValue + ".jpg")
            try bytes.write(to: file, options: .atomic); files[id] = file
        }
        try library.save(board, importing: files, session: authorization)
    }
}
