import Foundation

// The board model keeps six things apart, as the spec's data-model paragraph asks:
// concept identity, board position, image, spoken output, recording, and navigation.
// A tile's place on the grid lives only in `Cell`, so editing what a tile says or shows
// can never move it (AAC-002). Engineering safeguard, not a clinical finding.

/// A stable identity that survives edits, saves and restores.
public struct Identifier<Tag>: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// A new, unique identity.
    public init() { self.rawValue = UUID().uuidString }
    public var description: String { rawValue }
}

public enum ConceptTag {}
public enum AssetTag {}
public enum BoardTag {}
public typealias ConceptID = Identifier<ConceptTag>
public typealias AssetID = Identifier<AssetTag>
public typealias BoardID = Identifier<BoardTag>

/// A cell on the grid, counted from zero at the top left.
public struct Position: Hashable, Codable, Sendable, CustomStringConvertible {
    public var row: Int
    public var column: Int
    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
    public var description: String { "(\(row), \(column))" }
}

public struct GridSize: Hashable, Codable, Sendable {
    public var rows: Int
    public var columns: Int
    public init(rows: Int, columns: Int) {
        self.rows = rows
        self.columns = columns
    }

    /// False for every position when the grid has no rows or columns.
    public func contains(_ position: Position) -> Bool {
        position.row >= 0 && position.row < rows && position.column >= 0 && position.column < columns
    }
}

/// What a tile means: what it shows, what it says, and where it leads.
/// The label shown and the words spoken are separate on purpose (spec, "Do not enforce a
/// sentence template"): a tile labelled "Park" may speak "let's go to the park".
public struct Concept: Identifiable, Hashable, Codable, Sendable {
    public let id: ConceptID
    public var label: String
    public var spokenText: String
    public var imageID: AssetID?
    public var recordingID: AssetID?
    public var destinationID: BoardID?

    public init(
        id: ConceptID = ConceptID(),
        label: String,
        spokenText: String,
        imageID: AssetID? = nil,
        recordingID: AssetID? = nil,
        destinationID: BoardID? = nil
    ) {
        self.id = id
        self.label = label
        self.spokenText = spokenText
        self.imageID = imageID
        self.recordingID = recordingID
        self.destinationID = destinationID
    }
}

/// The only place a tile's position is stored.
public struct Cell: Hashable, Codable, Sendable {
    public var position: Position
    public var conceptID: ConceptID
    public init(position: Position, conceptID: ConceptID) {
        self.position = position
        self.conceptID = conceptID
    }
}

/// Where a reused image or recording came from (AAC-012).
public struct Provenance: Hashable, Codable, Sendable {
    public var source: String
    public var author: String?
    public var license: String
    public var modifications: String?

    public init(source: String, author: String? = nil, license: String, modifications: String? = nil) {
        self.source = source
        self.author = author
        self.license = license
        self.modifications = modifications
    }
}

public struct Asset: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Hashable, Codable, Sendable {
        case image
        case recording
    }

    public let id: AssetID
    public var kind: Kind
    /// File name inside the board's media folder.
    public var filename: String
    public var provenance: Provenance

    public init(id: AssetID = AssetID(), kind: Kind, filename: String, provenance: Provenance) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.provenance = provenance
    }
}

public struct Board: Identifiable, Hashable, Codable, Sendable {
    /// The on-disk format version this build writes and reads.
    public static let currentSchemaVersion = 1

    public private(set) var schemaVersion: Int
    public let id: BoardID
    public var name: String
    public var grid: GridSize
    public var concepts: [Concept]
    public var cells: [Cell]
    public var assets: [Asset]

    public init(
        id: BoardID = BoardID(),
        name: String,
        grid: GridSize,
        concepts: [Concept] = [],
        cells: [Cell] = [],
        assets: [Asset] = []
    ) {
        self.schemaVersion = Board.currentSchemaVersion
        self.id = id
        self.name = name
        self.grid = grid
        self.concepts = concepts
        self.cells = cells
        self.assets = assets
    }
}
