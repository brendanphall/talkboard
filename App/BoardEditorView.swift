import PhotosUI
import SwiftUI
import TalkboardCore
import UniformTypeIdentifiers

struct BoardEditorView: View {
    let speak: (Concept) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editor: BoardEditingSession
    @State private var photoItem: PhotosPickerItem?
    @State private var importing = false
    @State private var confirmingReplacement = false

    init(library: BoardLibrary, session: UUID, speak: @escaping (Concept) -> Void) {
        _editor = State(initialValue: BoardEditingSession(library: library, authorization: session))
        self.speak = speak
    }
    var body: some View {
        NavigationStack {
            Form {
                if let failure = editor.failure { Text(failure).foregroundStyle(.red).accessibilityIdentifier("editor-error") }
                if let draft = editor.draft { draftForm(draft) }
                else {
                    Section("Choose a tile to edit") {
                        ForEach(0..<editor.library.board.grid.rows, id: \.self) { row in
                            ForEach(0..<editor.library.board.grid.columns, id: \.self) { column in
                                positionButton(Position(row: row, column: column))
                            }
                        }
                    }
                    Section {
                        Button("Load chosen pictures from Files") { importing = true }
                            .accessibilityIdentifier("import-pictures")
                    } footer: { Text("Choose the prepared picture-choices JSON file. You will confirm before replacing this board.") }
                }
            }
            .navigationTitle(editor.draft == nil ? "Edit board" : "Edit tile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editor.draft == nil ? "Back to board" : "Cancel") {
                        if editor.draft == nil { dismiss() } else { editor.cancelDraft(); photoItem = nil }
                    }.accessibilityIdentifier("editor-cancel")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                editor.loadPacket(result)
                confirmingReplacement = editor.pendingBoard != nil
            }
            .confirmationDialog("Replace this board with the chosen pictures?", isPresented: $confirmingReplacement, titleVisibility: .visible) {
                Button("Replace board") { editor.installPacket() }
                Button("Cancel", role: .cancel) { editor.cancelPacket() }
            } message: { Text("The previous saved board is retained. Existing tile positions will be replaced with the positions in that file.") }
        }
    }
    private func draftForm(_ draft: TileDraft) -> some View {
        Section {
            TextField("Label", text: Binding(get: { editor.draft?.label ?? "" }, set: { editor.label($0) }))
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .accessibilityIdentifier("editor-label")
            TextField("Words to say", text: Binding(get: { editor.draft?.spokenText ?? "" }, set: { editor.spokenText($0) }))
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .accessibilityIdentifier("editor-spoken")
            if let bytes = draft.photo, let image = UIImage(data: bytes) {
                Image(uiImage: image).resizable().scaledToFit().frame(height: 160)
            } else if let id = draft.original?.imageID, let image = editor.library.images[id] {
                Image(uiImage: image).resizable().scaledToFit().frame(height: 160)
            }
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) { Label("Choose photo", systemImage: "photo") }
                .disabled(editor.loadingPhoto)
            if editor.loadingPhoto { ProgressView("Opening photo…") }
            Button("Speak preview") { if let preview = editor.preview { speak(preview) } }
                .accessibilityIdentifier("editor-speak")
            Button("Save tile") { editor.saveDraft(); photoItem = nil }.disabled(!editor.canSave)
                .accessibilityIdentifier("editor-save")
            Button("Revert changes") { editor.revert(); photoItem = nil }
                .accessibilityIdentifier("editor-revert")
        } footer: { Text("The label and words spoken can be different. Saving keeps every other tile in its place.") }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            guard let id = editor.draft?.id else { return }
            Task {
                await editor.loadPhoto(for: id) { try await item.loadTransferable(type: Data.self) }
                if editor.draft?.id == id { photoItem = nil }
            }
        }
    }
    private func positionButton(_ position: Position) -> some View {
        let concept = editor.library.board.cells.first(where: { $0.position == position })
            .flatMap { cell in editor.library.board.concepts.first(where: { $0.id == cell.conceptID }) }
        return Button(concept?.label ?? "Empty cell: row \(position.row + 1), column \(position.column + 1)") {
            editor.begin(position); photoItem = nil
        }.accessibilityIdentifier("edit-cell-\(position.row)-\(position.column)")
    }
}
