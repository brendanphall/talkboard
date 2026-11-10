import AVFoundation
import Foundation
import TalkboardCore

@MainActor
protocol NativeSpeechSynthesizing: AnyObject {
    var usesApplicationAudioSession: Bool { get set }
    func speak(_ utterance: AVSpeechUtterance)
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}
extension AVSpeechSynthesizer: NativeSpeechSynthesizing {}

@MainActor
final class AppleSpeechEngine: SpeechEngine {
    private var synthesizer: any NativeSpeechSynthesizing
    private let makeSynthesizer: () -> any NativeSpeechSynthesizing
    private let voices: () -> [AVSpeechSynthesisVoice]
    private let defaultVoiceID: () -> String?
    private let voiceLookup: (String) -> AVSpeechSynthesisVoice?

    init(
        makeSynthesizer: @escaping () -> any NativeSpeechSynthesizing = { AVSpeechSynthesizer() },
        voices: @escaping () -> [AVSpeechSynthesisVoice] = { AVSpeechSynthesisVoice.speechVoices() },
        defaultVoiceID: @escaping () -> String? = { AVSpeechSynthesisVoice(language: "en-US")?.identifier },
        voiceLookup: @escaping (String) -> AVSpeechSynthesisVoice? = { AVSpeechSynthesisVoice(identifier: $0) }
    ) {
        self.makeSynthesizer = makeSynthesizer
        self.voices = voices
        self.defaultVoiceID = defaultVoiceID
        self.voiceLookup = voiceLookup
        synthesizer = makeSynthesizer()
        synthesizer.usesApplicationAudioSession = true
    }

    var installedVoices: [SpeechVoice] {
        let available = voices().sorted { $0.identifier < $1.identifier }.map {
            SpeechVoice(id: $0.identifier, language: $0.language,
                        isDefaultEligible: $0.voiceTraits.intersection([.isNoveltyVoice, .isPersonalVoice]).isEmpty)
        }
        let recommended = defaultVoiceID()
        guard let preferred = available.first(where: { $0.id == recommended && $0.isDefaultEligible }) else { return available }
        return [preferred] + available.filter { $0.id != preferred.id }
    }

    func stop() { _ = synthesizer.stopSpeaking(at: .immediate) }

    func speak(text: String, voiceID: String) throws {
        // Recheck availability at use. An identifier can disappear after the catalog was read.
        guard let voice = voiceLookup(voiceID) else { throw SpeechIssue.noInstalledVoice }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    func reset() {
        synthesizer = makeSynthesizer()
        synthesizer.usesApplicationAudioSession = true
    }
}

@MainActor
protocol NativeAudioSession: AnyObject {
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}
extension AVAudioSession: NativeAudioSession {}

@MainActor
final class AppleSpeechAudio: SpeechAudio {
    private let session: () -> any NativeAudioSession

    init(session: @escaping () -> any NativeAudioSession = { AVAudioSession.sharedInstance() }) {
        self.session = session
    }

    func activate() throws {
        // Reacquire and reconfigure after every interruption or media-services reset.
        let audio = session()
        try audio.setCategory(.playback, mode: .spokenAudio, options: [])
        try audio.setActive(true, options: [])
    }

    func deactivate() throws {
        try session().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
final class AppleSpeechPreferences: SpeechPreferences {
    private let defaults: UserDefaults
    private let key = "talkboard.speech.preferredVoiceID"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var preferredVoiceID: String? {
        get { defaults.string(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
