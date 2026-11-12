import TalkboardCore

/// Family photos and names are saved device data, never bundled sample content.
enum PeopleBoard {
    static var empty: Board {
        Board(id: BoardID(rawValue: "people"), name: "People", grid: GridSize(rows: 3, columns: 5))
    }

    #if DEBUG
    static var testFixture: Board {
        var board = empty
        for (index, word) in ["one", "two", "three"].enumerated() {
            let concept = Concept(id: ConceptID(rawValue: "person-\(word)"), label: "Person \(word)", spokenText: "Person \(word)")
            board.concepts.append(concept)
            board.cells.append(Cell(position: Position(row: 1, column: index + 1), conceptID: concept.id))
        }
        return board
    }
    #endif
}
