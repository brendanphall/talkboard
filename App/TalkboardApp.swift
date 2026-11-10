import SwiftUI
import TalkboardCore

@main
struct TalkboardApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech = AppleSpeechService()
    @State private var caregiver: AppleCaregiverService
    @State private var library: BoardLibrary

    init() {
        let service = AppleCaregiverService()
        _caregiver = State(initialValue: service)
        _library = State(initialValue: BoardLibrary(caregiver: service.controller))
    }

    var body: some Scene {
        WindowGroup {
            BoardWorkspace(library: library, caregiver: caregiver.controller, speech: speech)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    caregiver.background()
                    speech.background()
                } else if phase == .active {
                    caregiver.foreground()
                }
            }
        }
    }

}
