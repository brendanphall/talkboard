import SwiftUI
import TalkboardCore

/// Every stored coordinate has a view, including empty cells (AAC-002).
struct BoardView: View {
    let board: Board
    var images: [AssetID: UIImage] = [:]
    var onSelect: (ConceptID) -> Void
    @State private var selection = BoardSelection()

    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 12
            let band: CGFloat = 56
            let width = max(0, (geometry.size.width - gap * CGFloat(board.grid.columns - 1)) / CGFloat(board.grid.columns))
            let height = max(0, (geometry.size.height - band - gap * CGFloat(board.grid.rows)) / CGFloat(board.grid.rows))
            VStack(spacing: gap) {
                Color.clear
                    .frame(height: band)
                    .accessibilityElement()
                    .accessibilityIdentifier("message-band")
                VStack(spacing: gap) {
                    ForEach(0..<board.grid.rows, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<board.grid.columns, id: \.self) { column in
                                cell(at: Position(row: row, column: column))
                                    .frame(width: width, height: height)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: selection.token) {
            let token = selection.token
            do { try await Task.sleep(for: .milliseconds(600)) }
            catch { return }
            selection.clear(matching: token)
        }
    }

    @ViewBuilder
    private func cell(at position: Position) -> some View {
        if let cell = board.cells.first(where: { $0.position == position }),
           let concept = board.concepts.first(where: { $0.id == cell.conceptID }) {
            TileView(concept: concept, image: concept.imageID.flatMap { images[$0] }, selected: selection.selectedID == concept.id) {
                selection.activate(concept.id, onSelect: onSelect)
            }
        } else {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(uiColor: .separator), style: StrokeStyle(lineWidth: 1, dash: [5]))
                .accessibilityElement()
                .accessibilityLabel("Empty cell")
                .accessibilityIdentifier("empty-\(position.row)-\(position.column)")
        }
    }
}
