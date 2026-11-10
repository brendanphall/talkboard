import AVFoundation
import Foundation
import SwiftUI
import Testing
import TalkboardCore
@testable import Talkboard

@Suite("Apple speech adapters", .serialized)
@MainActor
struct AppleSpeechTests {
    @Test("native speech uses the selected installed voice and application audio session")
    func nativeUtterance() throws {
        let voice = try #require(AVSpeechSynthesisVoice(language: "en-US"))
        let synth = NativeSynthSpy()
        let engine = AppleSpeechEngine(makeSynthesizer: { synth }, voices: { [voice] }, voiceLookup: { id in
            #expect(id == voice.identifier)
            return voice
        })
        #expect(synth.usesApplicationAudioSession)
        #expect(engine.installedVoices.map(\.id) == [voice.identifier])
        #expect(engine.installedVoices.map(\.language) == [voice.language])
        try engine.speak(text: "a placeholder phrase", voiceID: voice.identifier)
        #expect(synth.utterances.count == 1)
        #expect(synth.utterances[0].speechString == "a placeholder phrase")
        #expect(synth.utterances[0].voice?.identifier == voice.identifier)
        engine.stop()
        #expect(synth.boundaries == [.immediate])
    }

    @Test("the system-recommended installed normal voice precedes identifier ordering")
    func recommendedDefault() throws {
        let us = try #require(AVSpeechSynthesisVoice(language: "en-US"))
        let gb = try #require(AVSpeechSynthesisVoice(language: "en-GB"))
        let sorted = [us, gb].sorted { $0.identifier < $1.identifier }
        let recommended = try #require(sorted.last)
        let engine = AppleSpeechEngine(voices: { sorted }, defaultVoiceID: { recommended.identifier })
        #expect(engine.installedVoices.first?.id == recommended.identifier)
        #expect(engine.installedVoices.count == 2)
    }

    @Test("a voice that disappears after selection is rejected without enqueueing")
    func disappearedVoice() {
        let synth = NativeSynthSpy()
        let engine = AppleSpeechEngine(makeSynthesizer: { synth }, voices: { [] }, voiceLookup: { _ in nil })
        #expect(engine.installedVoices.isEmpty)
        #expect(throws: SpeechIssue.noInstalledVoice) { try engine.speak(text: "cup", voiceID: "missing") }
        #expect(synth.utterances.isEmpty)
    }

    @Test("reset constructs a new synthesizer configured for the application session")
    func nativeReset() {
        var created: [NativeSynthSpy] = []
        let engine = AppleSpeechEngine(makeSynthesizer: {
            let synth = NativeSynthSpy()
            created.append(synth)
            return synth
        })
        engine.reset()
        #expect(created.count == 2)
        #expect(created[0].usesApplicationAudioSession)
        #expect(created[1].usesApplicationAudioSession)
        engine.stop()
        #expect(created[0].boundaries.isEmpty)
        #expect(created[1].boundaries == [.immediate])
    }

    @Test("audio configures playback and spoken audio before activation and releases on request")
    func audioConfiguration() throws {
        let native = NativeAudioSpy()
        var lookups = 0
        let audio = AppleSpeechAudio(session: { lookups += 1; return native })
        try audio.activate()
        #expect(native.events == ["category", "active"])
        #expect(native.category == .playback)
        #expect(native.mode == .spokenAudio)
        #expect(native.categoryOptions == [])
        #expect(native.activeOptions == [])
        try audio.deactivate()
        #expect(native.events == ["category", "active", "inactive"])
        #expect(native.activeOptions == .notifyOthersOnDeactivation)
        #expect(lookups == 2)
    }

    @Test("native session failures propagate for the controller to display and retry")
    func audioFailure() {
        let native = NativeAudioSpy()
        native.fail = true
        let audio = AppleSpeechAudio(session: { native })
        #expect(throws: AdapterFailure.failed) { try audio.activate() }
        #expect(throws: AdapterFailure.failed) { try audio.deactivate() }
    }

    @Test("voice preferences survive a new defaults adapter")
    func preferences() throws {
        let name = "talkboard-speech-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppleSpeechPreferences(defaults: defaults)
        #expect(preferences.preferredVoiceID == nil)
        preferences.preferredVoiceID = "invented-installed-id"
        #expect(AppleSpeechPreferences(defaults: defaults).preferredVoiceID == "invented-installed-id")
        preferences.preferredVoiceID = nil
        #expect(preferences.preferredVoiceID == nil)
    }

    @Test("notifications ignore our own category changes and decode interruption phases")
    func notificationMapping() {
        #expect(AppleSpeechService.event(for: Notification(name: .init("unrelated"))) == nil)
        #expect(AppleSpeechService.event(for: Notification(name: AVAudioSession.interruptionNotification)) == nil)
        #expect(AppleSpeechService.event(for: Notification(name: AVAudioSession.interruptionNotification,
            userInfo: [AVAudioSessionInterruptionTypeKey: UInt(99)])) == nil)
        #expect(AppleSpeechService.event(for: Notification(name: AVAudioSession.interruptionNotification,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])) == .interruptionBegan)
        #expect(AppleSpeechService.event(for: Notification(name: AVAudioSession.interruptionNotification,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])) == .interruptionEnded)
        #expect(AppleSpeechService.event(for: Notification(name: AVAudioSession.routeChangeNotification,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue])) == nil)
        #expect(AppleSpeechService.event(for: Notification(name: AVAudioSession.routeChangeNotification)) == .routeChanged)
        #expect(AppleSpeechService.event(for: Notification(name: AVAudioSession.routeChangeNotification,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])) == .routeChanged)
        #expect(AppleSpeechService.event(for: Notification(name: AVAudioSession.mediaServicesWereResetNotification)) == .mediaServicesReset)
    }

    @Test("background notifications reach the main actor and subscriptions cancel on release")
    func notifications() async {
        let center = NotificationCenter()
        let driver = ServiceDriver()
        let controller = SpeechController(engine: driver, audio: driver, preferences: driver)
        var service: AppleSpeechService? = AppleSpeechService(controller: controller, notifications: center)
        #expect(service != nil)
        await Task.detached {
            center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        }.value
        await drainMainQueue()
        #expect(driver.events == ["stop", "deactivate", "reset"])
        driver.events = []
        service = nil
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        await drainMainQueue()
        #expect(driver.events.isEmpty)
    }

    @Test("board selection reaches the saved spoken text and an unknown identity speaks nothing")
    func boardWiring() {
        let driver = ServiceDriver()
        let service = AppleSpeechService(controller: SpeechController(engine: driver, audio: driver, preferences: driver), notifications: NotificationCenter())
        let concept = Concept(id: ConceptID(rawValue: "cup"), label: "Cup", spokenText: "please pass the cup")
        let board = Board(name: "Placeholder", grid: .init(rows: 1, columns: 1), concepts: [concept],
                          cells: [.init(position: .init(row: 0, column: 0), conceptID: concept.id)])
        service.speak(conceptID: ConceptID(rawValue: "missing"), in: board)
        #expect(driver.texts.isEmpty)
        service.speak(conceptID: concept.id, in: board)
        #expect(driver.texts == ["please pass the cup"])
        service.background()
        #expect(driver.events.suffix(2) == ["stop", "deactivate"])
    }

    @Test("speech notices explain retry without hiding or intercepting the board")
    func notices() {
        let expected: [(SpeechIssue, String)] = [
            (.noInstalledVoice, "No installed English voice is available."),
            (.noSpokenText, "This tile has no spoken text yet."),
            (.audioUnavailable, "Audio is unavailable. Tap again to retry."),
            (.interrupted, "Speech interrupted. Tap again when audio is available."),
        ]
        for (issue, message) in expected {
            #expect(issue.message == message)
            let host = UIHostingController(rootView: SpeechNotice(issue: issue))
            host.loadViewIfNeeded()
            host.view.layoutIfNeeded()
            let size = host.sizeThatFits(in: CGSize(width: 600, height: 56))
            #expect(size.height > 0)
            #expect(size.height <= 56)
        }
        let empty = UIHostingController(rootView: SpeechNotice(issue: nil))
        empty.loadViewIfNeeded()
        empty.view.layoutIfNeeded()
        #expect(empty.sizeThatFits(in: CGSize(width: 600, height: 56)).height == 0)
    }

    @Test("the silent test service keeps new output after activation notifications without persisting a choice")
    func nativeSmoke() async throws {
        let savedBefore = AppleSpeechPreferences().preferredVoiceID
        var outputs: [SilentSpeechSynthesizer] = []
        let service = AppleSpeechService(silentOutputFactory: {
            let output = SilentSpeechSynthesizer()
            outputs.append(output)
            return output
        })
        let concept = Concept(id: .init(rawValue: "smoke"), label: "Preview", spokenText: "This is a placeholder speech check.")
        let board = Board(name: "Preview", grid: .init(rows: 1, columns: 1), concepts: [concept],
                          cells: [.init(position: .init(row: 0, column: 0), conceptID: concept.id)])
        defer { service.background() }
        service.speak(conceptID: concept.id, in: board)
        await drainMainQueue()
        try await Task.sleep(for: .milliseconds(200))
        #expect(service.controller.issue == nil)
        #expect(outputs[0].usesApplicationAudioSession)
        #expect(outputs[0].utteranceCount == 1)
        #expect(outputs[0].stopCount == 1)
        #expect(AppleSpeechPreferences().preferredVoiceID == savedBefore)
        service.controller.handle(.mediaServicesReset)
        #expect(outputs.count == 2)
        #expect(outputs[1].usesApplicationAudioSession)
        #expect(outputs[1].utteranceCount == 0)
        // Voice metadata only. No utterance content is logged.
        let voice = AVSpeechSynthesisVoice(language: "en-US")
        print("System English default: \(voice?.identifier ?? "unavailable") (\(voice?.name ?? "unavailable"))")
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor
private final class NativeSynthSpy: NativeSpeechSynthesizing {
    var usesApplicationAudioSession = false
    var utterances: [AVSpeechUtterance] = []
    var boundaries: [AVSpeechBoundary] = []
    func speak(_ utterance: AVSpeechUtterance) { utterances.append(utterance) }
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool { boundaries.append(boundary); return true }
}
private enum AdapterFailure: Error { case failed }
@MainActor
private final class NativeAudioSpy: NativeAudioSession {
    var category: AVAudioSession.Category?
    var mode: AVAudioSession.Mode?
    var categoryOptions: AVAudioSession.CategoryOptions?
    var activeOptions: AVAudioSession.SetActiveOptions?
    var events: [String] = []
    var fail = false
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {
        if fail { throw AdapterFailure.failed }
        self.category = category
        self.mode = mode
        categoryOptions = options
        events.append("category")
    }
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        if fail { throw AdapterFailure.failed }
        activeOptions = options
        events.append(active ? "active" : "inactive")
    }
}
@MainActor
private final class ServiceDriver: SpeechEngine, SpeechAudio, SpeechPreferences {
    var installedVoices = [SpeechVoice(id: "us", language: "en-US")]
    var preferredVoiceID: String?
    var texts: [String] = []
    var events: [String] = []
    func stop() { events.append("stop") }
    func reset() { events.append("reset") }
    func speak(text: String, voiceID: String) throws { texts.append(text); events.append("speak") }
    func activate() throws { events.append("activate") }
    func deactivate() throws { events.append("deactivate") }
}
