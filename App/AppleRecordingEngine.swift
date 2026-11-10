import AVFoundation
import Foundation
import TalkboardCore

@MainActor
protocol NativeRecordingPlaying: AnyObject {
    func play() -> Bool
    func stop()
}
extension AVAudioPlayer: NativeRecordingPlaying {}

/// One retained player, replaced on every tap. Audio-session policy is shared with speech.
@MainActor
final class AppleRecordingEngine: SpeechRecordingEngine {
    private var player: (any NativeRecordingPlaying)?
    private let makePlayer: (URL) throws -> any NativeRecordingPlaying

    init(makePlayer: @escaping (URL) throws -> any NativeRecordingPlaying = { try AVAudioPlayer(contentsOf: $0) }) {
        self.makePlayer = makePlayer
    }

    func play(url: URL) throws {
        stop()
        let next = try makePlayer(url)
        guard next.play() else {
            next.stop()
            throw SpeechIssue.audioUnavailable
        }
        player = next
    }

    func stop() {
        player?.stop()
        player = nil
    }

    func reset() { stop() }
}
