import SwiftUI
import TalkboardCore

extension SpeechIssue {
    var message: String {
        switch self {
        case .noInstalledVoice: "No installed English voice is available."
        case .noSpokenText: "This tile has no spoken text yet."
        case .audioUnavailable: "Audio is unavailable. Tap again to retry."
        case .interrupted: "Speech interrupted. Tap again when audio is available."
        }
    }
}

/// Fits in the already-reserved band and never intercepts a communication tap.
struct SpeechNotice: View {
    let issue: SpeechIssue?

    var body: some View {
        if let issue {
            Text(issue.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("speech-notice")
                .allowsHitTesting(false)
        }
    }
}
