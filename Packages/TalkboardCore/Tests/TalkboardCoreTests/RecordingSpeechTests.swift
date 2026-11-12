import Foundation
import Testing
@testable import TalkboardCore

@Suite("Recorded tile audio")
@MainActor
struct RecordingSpeechTests {
    @Test("leaving an activity stops both outputs without replay and allows another tap")
    func deliberateStop() {
        let f = RecordingFixture()
        f.controller.speak(f.concept, recordingURL: f.url)
        f.trace.events = []
        f.controller.stop()
        #expect(f.trace.events == ["speech.stop", "recording.stop", "deactivate"])
        #expect(f.controller.issue == nil)
        #expect(f.recordings.urls == [f.url])
        f.controller.speak(f.concept)
        #expect(f.engine.texts == [" exact words "])
    }

    @Test("a recorded tile recovers without an interruption-ended notification")
    func missingInterruptionEnd() {
        let f = RecordingFixture()
        f.controller.handle(.interruptionBegan)
        #expect(f.recordings.urls.isEmpty)
        f.controller.speak(f.concept, recordingURL: f.url)
        #expect(f.recordings.urls == [f.url])
        #expect(f.controller.issue == nil)
    }

    @Test("a recording plays before voice or text validation without changing the voice preference")
    func recordingWithoutVoiceOrText() {
        let f = RecordingFixture()
        f.engine.installedVoices = []
        f.preferences.preferredVoiceID = "chosen"
        f.controller.speak(Concept(label: "Sound", spokenText: ""), recordingURL: f.url)
        #expect(f.trace.events == ["speech.stop", "recording.stop", "activate", "recording.play"])
        #expect(f.recordings.urls == [f.url])
        #expect(f.engine.texts.isEmpty)
        #expect(f.preferences.preferredVoiceID == "chosen")
        #expect(f.controller.issue == nil)
    }

    @Test("recording repeats and switches between speech and recording always interrupt both outputs")
    func preemption() {
        let f = RecordingFixture()
        f.controller.speak(f.concept)
        f.controller.speak(f.concept, recordingURL: f.url)
        f.controller.speak(f.concept, recordingURL: f.url)
        f.controller.speak(f.concept)
        #expect(f.trace.events == [
            "speech.stop", "recording.stop", "activate", "speech.speak",
            "speech.stop", "recording.stop", "activate", "recording.play",
            "speech.stop", "recording.stop", "activate", "recording.play",
            "speech.stop", "recording.stop", "activate", "speech.speak"
        ])
        #expect(f.recordings.urls == [f.url, f.url])
        #expect(f.engine.texts == [" exact words ", " exact words "])
    }

    @Test("a missing recording URL uses the exact spoken text even with a recording identifier")
    func absentURL() {
        let f = RecordingFixture()
        var concept = f.concept
        concept.recordingID = AssetID(rawValue: "missing")
        f.controller.speak(concept)
        #expect(f.engine.texts == [" exact words "])
        #expect(f.recordings.urls.isEmpty)
        #expect(f.controller.issue == nil)
    }

    @Test("without a recording engine a recording URL falls back to spoken text")
    func noRecordingEngine() {
        let f = RecordingFixture()
        let c = SpeechController(engine: f.engine, audio: f.audio, preferences: f.preferences)
        c.speak(f.concept, recordingURL: f.url)
        #expect(f.engine.texts == [" exact words "])
        #expect(c.issue == nil)
    }

    @Test("failed recorded playback stops before falling back to exact saved speech")
    func recordingFailure() {
        let f = RecordingFixture()
        f.recordings.fails = true
        f.controller.speak(f.concept, recordingURL: f.url)
        #expect(f.trace.events == ["speech.stop", "recording.stop", "activate", "recording.play", "recording.stop", "activate", "speech.speak"])
        #expect(f.engine.texts == [" exact words "])
        #expect(f.controller.issue == nil)
    }

    @Test("failed recorded playback with no voice reports the speech fallback failure")
    func failedFallback() {
        let f = RecordingFixture()
        f.recordings.fails = true
        f.engine.installedVoices = []
        f.controller.speak(f.concept, recordingURL: f.url)
        #expect(f.controller.issue == .noInstalledVoice)
        #expect(f.trace.events.last == "deactivate")
        #expect(f.engine.texts.isEmpty)
    }

    @Test("audio activation failure does not start recording or speech")
    func activationFailure() {
        let f = RecordingFixture()
        f.audio.fails = true
        f.controller.speak(f.concept, recordingURL: f.url)
        #expect(f.trace.events == ["speech.stop", "recording.stop", "activate", "deactivate"])
        #expect(f.recordings.urls.isEmpty)
        #expect(f.engine.texts.isEmpty)
        #expect(f.controller.issue == .audioUnavailable)
    }

    @Test("an unavailable audio session suppresses recording without automatic replay")
    func interruption() {
        let f = RecordingFixture()
        f.controller.handle(.interruptionBegan)
        f.audio.fails = true
        f.trace.events = []
        f.controller.speak(f.concept, recordingURL: f.url)
        #expect(f.recordings.urls.isEmpty)
        #expect(f.trace.events == ["speech.stop", "recording.stop", "speech.reset", "recording.reset", "activate", "deactivate"])
        #expect(f.controller.issue == .audioUnavailable)
        f.audio.fails = false
        f.controller.handle(.interruptionEnded)
        #expect(f.recordings.urls.isEmpty)
        f.controller.speak(f.concept, recordingURL: f.url)
        #expect(f.recordings.urls == [f.url])
        #expect(f.controller.issue == nil)
    }

    @Test("background and route changes stop both outputs without replay", arguments: [SpeechEvent.background, .routeChanged])
    func lifecycle(event: SpeechEvent) {
        let f = RecordingFixture()
        f.controller.speak(f.concept, recordingURL: f.url)
        f.trace.events = []
        f.controller.handle(event)
        #expect(f.trace.events == ["speech.stop", "recording.stop", "deactivate"])
        #expect(f.recordings.urls == [f.url])
        #expect(f.controller.issue == (event == .background ? nil : .interrupted))
    }

    @Test("media reset and foreground replace outputs without replay", arguments: [SpeechEvent.mediaServicesReset, .foreground])
    func mediaReset(event: SpeechEvent) {
        let f = RecordingFixture()
        f.controller.speak(f.concept, recordingURL: f.url)
        f.trace.events = []
        f.controller.handle(event)
        #expect(f.trace.events == ["speech.stop", "recording.stop", "deactivate", "speech.reset", "recording.reset"])
        #expect(f.recordings.urls == [f.url])
        f.controller.speak(f.concept, recordingURL: f.url)
        #expect(f.recordings.urls.count == 2)
    }
}

@MainActor
private final class RecordingTrace { var events: [String] = [] }
private enum RecordingTestError: Error { case failure }

@MainActor
private final class RecordingFixture {
    let trace = RecordingTrace()
    let engine: RecordingTestSpeech
    let recordings: RecordingTestPlayer
    let audio: RecordingTestAudio
    let preferences = RecordingTestPreferences()
    let controller: SpeechController
    let url = URL(fileURLWithPath: "/fixture/clip.m4a")
    let concept = Concept(label: "Sound", spokenText: " exact words ")
    init() {
        engine = RecordingTestSpeech(trace)
        recordings = RecordingTestPlayer(trace)
        audio = RecordingTestAudio(trace)
        controller = SpeechController(engine: engine, audio: audio, preferences: preferences, recordings: recordings)
    }
}

@MainActor
private final class RecordingTestSpeech: SpeechEngine {
    let trace: RecordingTrace
    var installedVoices = [SpeechVoice(id: "us", language: "en-US")]
    var texts: [String] = []
    init(_ trace: RecordingTrace) { self.trace = trace }
    func stop() { trace.events.append("speech.stop") }
    func reset() { trace.events.append("speech.reset") }
    func speak(text: String, voiceID: String) throws { trace.events.append("speech.speak"); texts.append(text) }
}

@MainActor
private final class RecordingTestPlayer: SpeechRecordingEngine {
    let trace: RecordingTrace
    var urls: [URL] = []
    var fails = false
    init(_ trace: RecordingTrace) { self.trace = trace }
    func stop() { trace.events.append("recording.stop") }
    func reset() { trace.events.append("recording.reset") }
    func play(url: URL) throws {
        trace.events.append("recording.play")
        if fails { throw RecordingTestError.failure }
        urls.append(url)
    }
}

@MainActor
private final class RecordingTestAudio: SpeechAudio {
    let trace: RecordingTrace
    var fails = false
    init(_ trace: RecordingTrace) { self.trace = trace }
    func activate() throws {
        trace.events.append("activate")
        if fails { throw RecordingTestError.failure }
    }
    func deactivate() throws { trace.events.append("deactivate") }
}

@MainActor
private final class RecordingTestPreferences: SpeechPreferences { var preferredVoiceID: String? }
