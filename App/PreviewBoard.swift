import TalkboardCore

/// Invented demonstration content only. Household content is installed on device later.
enum PreviewBoard {
    static func make() -> Board {
        let entries: [(String, String, Int, Int)] = [
            ("cup", "Cup", 0, 0), ("stop", "Stop", 0, 1), ("no", "No", 0, 3), ("open", "Open", 0, 4),
            ("park", "Park", 1, 0), ("go", "Go", 1, 2), ("more", "More", 1, 4),
            ("help", "Help", 2, 0), ("ball", "Ball", 2, 1), ("book", "Book", 2, 3),
        ]
        return Board(
            id: BoardID(rawValue: "preview"), name: "Preview", grid: GridSize(rows: 3, columns: 5),
            concepts: entries.map { Concept(id: ConceptID(rawValue: $0.0), label: $0.1, spokenText: $0.1) },
            cells: entries.map { Cell(position: Position(row: $0.2, column: $0.3), conceptID: ConceptID(rawValue: $0.0)) }
        )
    }
}
