import SwiftUI
import TalkboardCore

/// Home and People are saved boards; the two vocabulary pages remain transient.
struct AlphaPagesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let library: BoardLibrary
    let people: BoardLibrary
    let speech: AppleSpeechService
    let caregiver: CaregiverController
    var onEdit: (BoardLibrary) -> Void
    private var pages: [Board] {
        var home = library.board
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--changed-cup"), !home.concepts.isEmpty {
            home.concepts[0].label = "A different cup"
        }
        #endif
        return AlphaPages.make(home: home, people: people.board)
    }
    @State private var learning = false
    @State private var forward = true
    @State private var navigation = PageNavigation(count: AlphaPages.count)

    var body: some View {
        ZStack {
            if learning {
                LearningView(speech: speech)
            } else {
                let board = pages[navigation.index]
                let source = navigation.index == AlphaPages.count - 1 ? people : library
                BoardView(board: board, images: AlphaSymbolLibrary.images.merging(source.images) { _, saved in saved }) { id in
                    speech.speak(conceptID: id, in: board, recordingURL: source.recordingURL(for: id))
                }
                .id(board.id)
                .transition(reduceMotion ? .identity : .asymmetric(
                    insertion: .offset(x: forward ? 48 : -48).combined(with: .opacity),
                    removal: .offset(x: forward ? -48 : 48).combined(with: .opacity)))
            }
        }
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: navigation.index)
        .overlay(alignment: .top) {
            if !learning {
                CaregiverControls(controller: caregiver,
                                  editLabel: navigation.index == AlphaPages.count - 1 ? "Edit People" : "Edit home board",
                                  onEdit: { onEdit(navigation.index == AlphaPages.count - 1 ? people : library) })
                .overlay {
                    HStack(spacing: 14) {
                        ForEach(0..<navigation.count, id: \.self) { index in
                            Circle()
                                .fill(index == navigation.index ? navigationGreen : .clear)
                                .overlay { Circle().strokeBorder(navigationGreen, lineWidth: 3) }
                                .frame(width: 22, height: 22)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Page \(navigation.index + 1) of \(navigation.count)")
                    .accessibilityIdentifier("page-position")
                    .allowsHitTesting(false)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 16) {
                Button {
                    speech.controller.stop()
                    if learning { learning = false } else { forward = false; navigation.previous() }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 64, weight: .heavy))
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .disabled(!learning && !navigation.canGoBack)
                .opacity(learning || navigation.canGoBack ? 1 : 0.4)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("page-previous")
                Button { speech.controller.stop(); learning = false; forward = false; navigation.home() } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 52, weight: .bold))
                        .frame(width: 110, height: 72)
                }
                .accessibilityLabel("Home")
                .accessibilityIdentifier("page-home")
                Button { speech.controller.stop(); forward = true; navigation.next() } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 64, weight: .heavy))
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .disabled(learning || !navigation.canGoForward)
                .opacity(!learning && navigation.canGoForward ? 1 : 0.4)
                .accessibilityLabel("Next")
                .accessibilityIdentifier("page-next")
            }
            .font(.title2.bold())
            .buttonStyle(AlphaNavigationStyle())
            .overlay(alignment: .leading) {
                if !learning {
                    Button {
                        speech.controller.stop()
                        learning = true
                    } label: {
                        Text("ABC\n123")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(width: 96, height: 72)
                            .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(AlphaNavigationStyle())
                    .accessibilityLabel("Alphabet and numbers")
                    .accessibilityIdentifier("learning-open")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                SpeechNotice(issue: speech.controller.issue)
                if let notice = (navigation.index == AlphaPages.count - 1 ? people.notice : library.notice) { Text(notice).font(.caption) }
            }
            .padding(.top, 64)
            .allowsHitTesting(false)
        }
    }
}

private let navigationGreen = Color(red: 0.10, green: 0.43, blue: 0.22)

private struct AlphaNavigationStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(navigationGreen)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// Repeated controls retain the loaded board's identity, meaning, artwork and location.
@MainActor
enum AlphaPages {
    static let count = 4

    static func make(home: Board, people: Board = PeopleBoard.empty) -> [Board] {
        let essentials: Set<String> = ["yes", "go", "stop", "no", "help"]
        let words = [
            [("done", "Done"), ("eat", "Eat"), ("potty", "Potty"), ("outside", "Outside"), ("bye", "Bye bye")],
            [("school", "School"), ("book", "Book"), ("train", "Train"), ("ball", "Ball"), ("cat", "Cat")]
        ]
        let safetyCells = home.cells.filter { essentials.contains($0.conceptID.rawValue) }
        let occupied = Set(safetyCells.map(\.position))
        let slots = (0..<home.grid.rows).flatMap { row in
            (0..<home.grid.columns).map { Position(row: row, column: $0) }
        }.filter { !occupied.contains($0) }
        let existingIDs = Set(home.concepts.map { $0.id.rawValue })
        let vocabulary = words.enumerated().map { index, entries in
            let concepts = entries.filter { !existingIDs.contains($0.0) }.prefix(slots.count)
                .map { Concept(id: ConceptID(rawValue: $0.0), label: $0.1, spokenText: $0.1,
                               imageID: AlphaSymbolLibrary.asset(for: $0.0)?.id) }
            let safetyConcepts = home.concepts.filter { essentials.contains($0.id.rawValue) }
            let assetIDs = Set(safetyConcepts.flatMap { [$0.imageID, $0.recordingID].compactMap { $0 } })
            return Board(id: BoardID(rawValue: "alpha-page-\(index + 2)"), name: "Preview \(index + 2)", grid: home.grid,
                         concepts: safetyConcepts + concepts,
                         cells: safetyCells + zip(slots, concepts).map { Cell(position: $0.0, conceptID: $0.1.id) },
                         assets: home.assets.filter { assetIDs.contains($0.id) }
                            + AlphaSymbolLibrary.assets.filter { asset in concepts.contains { $0.imageID == asset.id } })
        }
        return [home] + vocabulary + [people]
    }
}
