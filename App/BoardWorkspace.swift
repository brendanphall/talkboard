import SwiftUI
import TalkboardCore

private struct EditorPresentation: Identifiable { let id: UUID }

struct BoardWorkspace: View {
    let library: BoardLibrary
    let caregiver: CaregiverController
    let speech: AppleSpeechService
    @State private var editor: EditorPresentation?

    var body: some View {
        BoardView(board: displayBoard, images: library.images) { id in
            speech.speak(conceptID: id, in: library.board, recordingURL: library.recordingURL(for: id))
        }
        .overlay(alignment: .top) {
            CaregiverControls(controller: caregiver) {
                guard library.canEdit, let session = caregiver.sessionID else { return }
                editor = EditorPresentation(id: session)
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
                SpeechNotice(issue: speech.controller.issue)
                if let notice = library.notice {
                    Text(notice).font(.caption).padding(.horizontal, 20)
                        .accessibilityIdentifier("board-notice")
                }
            }
            .padding(.top, 28)
            .allowsHitTesting(false)
        }
        .sheet(item: $editor) { presentation in
            BoardEditorView(library: library, session: presentation.id, speak: { speech.controller.speak($0) })
        }
        .onChange(of: caregiver.sessionID) { _, session in
            if session != editor?.id { editor = nil }
        }
    }

    private var displayBoard: Board {
        var board = library.board
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--changed-cup"), !board.concepts.isEmpty {
            board.concepts[0].label = "A different cup"
        }
        #endif
        return board
    }
}
