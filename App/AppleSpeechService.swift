import AVFoundation
import Combine
import Foundation
import TalkboardCore

@MainActor
final class AppleSpeechService {
    let controller: SpeechController
    private var notifications: AnyCancellable?

    convenience init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--silent-speech-test") {
            self.init(silentOutputFactory: { SilentSpeechSynthesizer() })
            return
        }
        #endif
        self.init(controller: SpeechController(engine: AppleSpeechEngine(), audio: AppleSpeechAudio(),
                                               preferences: AppleSpeechPreferences(), recordings: AppleRecordingEngine()))
    }

    #if DEBUG
    /// UI tests exercise voice selection, audio configuration and notifications without
    /// speaker output or a durable voice choice for the person's next manual run.
    convenience init(silentOutputFactory: @escaping () -> SilentSpeechSynthesizer) {
        self.init(controller: SpeechController(
            engine: AppleSpeechEngine(makeSynthesizer: { silentOutputFactory() }),
            audio: AppleSpeechAudio(), preferences: TransientSpeechPreferences()))
    }
    #endif

    init(controller: SpeechController, notifications center: NotificationCenter = .default) {
        self.controller = controller
        let names = [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification]
        notifications = Publishers.MergeMany(names.map { center.publisher(for: $0) })
            .compactMap(Self.event(for:))
            .receive(on: DispatchQueue.main)
            .sink { [weak controller] event in
                // receive(on:) guarantees this queue; assert isolation instead of passing
                // non-Sendable Foundation notifications through an unstructured Task.
                MainActor.assumeIsolated { controller?.handle(event) }
            }
    }

    func speak(conceptID: ConceptID, in board: Board, recordingURL: URL? = nil) {
        guard let concept = board.concepts.first(where: { $0.id == conceptID }) else { return }
        controller.speak(concept, recordingURL: recordingURL)
    }

    func background() { controller.handle(.background) }

    nonisolated static func event(for notification: Notification) -> SpeechEvent? {
        switch notification.name {
        case AVAudioSession.interruptionNotification:
            switch notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt {
            case AVAudioSession.InterruptionType.began.rawValue: return .interruptionBegan
            case AVAudioSession.InterruptionType.ended.rawValue: return .interruptionEnded
            default: return nil
            }
        case AVAudioSession.routeChangeNotification:
            // Our own activation changes category. It must not cancel the tap that caused it.
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                == AVAudioSession.RouteChangeReason.categoryChange.rawValue { return nil }
            return .routeChanged
        case AVAudioSession.mediaServicesWereResetNotification:
            return .mediaServicesReset
        default:
            return nil
        }
    }
}

#if DEBUG
@MainActor
final class SilentSpeechSynthesizer: NativeSpeechSynthesizing {
    var usesApplicationAudioSession = false
    private(set) var utteranceCount = 0
    private(set) var stopCount = 0
    func speak(_ utterance: AVSpeechUtterance) { utteranceCount += 1 }
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool { stopCount += 1; return true }
}
@MainActor
private final class TransientSpeechPreferences: SpeechPreferences {
    var preferredVoiceID: String?
}
#endif
