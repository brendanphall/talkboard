import SwiftUI
import TalkboardCore

private struct EditorPresentation: Identifiable { let id: UUID; let library: BoardLibrary }

struct BoardWorkspace: View {
    let library: BoardLibrary
    let people: BoardLibrary
    let caregiver: CaregiverController
    let speech: AppleSpeechService
    @State private var editor: EditorPresentation?

    var body: some View {
        AlphaPagesView(library: library, people: people, speech: speech, caregiver: caregiver) { selectedLibrary in
            guard selectedLibrary.canEdit, let session = caregiver.sessionID else { return }
            editor = EditorPresentation(id: session, library: selectedLibrary)
        }
        .sheet(item: $editor) { presentation in
            BoardEditorView(library: presentation.library, session: presentation.id, speak: { speech.controller.speak($0) })
        }
        .onChange(of: caregiver.sessionID) { _, session in
            if session != editor?.id { editor = nil }
        }
    }
}
