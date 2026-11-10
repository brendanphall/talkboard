import Foundation

/// Explicitly separates keeping an image from removing or replacing it.
public enum BoardImageEdit: Hashable, Sendable {
    case keep
    case remove
    case replace(Asset)
}

public enum BoardEditError: Error, Hashable, Sendable {
    case unknownConcept(ConceptID)
    case occupiedPosition(Position)
    case emptyLabel
}

/// Pure draft operations (AAC-002/003/012). The caller owns authorization and
/// atomic publication; discarding the returned value leaves the live board unchanged.
public enum BoardEditor {
    public static func replaceConcept(
        in board: Board, id: ConceptID, label: String, spokenText: String,
        image: BoardImageEdit = .keep, knownBoards: Set<BoardID> = []
    ) throws -> Board {
        try validate(board, knownBoards: knownBoards)
        try validateLabel(label)
        guard let index = board.concepts.firstIndex(where: { $0.id == id }) else {
            throw BoardEditError.unknownConcept(id)
        }
        var edited = board
        edited.concepts[index].label = label
        edited.concepts[index].spokenText = spokenText
        switch image {
        case .keep: break
        case .remove: edited.concepts[index].imageID = nil
        case .replace(let asset):
            edited.assets.append(asset)
            edited.concepts[index].imageID = asset.id
        }
        try validate(edited, knownBoards: knownBoards)
        return edited
    }

    public static func addConcept(
        to board: Board, at position: Position, concept: Concept,
        image: Asset? = nil, knownBoards: Set<BoardID> = []
    ) throws -> Board {
        try validate(board, knownBoards: knownBoards)
        try validateLabel(concept.label)
        guard !board.cells.contains(where: { $0.position == position }) else {
            throw BoardEditError.occupiedPosition(position)
        }
        var edited = board
        var added = concept
        if let image {
            edited.assets.append(image)
            added.imageID = image.id
        }
        edited.concepts.append(added)
        edited.cells.append(Cell(position: position, conceptID: added.id))
        try validate(edited, knownBoards: knownBoards)
        return edited
    }

    private static func validate(_ board: Board, knownBoards: Set<BoardID>) throws {
        let issues = board.issues(knownBoards: knownBoards)
        guard issues.isEmpty else { throw BoardCodecError.invalid(issues) }
    }

    private static func validateLabel(_ label: String) throws {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BoardEditError.emptyLabel
        }
    }
}
