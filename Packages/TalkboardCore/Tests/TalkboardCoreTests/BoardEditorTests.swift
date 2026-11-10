import Testing
@testable import TalkboardCore

@Suite("Stable board editing")
struct BoardEditorTests {
    private let firstID = ConceptID(rawValue: "first")
    private let secondID = ConceptID(rawValue: "second")
    private let imageID = AssetID(rawValue: "original-image")
    private let recordingID = AssetID(rawValue: "original-recording")

    @Test("editing text preserves concept identity, every cell, other concepts and media")
    func editText() throws {
        let original = fixture()
        let edited = try BoardEditor.replaceConcept(in: original, id: firstID, label: "New label", spokenText: "  different saved words  ")
        #expect(edited.id == original.id)
        #expect(edited.name == original.name)
        #expect(edited.grid == original.grid)
        #expect(edited.schemaVersion == original.schemaVersion)
        #expect(edited.cells == original.cells)
        #expect(edited.assets == original.assets)
        #expect(edited.concepts[0].id == firstID)
        #expect(edited.concepts[0].label == "New label")
        #expect(edited.concepts[0].spokenText == "  different saved words  ")
        #expect(edited.concepts[0].imageID == imageID)
        #expect(edited.concepts[0].recordingID == recordingID)
        #expect(edited.concepts[0].destinationID == original.id)
        #expect(edited.concepts[1] == original.concepts[1])
        #expect(original == fixture())
    }

    @Test("replacement can target a later concept without changing the first")
    func editSecondConcept() throws {
        let original = fixture()
        let edited = try BoardEditor.replaceConcept(in: original, id: secondID, label: "Second edited", spokenText: "Second words")
        #expect(edited.concepts[0] == original.concepts[0])
        #expect(edited.concepts[1].id == secondID)
        #expect(edited.concepts[1].label == "Second edited")
        #expect(edited.concepts[1].spokenText == "Second words")
        #expect(edited.cells == original.cells)
    }

    @Test("replacing an image adds new provenance without deleting a shared old asset")
    func replaceImage() throws {
        let original = fixture()
        let replacement = image("replacement")
        let edited = try BoardEditor.replaceConcept(in: original, id: firstID, label: "First", spokenText: "First words", image: .replace(replacement))
        #expect(edited.concepts[0].imageID == replacement.id)
        #expect(edited.concepts[1].imageID == imageID)
        #expect(edited.assets == original.assets + [replacement])
        #expect(edited.cells == original.cells)
        #expect(edited.issues().isEmpty)
        #expect(original == fixture())
    }

    @Test("removing an image clears only its reference and retains shared media")
    func removeImage() throws {
        let original = fixture()
        let edited = try BoardEditor.replaceConcept(in: original, id: firstID, label: "First", spokenText: "First words", image: .remove)
        #expect(edited.concepts[0].imageID == nil)
        #expect(edited.concepts[1].imageID == imageID)
        #expect(edited.assets == original.assets)
        #expect(edited.concepts[0].recordingID == recordingID)
        #expect(edited.concepts[0].destinationID == original.id)
    }

    @Test("adding to an empty coordinate appends only the new concept and cell")
    func addWithoutImage() throws {
        let original = fixture()
        let concept = Concept(id: .init(rawValue: "added"), label: "New label", spokenText: "New words", imageID: imageID)
        let position = Position(row: 2, column: 4)
        let edited = try BoardEditor.addConcept(to: original, at: position, concept: concept)
        #expect(edited.concepts == original.concepts + [concept])
        #expect(edited.cells == original.cells + [Cell(position: position, conceptID: concept.id)])
        #expect(edited.assets == original.assets)
        #expect(original == fixture())
    }

    @Test("adding an imported image binds it to the new card and retains its provenance")
    func addWithImage() throws {
        let original = fixture()
        let added = Concept(id: .init(rawValue: "added"), label: "New label", spokenText: "New words")
        let media = image("new-photo")
        let edited = try BoardEditor.addConcept(to: original, at: Position(row: 0, column: 1), concept: added, image: media)
        #expect(edited.concepts.last?.imageID == media.id)
        #expect(edited.assets == original.assets + [media])
        #expect(edited.concepts.dropLast() == original.concepts[...])
        #expect(edited.cells.dropLast() == original.cells[...])
        #expect(edited.issues().isEmpty)
    }

    @Test("an occupied coordinate is refused without replacing its existing card")
    func occupiedPosition() {
        let original = fixture()
        let occupied = Position(row: 0, column: 0)
        #expect(throws: BoardEditError.occupiedPosition(occupied)) {
            try BoardEditor.addConcept(to: original, at: occupied, concept: Concept(label: "New", spokenText: "New"))
        }
        #expect(original == fixture())
    }

    @Test("unknown concept identity is refused instead of editing another card")
    func unknownConcept() {
        let missing = ConceptID(rawValue: "missing")
        #expect(throws: BoardEditError.unknownConcept(missing)) {
            try BoardEditor.replaceConcept(in: fixture(), id: missing, label: "New", spokenText: "New")
        }
    }

    @Test("blank labels are refused for both replacement and addition", arguments: ["", " \n\t "])
    func blankLabel(label: String) {
        #expect(throws: BoardEditError.emptyLabel) {
            try BoardEditor.replaceConcept(in: fixture(), id: firstID, label: label, spokenText: "Words")
        }
        #expect(throws: BoardEditError.emptyLabel) {
            try BoardEditor.addConcept(to: fixture(), at: Position(row: 0, column: 1), concept: Concept(label: label, spokenText: "Words"))
        }
    }

    @Test("labels and spoken text are retained exactly without normalization")
    func exactText() throws {
        let edited = try BoardEditor.replaceConcept(in: fixture(), id: firstID, label: "  New label  ", spokenText: "\nWords\t")
        #expect(edited.concepts[0].label == "  New label  ")
        #expect(edited.concepts[0].spokenText == "\nWords\t")
    }

    @Test("silent cards cannot be introduced by either operation")
    func silentConcept() {
        #expect(throws: BoardCodecError.invalid([.silentConcept(secondID)])) {
            try BoardEditor.replaceConcept(in: fixture(), id: secondID, label: "Second", spokenText: " \n")
        }
        let added = Concept(id: .init(rawValue: "new"), label: "New", spokenText: "")
        #expect(throws: BoardCodecError.invalid([.silentConcept(added.id)])) {
            try BoardEditor.addConcept(to: fixture(), at: Position(row: 0, column: 1), concept: added)
        }
    }

    @Test("recorded or navigational meaning is retained when editing blank spoken text")
    func retainedNonTextMeaning() throws {
        let original = fixture()
        let edited = try BoardEditor.replaceConcept(in: original, id: firstID, label: "Recorded", spokenText: "")
        #expect(edited.concepts[0].recordingID == recordingID)
        #expect(edited.concepts[0].destinationID == original.id)
        #expect(edited.issues().isEmpty)
    }

    @Test("out-of-grid additions are refused", arguments: [Position(row: -1, column: 0), Position(row: 3, column: 0), Position(row: 0, column: 5)])
    func outsideGrid(position: Position) {
        #expect(throws: BoardCodecError.invalid([.positionOutsideGrid(position)])) {
            try BoardEditor.addConcept(to: fixture(), at: position, concept: Concept(label: "New", spokenText: "New"))
        }
    }

    @Test("duplicate concept IDs cannot be introduced")
    func duplicateConcept() {
        let added = Concept(id: firstID, label: "Duplicate", spokenText: "New")
        #expect(throws: BoardCodecError.invalid([.duplicateConceptID(firstID)])) {
            try BoardEditor.addConcept(to: fixture(), at: Position(row: 0, column: 1), concept: added)
        }
    }

    @Test("new media cannot overwrite the identity or filename of a shared old asset")
    func duplicateMedia() {
        var replacement = image("replacement")
        replacement.filename = "original-image.png"
        #expect(throws: BoardCodecError.invalid([.duplicateFilename("original-image.png")])) {
            try BoardEditor.replaceConcept(in: fixture(), id: firstID, label: "First", spokenText: "Words", image: .replace(replacement))
        }
        let duplicate = Asset(id: imageID, kind: .image, filename: "different.png", provenance: replacement.provenance)
        #expect(throws: BoardCodecError.invalid([.duplicateAssetID(imageID)])) {
            try BoardEditor.replaceConcept(in: fixture(), id: firstID, label: "First", spokenText: "Words", image: .replace(duplicate))
        }
    }

    @Test("wrong image kind and missing attribution are refused")
    func invalidMedia() {
        var wrongKind = image("new")
        wrongKind.kind = .recording
        #expect(throws: BoardCodecError.invalid([.wrongAssetKind(wrongKind.id, expected: .image)])) {
            try BoardEditor.replaceConcept(in: fixture(), id: firstID, label: "First", spokenText: "Words", image: .replace(wrongKind))
        }
        var missingLicense = image("new")
        missingLicense.provenance.license = ""
        #expect(throws: BoardCodecError.invalid([.incompleteProvenance(missingLicense.id)])) {
            try BoardEditor.addConcept(to: fixture(), at: Position(row: 0, column: 1), concept: Concept(label: "New", spokenText: "Words"), image: missingLicense)
        }
    }

    @Test("invalid input boards cannot be silently repaired or extended")
    func invalidInput() {
        var board = fixture()
        board.cells.append(board.cells[0])
        let error = BoardCodecError.invalid([.duplicatePosition(Position(row: 0, column: 0))])
        #expect(throws: error) { try BoardEditor.replaceConcept(in: board, id: firstID, label: "New", spokenText: "New") }
        #expect(throws: error) { try BoardEditor.addConcept(to: board, at: Position(row: 0, column: 1), concept: Concept(label: "New", spokenText: "New")) }
    }

    @Test("editing cannot disguise an already-invalid silent concept as a valid save")
    func cannotRepairInvalidInputByEditing() {
        var board = fixture()
        board.concepts[1].spokenText = ""
        #expect(throws: BoardCodecError.invalid([.silentConcept(secondID)])) {
            try BoardEditor.replaceConcept(in: board, id: secondID, label: "Second", spokenText: "Repaired")
        }
    }

    @Test("adding a missing concept cannot silently repair an invalid dangling cell")
    func cannotRepairInvalidInputByAdding() {
        var board = fixture()
        let missing = ConceptID(rawValue: "missing")
        board.cells.append(Cell(position: Position(row: 1, column: 1), conceptID: missing))
        #expect(throws: BoardCodecError.invalid([.unknownConcept(missing)])) {
            try BoardEditor.addConcept(to: board, at: Position(row: 0, column: 1), concept: Concept(id: missing, label: "Missing", spokenText: "Missing"))
        }
    }

    @Test("known destination IDs are respected for input and output validation")
    func externalDestination() throws {
        let destination = BoardID(rawValue: "other-board")
        var board = fixture()
        board.concepts[0].destinationID = destination
        let edited = try BoardEditor.replaceConcept(in: board, id: firstID, label: "New", spokenText: "Words", knownBoards: [destination])
        #expect(edited.concepts[0].destinationID == destination)
        let added = Concept(label: "Other", spokenText: "Other", destinationID: destination)
        let extended = try BoardEditor.addConcept(to: board, at: Position(row: 0, column: 1), concept: added, knownBoards: [destination])
        #expect(extended.concepts.last?.destinationID == destination)
        #expect(throws: BoardCodecError.invalid([.unknownDestination(destination)])) {
            try BoardEditor.replaceConcept(in: board, id: firstID, label: "New", spokenText: "Words")
        }
    }

    private func image(_ name: String) -> Asset {
        Asset(id: .init(rawValue: name), kind: .image, filename: name + ".png", provenance: .init(source: "Fixture", author: "Test author", license: "CC0", modifications: "None"))
    }

    private func fixture() -> Board {
        let boardID = BoardID(rawValue: "board")
        return Board(id: boardID, name: "Fixture", grid: GridSize(rows: 3, columns: 5), concepts: [
            Concept(id: firstID, label: "First", spokenText: "First words", imageID: imageID, recordingID: recordingID, destinationID: boardID),
            Concept(id: secondID, label: "Second", spokenText: "Second words", imageID: imageID),
        ], cells: [
            Cell(position: Position(row: 0, column: 0), conceptID: firstID),
            Cell(position: Position(row: 2, column: 3), conceptID: secondID),
        ], assets: [image("original-image"), Asset(id: recordingID, kind: .recording, filename: "original.m4a", provenance: .init(source: "Fixture", license: "CC0"))])
    }
}
