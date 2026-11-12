import Foundation
import Testing
@testable import TalkboardCore

@Suite("Immediate speech")
@MainActor
struct SpeechControllerTests {
    @Test("a fresh tap recovers when interruption ended never arrives")
    func missingInterruptionEnd() {
        let f = SpeechFixture()
        f.controller.handle(.interruptionBegan)
        #expect(f.engine.texts.isEmpty)
        f.controller.speak(Concept(label: "Help", spokenText: "help"))
        #expect(f.engine.texts == ["help"])
        #expect(f.controller.issue == nil)
    }

    @Test("a selection speaks its exact saved text after stopping and activating audio")
    func exactText() {
        let f = SpeechFixture()
        f.controller.speak(Concept(label: "Cup", spokenText: "  please give me the cup  "))
        #expect(f.trace.events == ["stop", "activate", "speak"])
        #expect(f.engine.texts == ["  please give me the cup  "])
        #expect(f.engine.voiceIDs == ["us"])
        #expect(f.controller.issue == nil)
    }

    @Test("rapid repeats and a different word each stop before speaking without a backlog")
    func repeatTaps() {
        let f = SpeechFixture()
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        f.controller.speak(Concept(label: "Stop", spokenText: "stop"))
        #expect(f.trace.events == ["stop", "activate", "speak", "stop", "activate", "speak", "stop", "activate", "speak"])
        #expect(f.engine.texts == ["cup", "cup", "stop"])
    }

    @Test("the first installed US English choice is persisted across controller creation")
    func initialVoice() {
        let f = SpeechFixture()
        f.engine.installedVoices = [.init(id: "fr", language: "fr-FR"), .init(id: "gb", language: "en-GB"), .init(id: "us", language: "en-US")]
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        #expect(f.preferences.preferredVoiceID == "us")
        let reopened = SpeechController(engine: f.engine, audio: f.audio, preferences: f.preferences)
        f.engine.installedVoices.reverse()
        reopened.speak(Concept(label: "Park", spokenText: "park"))
        #expect(f.engine.voiceIDs == ["us", "us"])
    }

    @Test("an unavailable preference falls back without being overwritten and recovers on return")
    func missingPreferredVoice() {
        let f = SpeechFixture()
        f.preferences.preferredVoiceID = "preferred"
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        #expect(f.preferences.preferredVoiceID == "preferred")
        #expect(f.engine.voiceIDs == ["us"])
        f.engine.installedVoices.append(.init(id: "preferred", language: "en-GB"))
        f.controller.speak(Concept(label: "Park", spokenText: "park"))
        #expect(f.engine.voiceIDs == ["us", "preferred"])
    }

    @Test("fallback uses another English voice when US English is absent", arguments: ["en", "en-AU"])
    func englishFallback(language: String) {
        let f = SpeechFixture()
        f.engine.installedVoices = [.init(id: "fr", language: "fr-FR"), .init(id: "au", language: language)]
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        #expect(f.engine.voiceIDs == ["au"])
    }

    @Test("a language code merely starting with en is not treated as English")
    func languageBoundary() {
        let f = SpeechFixture()
        f.engine.installedVoices = [.init(id: "other", language: "eng")]
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        #expect(f.controller.issue == .noInstalledVoice)
        #expect(f.engine.texts.isEmpty)
    }

    @Test("novelty and personal voices are not selected as defaults")
    func eligibleDefaults() {
        let f = SpeechFixture()
        f.engine.installedVoices = [.init(id: "novelty", language: "en-US", isDefaultEligible: false), .init(id: "standard", language: "en-GB")]
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        #expect(f.engine.voiceIDs == ["standard"])
    }

    @Test("an explicitly chosen installed voice is kept even when it is not a default candidate")
    func explicitChoice() throws {
        let f = SpeechFixture()
        f.engine.installedVoices.append(.init(id: "chosen", language: "en-GB", isDefaultEligible: false))
        try f.controller.chooseVoice("chosen")
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        #expect(f.preferences.preferredVoiceID == "chosen")
        #expect(f.engine.voiceIDs == ["chosen"])
    }

    @Test("choosing an unavailable voice leaves the existing preference unchanged")
    func unavailableChoice() {
        let f = SpeechFixture()
        f.preferences.preferredVoiceID = "us"
        #expect(throws: SpeechIssue.noInstalledVoice) { try f.controller.chooseVoice("missing") }
        #expect(f.preferences.preferredVoiceID == "us")
        #expect(f.trace.events.isEmpty)
    }

    @Test("missing English voices report a retryable problem without speaking an unrelated language", arguments: [false, true])
    func missingVoice(empty: Bool) {
        let f = SpeechFixture()
        f.engine.installedVoices = empty ? [] : [.init(id: "fr", language: "fr-FR")]
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        #expect(f.controller.issue == .noInstalledVoice)
        #expect(f.engine.texts.isEmpty)
        #expect(f.trace.events == ["stop", "deactivate"])
        #expect(f.preferences.preferredVoiceID == nil)
        f.engine.installedVoices = [.init(id: "us", language: "en-US")]
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        #expect(f.controller.issue == nil)
        #expect(f.engine.texts == ["cup"])
    }

    @Test("empty spoken text never falls back to a label", arguments: ["", " \n\t"])
    func emptyText(text: String) {
        let f = SpeechFixture()
        f.controller.speak(Concept(label: "Not selected speech", spokenText: text))
        #expect(f.controller.issue == .noSpokenText)
        #expect(f.engine.texts.isEmpty)
        #expect(f.trace.events == ["stop", "deactivate"])
    }

    @Test("audio activation failure is visible and the next tap retries")
    func activationFailure() {
        let f = SpeechFixture()
        f.audio.failActivation = true
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        #expect(f.controller.issue == .audioUnavailable)
        #expect(f.engine.texts.isEmpty)
        #expect(f.trace.events == ["stop", "activate", "stop", "deactivate"])
        f.audio.failActivation = false
        f.controller.speak(Concept(label: "Park", spokenText: "park"))
        #expect(f.controller.issue == nil)
        #expect(f.engine.texts == ["park"])
    }

    @Test("a failed speech start is cancelled and does not block a later tap")
    func speechFailure() {
        let f = SpeechFixture()
        f.engine.failSpeak = true
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        #expect(f.controller.issue == .audioUnavailable)
        #expect(f.trace.events == ["stop", "activate", "speak", "stop", "deactivate"])
        f.engine.failSpeak = false
        f.controller.speak(Concept(label: "Park", spokenText: "park"))
        #expect(f.controller.issue == nil)
        #expect(f.engine.texts == ["park"])
    }

    @Test("interruption and route changes cancel stale speech without replay", arguments: [SpeechEvent.interruptionBegan, .routeChanged])
    func interruption(event: SpeechEvent) {
        let f = SpeechFixture()
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        f.trace.events = []
        f.controller.handle(event)
        #expect(f.trace.events == ["stop", "deactivate"])
        #expect(f.controller.issue == .interrupted)
        f.controller.handle(.interruptionEnded)
        #expect(f.engine.texts == ["cup"])
        f.controller.speak(Concept(label: "Park", spokenText: "park"))
        #expect(f.engine.texts == ["cup", "park"])
        #expect(f.controller.issue == nil)
    }

    @Test("unavailable audio during interruption rejects a tap without queuing it")
    func activeInterruption() {
        let f = SpeechFixture()
        f.controller.handle(.interruptionBegan)
        f.audio.failActivation = true
        f.trace.events = []
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        #expect(f.engine.texts.isEmpty)
        #expect(f.trace.events == ["stop", "reset", "activate", "stop", "deactivate"])
        #expect(f.controller.issue == .audioUnavailable)
        f.audio.failActivation = false
        f.controller.handle(.interruptionEnded)
        #expect(f.engine.texts.isEmpty)
        f.controller.speak(Concept(label: "Park", spokenText: "park"))
        #expect(f.engine.texts == ["park"])
        #expect(f.controller.issue == nil)
    }

    @Test("background and media reset clear a stale interruption without replay", arguments: [SpeechEvent.background, .mediaServicesReset, .foreground])
    func staleInterruptionRecovery(event: SpeechEvent) {
        let f = SpeechFixture()
        f.controller.handle(.interruptionBegan)
        f.controller.handle(event)
        #expect(f.engine.texts.isEmpty)
        f.controller.speak(Concept(label: "Park", spokenText: "park"))
        #expect(f.engine.texts == ["park"])
    }

    @Test("an interruption ending does not cancel or replay a newer tap")
    func endedIsNotReplay() {
        let f = SpeechFixture()
        f.controller.speak(Concept(label: "Park", spokenText: "park"))
        f.trace.events = []
        f.controller.handle(.interruptionEnded)
        #expect(f.trace.events.isEmpty)
        #expect(f.engine.texts == ["park"])
    }

    @Test("a media reset replaces audio objects and waits for another selection")
    func mediaReset() {
        let f = SpeechFixture()
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        f.trace.events = []
        f.controller.handle(.mediaServicesReset)
        #expect(f.trace.events == ["stop", "deactivate", "reset"])
        #expect(f.engine.texts == ["cup"])
        f.controller.speak(Concept(label: "Park", spokenText: "park"))
        #expect(f.engine.texts == ["cup", "park"])
        #expect(f.controller.issue == nil)
    }

    @Test("backgrounding stops speech and releases audio without replay")
    func background() {
        let f = SpeechFixture()
        f.controller.speak(Concept(label: "Cup", spokenText: "cup"))
        f.trace.events = []
        f.controller.handle(.background)
        #expect(f.trace.events == ["stop", "deactivate"])
        #expect(f.controller.issue == nil)
        #expect(f.engine.texts == ["cup"])
    }

    @Test("a deactivation error cannot prevent a reset or a later tap")
    func deactivationFailure() {
        let f = SpeechFixture()
        f.audio.failDeactivation = true
        f.controller.handle(.mediaServicesReset)
        #expect(f.trace.events == ["stop", "deactivate", "reset"])
        f.controller.speak(Concept(label: "Park", spokenText: "park"))
        #expect(f.engine.texts == ["park"])
    }
}

@MainActor
private final class SpeechFixture {
    let trace = SpeechTrace()
    let preferences = FakeSpeechPreferences()
    let engine: FakeSpeechEngine
    let audio: FakeSpeechAudio
    let controller: SpeechController
    init() {
        engine = FakeSpeechEngine(trace)
        audio = FakeSpeechAudio(trace)
        controller = SpeechController(engine: engine, audio: audio, preferences: preferences)
    }
}
@MainActor private final class SpeechTrace { var events: [String] = [] }
private enum InjectedSpeechFailure: Error { case failed }
@MainActor private final class FakeSpeechPreferences: SpeechPreferences { var preferredVoiceID: String? }
@MainActor
private final class FakeSpeechEngine: SpeechEngine {
    let trace: SpeechTrace
    var installedVoices = [SpeechVoice(id: "us", language: "en-US")]
    var texts: [String] = []
    var voiceIDs: [String] = []
    var failSpeak = false
    init(_ trace: SpeechTrace) { self.trace = trace }
    func stop() { trace.events.append("stop") }
    func reset() { trace.events.append("reset") }
    func speak(text: String, voiceID: String) throws {
        trace.events.append("speak")
        if failSpeak { throw InjectedSpeechFailure.failed }
        texts.append(text)
        voiceIDs.append(voiceID)
    }
}
@MainActor
private final class FakeSpeechAudio: SpeechAudio {
    let trace: SpeechTrace
    var failActivation = false
    var failDeactivation = false
    init(_ trace: SpeechTrace) { self.trace = trace }
    func activate() throws {
        trace.events.append("activate")
        if failActivation { throw InjectedSpeechFailure.failed }
    }
    func deactivate() throws {
        trace.events.append("deactivate")
        if failDeactivation { throw InjectedSpeechFailure.failed }
    }
}
