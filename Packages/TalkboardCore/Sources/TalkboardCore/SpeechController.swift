import Foundation
import Observation

public struct SpeechVoice: Equatable, Sendable {
    public let id: String
    public let language: String
    public let isDefaultEligible: Bool

    public init(id: String, language: String, isDefaultEligible: Bool = true) {
        self.id = id
        self.language = language
        self.isDefaultEligible = isDefaultEligible
    }
}

@MainActor
public protocol SpeechEngine: AnyObject {
    var installedVoices: [SpeechVoice] { get }
    func stop()
    func speak(text: String, voiceID: String) throws
    func reset()
}

@MainActor
public protocol SpeechRecordingEngine: AnyObject {
    func stop()
    func play(url: URL) throws
    func reset()
}

@MainActor
public protocol SpeechAudio: AnyObject {
    func activate() throws
    func deactivate() throws
}

@MainActor
public protocol SpeechPreferences: AnyObject {
    var preferredVoiceID: String? { get set }
}

public enum SpeechIssue: Error, Equatable, Sendable {
    case noInstalledVoice, noSpokenText, audioUnavailable, interrupted
}

public enum SpeechEvent: Sendable {
    case interruptionBegan, interruptionEnded, routeChanged, mediaServicesReset, background
}

/// Engineering safeguards AAC-006/007: a tap replaces prior output, using saved recording or exact text.
/// There is no completion callback or speaking-state gate to strand later selections.
@MainActor
@Observable
public final class SpeechController {
    public private(set) var issue: SpeechIssue?
    private var interruptionActive = false
    private let engine: any SpeechEngine
    private let audio: any SpeechAudio
    private let preferences: any SpeechPreferences
    private let recordings: (any SpeechRecordingEngine)?

    public init(engine: any SpeechEngine, audio: any SpeechAudio, preferences: any SpeechPreferences,
                recordings: (any SpeechRecordingEngine)? = nil) {
        self.engine = engine
        self.audio = audio
        self.preferences = preferences
        self.recordings = recordings
    }

    public func speak(_ concept: Concept, recordingURL: URL? = nil) {
        engine.stop()
        recordings?.stop()
        issue = nil
        guard !interruptionActive else {
            fail(.interrupted)
            return
        }
        if let recordingURL, let recordings {
            do { try audio.activate() }
            catch {
                fail(.audioUnavailable)
                return
            }
            do {
                try recordings.play(url: recordingURL)
                return
            } catch {
                // A missing or undecodable recording keeps the saved words available.
                recordings.stop()
            }
        }
        guard !concept.spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail(.noSpokenText)
            return
        }
        guard let voice = selectedVoice() else {
            fail(.noInstalledVoice)
            return
        }
        if preferences.preferredVoiceID == nil { preferences.preferredVoiceID = voice.id }
        do {
            try audio.activate()
            try engine.speak(text: concept.spokenText, voiceID: voice.id)
        } catch {
            engine.stop()
            fail(.audioUnavailable)
        }
    }

    /// A future authenticated caregiver workflow can change the preference without speaking.
    public func chooseVoice(_ identifier: String) throws {
        guard engine.installedVoices.contains(where: { $0.id == identifier }) else {
            throw SpeechIssue.noInstalledVoice
        }
        preferences.preferredVoiceID = identifier
    }

    public func handle(_ event: SpeechEvent) {
        switch event {
        case .interruptionEnded:
            interruptionActive = false
            return
        case .interruptionBegan:
            interruptionActive = true
        case .mediaServicesReset, .background:
            interruptionActive = false
        case .routeChanged:
            break
        }
        engine.stop()
        recordings?.stop()
        try? audio.deactivate()
        if event == .mediaServicesReset {
            engine.reset()
            recordings?.reset()
        }
        issue = event == .background ? nil : .interrupted
    }

    private func selectedVoice() -> SpeechVoice? {
        let voices = engine.installedVoices
        if let preferred = voices.first(where: { $0.id == preferences.preferredVoiceID }) { return preferred }
        let defaults = voices.filter(\.isDefaultEligible)
        return defaults.first(where: { $0.language == "en-US" })
            ?? defaults.first(where: { $0.language == "en" || $0.language.hasPrefix("en-") })
    }

    private func fail(_ problem: SpeechIssue) {
        issue = problem
        try? audio.deactivate()
    }
}
