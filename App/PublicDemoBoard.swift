import TalkboardCore

/// Generic vocabulary and licensed artwork only; never a copied personal board.
@MainActor
enum PublicDemoBoard {
    static func make() -> Board {
        let entries: [(String, String, Int, Int)] = [
            ("dog", "Dog", 0, 0), ("stop", "Stop", 0, 1), ("no", "No", 0, 3), ("food", "Food", 0, 4),
            ("hungry", "Hungry", 1, 0), ("go", "Go", 1, 1), ("night-night", "Night-night", 1, 2), ("yes", "Yes", 1, 3),
            ("help", "Help", 2, 0), ("bath", "Bath", 2, 1), ("water", "Water", 2, 3)
        ]
        let concepts = entries.map {
            Concept(id: ConceptID(rawValue: $0.0), label: $0.1, spokenText: $0.1,
                    imageID: AlphaSymbolLibrary.asset(for: $0.0)?.id)
        }
        let imageIDs = Set(concepts.compactMap(\.imageID))
        return Board(id: BoardID(rawValue: "public-home"), name: "Home", grid: GridSize(rows: 3, columns: 5),
                     concepts: concepts,
                     cells: entries.map { Cell(position: Position(row: $0.2, column: $0.3), conceptID: ConceptID(rawValue: $0.0)) },
                     assets: AlphaSymbolLibrary.assets.filter { imageIDs.contains($0.id) })
    }
}
