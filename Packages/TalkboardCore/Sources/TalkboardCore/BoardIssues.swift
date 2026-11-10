import Foundation

/// Something that makes a board unsafe to show or save.
public enum BoardIssue: Hashable, Sendable {
    case emptyGrid
    case duplicatePosition(Position)
    case positionOutsideGrid(Position)
    case unknownConcept(ConceptID)
    case duplicateConceptID(ConceptID)
    case duplicateAssetID(AssetID)
    /// The file name is empty, hidden, or reaches outside the board's media folder.
    case unsafeFilename(AssetID)
    case duplicateFilename(String)
    /// Source and license are required for every media file (AAC-012).
    case incompleteProvenance(AssetID)
    case unknownAsset(AssetID)
    case wrongAssetKind(AssetID, expected: Asset.Kind)
    case unknownDestination(BoardID)
    /// A tile with no words, no recording and no destination would do nothing when tapped.
    case silentConcept(ConceptID)
}

extension Board {
    /// The problems with this board, in a stable order: grid, cells, media, then tiles.
    /// Each cell reports its first problem; each media file and tile reports all of its own.
    /// An empty grid is reported alone. Empty means the board is valid.
    ///
    /// - Parameter knownBoards: boards a tile may open. This board is always included.
    ///   Navigation is checked against the whole board set, which a single board cannot see.
    public func issues(knownBoards: Set<BoardID> = []) -> [BoardIssue] {
        guard grid.rows > 0, grid.columns > 0 else { return [.emptyGrid] }
        return cellIssues() + assetIssues() + conceptIssues(knownBoards: knownBoards.union([id]))
    }

    private func cellIssues() -> [BoardIssue] {
        let known = Set(concepts.map(\.id))
        var seen = Set<Position>()
        return cells.compactMap { cell in
            if !grid.contains(cell.position) { return .positionOutsideGrid(cell.position) }
            if !seen.insert(cell.position).inserted { return .duplicatePosition(cell.position) }
            if !known.contains(cell.conceptID) { return .unknownConcept(cell.conceptID) }
            return nil
        }
    }

    private func assetIssues() -> [BoardIssue] {
        var ids = Set<AssetID>()
        var names = Set<String>()
        return assets.flatMap { asset -> [BoardIssue] in
            var found: [BoardIssue] = []
            if !ids.insert(asset.id).inserted { found.append(.duplicateAssetID(asset.id)) }
            if !asset.hasSafeFilename {
                found.append(.unsafeFilename(asset.id))
            } else if !names.insert(asset.filename.lowercased()).inserted {
                found.append(.duplicateFilename(asset.filename))
            }
            if !asset.provenance.isComplete { found.append(.incompleteProvenance(asset.id)) }
            return found
        }
    }

    private func conceptIssues(knownBoards: Set<BoardID>) -> [BoardIssue] {
        let assetsByID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<ConceptID>()
        return concepts.flatMap { concept -> [BoardIssue] in
            guard seen.insert(concept.id).inserted else { return [.duplicateConceptID(concept.id)] }
            return [
                mediaIssue(concept.imageID, expected: .image, in: assetsByID),
                mediaIssue(concept.recordingID, expected: .recording, in: assetsByID),
                concept.destinationID.flatMap { knownBoards.contains($0) ? nil : .unknownDestination($0) },
                concept.doesNothing ? .silentConcept(concept.id) : nil,
            ].compactMap { $0 }
        }
    }

    private func mediaIssue(_ id: AssetID?, expected: Asset.Kind, in assetsByID: [AssetID: Asset]) -> BoardIssue? {
        guard let id else { return nil }
        guard let asset = assetsByID[id] else { return .unknownAsset(id) }
        return asset.kind == expected ? nil : .wrongAssetKind(id, expected: expected)
    }
}

extension Concept {
    var doesNothing: Bool {
        spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && recordingID == nil
            && destinationID == nil
    }
}

extension Asset {
    /// A plain file name: not empty, not hidden, no path separators, no NUL.
    var hasSafeFilename: Bool {
        !filename.isEmpty && !filename.hasPrefix(".") && !filename.contains { "/\\\u{0}".contains($0) }
    }
}

extension Provenance {
    var isComplete: Bool {
        [source, license].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
