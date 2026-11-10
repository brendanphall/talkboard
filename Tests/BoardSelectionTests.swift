import Testing
import TalkboardCore
@testable import Talkboard

@Suite("Board selection")
@MainActor
struct BoardSelectionTests {
    @Test("a tap immediately selects and reports its exact concept once")
    func activation() {
        let selection = BoardSelection()
        let cup = ConceptID(rawValue: "cup")
        var calls: [ConceptID] = []
        selection.activate(cup) { id in
            #expect(selection.selectedID == cup)
            calls.append(id)
        }
        #expect(calls == [cup])
        #expect(selection.selectedID == cup)
    }

    @Test("repeated intentional taps each report once and renew feedback")
    func repeats() {
        let selection = BoardSelection()
        let cup = ConceptID(rawValue: "cup")
        var calls: [ConceptID] = []
        selection.activate(cup) { calls.append($0) }
        let first = selection.token
        selection.activate(cup) { calls.append($0) }
        #expect(selection.token != first)
        #expect(calls == [cup, cup])
    }

    @Test("an old feedback expiry cannot clear a newer selection")
    func staleExpiry() {
        let selection = BoardSelection()
        let cup = ConceptID(rawValue: "cup")
        let park = ConceptID(rawValue: "park")
        selection.activate(cup) { _ in }
        let first = selection.token
        selection.activate(park) { _ in }
        selection.clear(matching: first)
        #expect(selection.selectedID == park)
        selection.clear(matching: selection.token)
        #expect(selection.selectedID == nil)
    }

    @Test("the untouched board has no selection")
    func initial() {
        #expect(BoardSelection().selectedID == nil)
    }
}
