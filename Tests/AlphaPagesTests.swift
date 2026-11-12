import Testing
import UIKit
import TalkboardCore
@testable import Talkboard

@MainActor
struct AlphaPagesTests {
    @Test func peoplePageIsIndependentAndKeepsAllSavedFields() throws {
        let home = PreviewBoard.make()
        var people = PeopleBoard.empty
        let asset = Asset(id: AssetID(rawValue: "private-photo"), kind: .image, filename: "person.jpg",
                          provenance: Provenance(source: "synthetic fixture", license: "test"))
        let person = Concept(id: ConceptID(rawValue: "person"), label: "Person", spokenText: "Saved name", imageID: asset.id)
        people.concepts = [person]
        people.cells = [Cell(position: Position(row: 1, column: 2), conceptID: person.id)]
        people.assets = [asset]
        let pages = AlphaPages.make(home: home, people: people)
        #expect(pages.count == AlphaPages.count)
        #expect(Array(pages.prefix(3)) == Array(AlphaPages.make(home: home).prefix(3)))
        #expect(pages[3] == people)
        #expect(pages[3].concepts.count == 1)
        _ = try BoardCodec.encode(pages[3])
    }

    @Test func repeatsYesGoNoStopHelpAtTheirHomeCoordinates() throws {
        var home = PreviewBoard.make()
        home.concepts.append(Concept(id: ConceptID(rawValue: "yes"), label: "Yes", spokenText: "Yes"))
        home.cells.append(Cell(position: Position(row: 1, column: 3), conceptID: ConceptID(rawValue: "yes")))
        let go = try #require(home.cells.firstIndex { $0.conceptID.rawValue == "go" })
        home.cells[go].position = Position(row: 1, column: 1)
        let picture = Asset(id: AssetID(rawValue: "saved-go-picture"), kind: .image, filename: "go.png",
                            provenance: Provenance(source: "synthetic test", license: "test"))
        let recording = Asset(id: AssetID(rawValue: "saved-go-recording"), kind: .recording, filename: "go.wav",
                              provenance: Provenance(source: "synthetic test", license: "test"))
        home.assets = [picture, recording]
        let concept = try #require(home.concepts.firstIndex { $0.id.rawValue == "go" })
        home.concepts[concept].imageID = picture.id
        home.concepts[concept].recordingID = recording.id
        let pages = AlphaPages.make(home: home)
        for page in pages.prefix(3) {
            _ = try BoardCodec.encode(page)
            #expect(page.assets.contains(picture))
            #expect(page.assets.contains(recording))
            for id in ["yes", "go", "stop", "no", "help"] {
                let original = try #require(home.concepts.first { $0.id.rawValue == id })
                #expect(page.concepts.first { $0.id == original.id } == original)
                #expect(page.cells.first { $0.conceptID == original.id } == home.cells.first { $0.conceptID == original.id })
            }
        }
    }

    @Test func vocabularyPicturesAreBundledWithAttribution() throws {
        for word in ["done", "eat", "potty", "outside", "bye", "school", "book", "train", "ball", "cat"] {
            let asset = try #require(AlphaSymbolLibrary.asset(for: word))
            #expect(AlphaSymbolLibrary.images[asset.id] != nil)
            #expect(asset.provenance.license == "CC-BY-NC-SA-4.0")
            #expect(asset.provenance.source.hasPrefix("https://arasaac.org/pictograms/en/"))
        }
    }

    @Test func loadedHomeIsPreservedExactlyIncludingCustomTextAndPositions() {
        var home = PreviewBoard.make()
        home.name = "Saved board"
        home.concepts[0].label = "Personal label"
        home.concepts[0].spokenText = "Different spoken meaning"
        home.concepts[0].recordingID = AssetID(rawValue: "saved-audio")
        home.concepts[0].imageID = AssetID(rawValue: "saved-image")
        home.cells.swapAt(0, 3)
        let pages = AlphaPages.make(home: home)
        #expect(pages[0] == home)
        #expect(pages[0].concepts[0].recordingID == AssetID(rawValue: "saved-audio"))
        #expect(pages[0].concepts[0].imageID == AssetID(rawValue: "saved-image"))
    }

    @Test func samplesKeepHomeAndSafetyCoordinatesAndHaveVisibleSymbols() throws {
        let pages = AlphaPages.make(home: PreviewBoard.make())
        #expect(pages.count == 4)
        #expect(pages[0] == PreviewBoard.make())
        for page in pages.prefix(3) {
            _ = try BoardCodec.encode(page)
            for id in ["stop", "no", "help"] {
                let key = ConceptID(rawValue: id)
                #expect(page.cells.first { $0.conceptID == key } == pages[0].cells.first { $0.conceptID == key })
            }
            for concept in page.concepts where !["cup", "stop", "no", "open", "park", "go", "more", "help", "ball", "book"].contains(concept.id.rawValue) {
                let id = try #require(concept.imageID)
                #expect(AlphaSymbolLibrary.images[id] != nil)
            }
        }
        let labels = Set(pages.flatMap(\.concepts).map(\.label))
        #expect(Set(["Done", "Eat", "Potty", "Outside", "Bye bye", "School", "Book", "Train", "Ball", "Cat"]).isSubset(of: labels))
    }
}
