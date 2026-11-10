import Foundation
import Observation
import TalkboardCore

/// Selection feedback is independent of the callback, so speech can begin immediately.
@MainActor
@Observable
final class BoardSelection {
    private(set) var selectedID: ConceptID?
    private(set) var token = UUID()

    func activate(_ id: ConceptID, onSelect: (ConceptID) -> Void) {
        selectedID = id
        token = UUID()
        onSelect(id)
    }

    func clear(matching expiredToken: UUID) {
        guard expiredToken == token else { return }
        selectedID = nil
    }
}
