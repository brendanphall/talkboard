import Foundation
import Testing
@testable import TalkboardCore

// Fixtures use invented placeholder content only. Personal boards never appear in tests.

private func fixtureData() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "board-v1", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private let cupID = ConceptID(rawValue: "concept-cup")
private let stopID = ConceptID(rawValue: "concept-stop")
private let photoID = AssetID(rawValue: "asset-cup-photo")
private let voiceID = AssetID(rawValue: "asset-park-voice")
private let parkBoard = BoardID(rawValue: "board-park")

/// A small valid board built in code: two tiles on a 2 x 3 grid with one photo.
private func sampleBoard() -> Board {
    Board(
        id: BoardID(rawValue: "board-sample"),
        name: "Sample",
        grid: GridSize(rows: 2, columns: 3),
        concepts: [
            Concept(id: cupID, label: "Cup", spokenText: "cup please", imageID: photoID),
            Concept(id: stopID, label: "Stop", spokenText: "stop"),
        ],
        cells: [
            Cell(position: Position(row: 0, column: 0), conceptID: stopID),
            Cell(position: Position(row: 1, column: 2), conceptID: cupID),
        ],
        assets: [
            Asset(id: photoID, kind: .image, filename: "cup.jpg",
                  provenance: Provenance(source: "placeholder photo", license: "CC0-1.0")),
        ]
    )
}

@Suite("Board format on disk")
struct BoardFormatTests {
    @Test("a saved version-1 board reads back with every field in place")
    func readsKnownGoodFile() throws {
        let board = try BoardCodec.decode(fixtureData(), knownBoards: [parkBoard])

        #expect(board.schemaVersion == 1)
        #expect(board.id == BoardID(rawValue: "board-home"))
        #expect(board.grid == GridSize(rows: 3, columns: 4))
        #expect(board.cells.map(\.position) == [
            Position(row: 0, column: 0), Position(row: 2, column: 3), Position(row: 1, column: 2),
        ])
        let cup = try #require(board.concepts.first { $0.id == cupID })
        #expect(cup.label == "Cup")
        #expect(cup.spokenText == "cup please")
        #expect(cup.imageID == photoID)
        let park = try #require(board.concepts.first { $0.id == ConceptID(rawValue: "concept-park") })
        #expect(park.recordingID == voiceID)
        #expect(park.destinationID == BoardID(rawValue: "board-park"))
        let voice = try #require(board.assets.first { $0.id == voiceID })
        #expect(voice.kind == .recording)
        #expect(voice.provenance.modifications == "trimmed")
        #expect(voice.provenance.author == nil)
    }

    @Test("a board survives saving and reading back unchanged")
    func roundTrip() throws {
        let board = sampleBoard()
        #expect(try BoardCodec.decode(BoardCodec.encode(board)) == board)
    }

    @Test("saving the same board twice gives identical bytes")
    func stableEncoding() throws {
        #expect(try BoardCodec.encode(sampleBoard()) == BoardCodec.encode(sampleBoard()))
    }

    @Test("a board from a newer app version is refused, not reset", arguments: [0, 2, 99])
    func refusesUnknownSchema(version: Int) throws {
        var json = try #require(String(data: fixtureData(), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": \(version)")
        #expect(throws: BoardCodecError.unsupportedSchemaVersion(version)) {
            try BoardCodec.decode(Data(json.utf8), knownBoards: [parkBoard])
        }
    }

    @Test("a damaged file is reported as unreadable")
    func malformedFile() {
        #expect(throws: BoardCodecError.unreadable) {
            try BoardCodec.decode(Data("{\"schemaVersion\": 1, \"cells\": [".utf8))
        }
    }

    @Test("an invalid board is refused when read, with the reasons")
    func invalidOnRead() throws {
        var json = try #require(String(data: fixtureData(), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"row\": 2, \"column\": 3", with: "\"row\": 0, \"column\": 0")
        #expect(throws: BoardCodecError.invalid([.duplicatePosition(Position(row: 0, column: 0))])) {
            try BoardCodec.decode(Data(json.utf8), knownBoards: [parkBoard])
        }
    }

    @Test("an invalid board is never written")
    func invalidNotWritten() {
        var board = sampleBoard()
        board.cells.append(Cell(position: Position(row: 0, column: 0), conceptID: cupID))
        #expect(throws: BoardCodecError.invalid([.duplicatePosition(Position(row: 0, column: 0))])) {
            try BoardCodec.encode(board)
        }
    }

    @Test("writing the saved fixture back gives exactly the version-1 file contract")
    func pinnedContract() throws {
        let original = try fixtureData()
        let rewritten = try BoardCodec.encode(BoardCodec.decode(original, knownBoards: [parkBoard]), knownBoards: [parkBoard])
        let expected = try JSONSerialization.jsonObject(with: original) as? NSDictionary
        let actual = try JSONSerialization.jsonObject(with: rewritten) as? NSDictionary
        #expect(actual == expected)
    }

    @Test("an explicit null reads the same as a missing field")
    func explicitNull() throws {
        var json = try #require(String(data: fixtureData(), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"spokenText\": \"stop\"", with: "\"spokenText\": \"stop\", \"imageID\": null")
        let board = try BoardCodec.decode(Data(json.utf8), knownBoards: [parkBoard])
        #expect(board.concepts.first { $0.id == stopID }?.imageID == nil)
    }

    @Test("a field this build does not know is refused, so saving cannot drop it", arguments: [
        ("\"name\": \"Home\"", "\"name\": \"Home\", \"voice\": \"x\"", "voice"),
        ("\"label\": \"Stop\"", "\"label\": \"Stop\", \"color\": \"red\"", "concepts[1].color"),
        ("\"name\": \"Home\"", "\"name\": \"Home\", \"grid.rows\": 999", "grid.rows"),
        ("\"name\": \"Home\"", "\"name\": \"Home\", \"concepts[].label\": \"lost\"", "concepts[].label"),
    ])
    func unknownField(find: String, replace: String, path: String) throws {
        var json = try #require(String(data: fixtureData(), encoding: .utf8))
        json = json.replacingOccurrences(of: find, with: replace)
        #expect(throws: BoardCodecError.unknownFields([path])) {
            try BoardCodec.decode(Data(json.utf8), knownBoards: [parkBoard])
        }
    }

    @Test("an explicit null on a field no other element has still reads as missing")
    func explicitNullAlone() throws {
        var json = try #require(String(data: fixtureData(), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"source\": \"placeholder recording\"", with: "\"source\": \"placeholder recording\", \"author\": null")
        let board = try BoardCodec.decode(Data(json.utf8), knownBoards: [parkBoard])
        #expect(board.assets.first { $0.id == voiceID }?.provenance.author == nil)
    }

    @Test("an unknown field holding null is ignored, since saving loses nothing")
    func unknownNull() throws {
        var json = try #require(String(data: fixtureData(), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"name\": \"Home\"", with: "\"name\": \"Home\", \"future\": null")
        #expect(try BoardCodec.decode(Data(json.utf8), knownBoards: [parkBoard]).name == "Home")
    }

    @Test("a newer format is refused from its version alone, before its fields are read")
    func refusesBareNewerHeader() {
        #expect(throws: BoardCodecError.unsupportedSchemaVersion(2)) {
            try BoardCodec.decode(Data("{\"schemaVersion\": 2}".utf8))
        }
    }

    @Test("a current-version file missing required fields is unreadable")
    func missingFields() {
        #expect(throws: BoardCodecError.unreadable) {
            try BoardCodec.decode(Data("{\"schemaVersion\": 1}".utf8))
        }
    }

    @Test("this build reads exactly the versions it knows")
    func supportedVersions() {
        #expect(BoardCodec.supportedSchemaVersions == [1])
    }

    @Test("a new board is written as the current schema version")
    func newBoardsUseCurrentSchema() {
        #expect(sampleBoard().schemaVersion == Board.currentSchemaVersion)
        #expect(Board.currentSchemaVersion == 1)
    }
}

@Suite("Board validation")
struct BoardValidationTests {
    @Test("the sample board and the saved fixture are valid")
    func validBoards() throws {
        #expect(sampleBoard().issues() == [])
        #expect(try BoardCodec.decode(fixtureData(), knownBoards: [parkBoard]).issues(knownBoards: [parkBoard]) == [])
    }

    @Test("two tiles in one cell are rejected")
    func duplicatePosition() {
        var board = sampleBoard()
        board.cells.append(Cell(position: Position(row: 1, column: 2), conceptID: stopID))
        #expect(board.issues() == [.duplicatePosition(Position(row: 1, column: 2))])
    }

    @Test("a cell on the last row and column is inside a 2 x 3 grid")
    func lastCellInside() {
        var board = sampleBoard()
        board.cells[1] = Cell(position: Position(row: 1, column: 2), conceptID: cupID)
        #expect(board.issues() == [])
    }

    @Test("a cell one past the grid edge is rejected", arguments: [
        Position(row: 2, column: 0), Position(row: 0, column: 3), Position(row: -1, column: 0), Position(row: 0, column: -1),
    ])
    func outsideGrid(position: Position) {
        var board = sampleBoard()
        board.cells[1] = Cell(position: position, conceptID: cupID)
        #expect(board.issues() == [.positionOutsideGrid(position)])
    }

    @Test("a grid needs at least one row and one column", arguments: [GridSize(rows: 0, columns: 3), GridSize(rows: 2, columns: 0), GridSize(rows: -1, columns: 3), GridSize(rows: 2, columns: -4)])
    func emptyGrid(grid: GridSize) {
        var board = sampleBoard()
        board.grid = grid
        board.cells = []
        #expect(board.issues() == [.emptyGrid])
    }

    @Test("a cell pointing at a missing tile is rejected")
    func unknownConcept() {
        var board = sampleBoard()
        let ghost = ConceptID(rawValue: "concept-ghost")
        board.cells.append(Cell(position: Position(row: 0, column: 1), conceptID: ghost))
        #expect(board.issues() == [.unknownConcept(ghost)])
    }

    @Test("two tiles with the same identity are rejected")
    func duplicateConcept() {
        var board = sampleBoard()
        board.concepts.append(Concept(id: stopID, label: "Halt", spokenText: "halt"))
        #expect(board.issues() == [.duplicateConceptID(stopID)])
    }

    @Test("a tile pointing at a missing photo is rejected")
    func unknownImage() {
        var board = sampleBoard()
        board.assets = []
        #expect(board.issues() == [.unknownAsset(photoID)])
    }

    @Test("a tile pointing at a missing recording is rejected")
    func unknownRecording() {
        var board = sampleBoard()
        board.concepts[1].recordingID = voiceID
        #expect(board.issues() == [.unknownAsset(voiceID)])
    }

    @Test("a recording used as a photo is rejected")
    func recordingAsImage() {
        var board = sampleBoard()
        board.assets[0].kind = .recording
        #expect(board.issues() == [.wrongAssetKind(photoID, expected: .image)])
    }

    @Test("a photo used as a recording is rejected")
    func imageAsRecording() {
        var board = sampleBoard()
        board.concepts[1].recordingID = photoID
        #expect(board.issues() == [.wrongAssetKind(photoID, expected: .recording)])
    }

    @Test("a tile with nothing to say and nowhere to go is rejected", arguments: ["", "   ", "\n"])
    func silentTile(spoken: String) {
        var board = sampleBoard()
        board.concepts[1].spokenText = spoken
        #expect(board.issues() == [.silentConcept(stopID)])
    }

    @Test("a tile that only plays a recording is valid")
    func recordingOnly() {
        var board = sampleBoard()
        board.assets.append(Asset(id: voiceID, kind: .recording, filename: "v.m4a",
                                  provenance: Provenance(source: "placeholder", license: "CC0-1.0")))
        board.concepts[1].spokenText = ""
        board.concepts[1].recordingID = voiceID
        #expect(board.issues() == [])
    }

    @Test("a tile that only opens another page is valid")
    func navigationOnly() {
        var board = sampleBoard()
        board.concepts[1].spokenText = ""
        board.concepts[1].destinationID = parkBoard
        #expect(board.issues(knownBoards: [parkBoard]) == [])
    }

    @Test("a tile that opens a page that does not exist is rejected")
    func danglingDestination() {
        var board = sampleBoard()
        board.concepts[1].destinationID = parkBoard
        #expect(board.issues() == [.unknownDestination(parkBoard)])
    }

    @Test("a tile may open its own board")
    func selfDestination() {
        var board = sampleBoard()
        board.concepts[1].destinationID = board.id
        #expect(board.issues() == [])
    }

    @Test("problems in different cells and tiles are all reported")
    func reportsAll() {
        var board = sampleBoard()
        board.assets = []
        board.cells.append(Cell(position: Position(row: 5, column: 5), conceptID: stopID))
        #expect(board.issues() == [.positionOutsideGrid(Position(row: 5, column: 5)), .unknownAsset(photoID)])
    }

    @Test("the label shown and the words spoken are kept separately")
    func labelAndSpeechSeparate() throws {
        let board = try BoardCodec.decode(BoardCodec.encode(sampleBoard()))
        let cup = try #require(board.concepts.first { $0.id == cupID })
        #expect(cup.label == "Cup")
        #expect(cup.spokenText == "cup please")
    }

    @Test("two media files with the same identity are rejected")
    func duplicateAsset() {
        var board = sampleBoard()
        board.assets.append(Asset(id: photoID, kind: .recording, filename: "other.m4a",
                                  provenance: Provenance(source: "placeholder", license: "CC0-1.0")))
        #expect(board.issues() == [.duplicateAssetID(photoID)])
    }

    @Test("a media file name must stay inside the media folder", arguments: ["", "../board.json", "a/b.jpg", "a\\b.jpg", ".", "..", ".hidden.jpg", "cup\u{0}.jpg"])
    func unsafeFilename(name: String) {
        var board = sampleBoard()
        board.assets[0].filename = name
        #expect(board.issues() == [.unsafeFilename(photoID)])
    }

    @Test("two media files may not share a file name, ignoring case")
    func sharedFilename() {
        var board = sampleBoard()
        board.assets.append(Asset(id: voiceID, kind: .recording, filename: "CUP.jpg",
                                  provenance: Provenance(source: "placeholder", license: "CC0-1.0")))
        #expect(board.issues() == [.duplicateFilename("CUP.jpg")])
    }

    @Test("a media file must say where it came from and under what license", arguments: [
        Provenance(source: "", license: "CC0-1.0"), Provenance(source: "photo", license: "  "),
    ])
    func incompleteProvenance(provenance: Provenance) {
        var board = sampleBoard()
        board.assets[0].provenance = provenance
        #expect(board.issues() == [.incompleteProvenance(photoID)])
    }

    @Test("a grid with no rows or columns contains no cells")
    func emptyGridContainsNothing() {
        #expect(!GridSize(rows: -1, columns: 3).contains(Position(row: 0, column: 0)))
        #expect(!GridSize(rows: 3, columns: 0).contains(Position(row: 0, column: 0)))
        #expect(GridSize(rows: 1, columns: 1).contains(Position(row: 0, column: 0)))
    }

    @Test("new identities are unique")
    func freshIDs() {
        #expect(ConceptID() != ConceptID())
    }

    @Test("an identity prints as its stored value")
    func identityText() {
        #expect(String(describing: ConceptID(rawValue: "concept-cup")) == "concept-cup")
    }
}
