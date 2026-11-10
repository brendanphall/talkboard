import Foundation
import Testing
import TalkboardCore
import UIKit
@testable import Talkboard

@Suite("Picture selection packet")
@MainActor
struct PicturePacketTests {
    @Test("import preserves chosen slots, labels, spoken text and source credits")
    func preservesMeaning() throws {
        let prepared = try PicturePacket.prepare(packet())
        #expect(prepared.board.cells[0].position == Position(row: 1, column: 2))
        #expect(prepared.board.concepts[0].label == "Sample")
        #expect(prepared.board.concepts[0].spokenText == "A saved phrase")
        #expect(prepared.board.assets[0].provenance.source == "fixture source")
        #expect(prepared.board.assets[0].provenance.author == "fixture author")
        #expect(prepared.board.assets[0].provenance.license.contains("https://example.com/license"))
        #expect(UIImage(data: try #require(prepared.media.values.first)) != nil)
    }

    @Test("bad versions, out-of-grid cells and duplicate positions are rejected")
    func invalidStructure() throws {
        #expect(throws: (any Error).self) { try PicturePacket.prepare(packet(version: 2)) }
        #expect(throws: (any Error).self) { try PicturePacket.prepare(packet(label: "  ")) }
        #expect(throws: (any Error).self) { try PicturePacket.prepare(packet(slot: 15)) }
        #expect(throws: (any Error).self) { try PicturePacket.prepare(packet(copies: 2)) }
        #expect(throws: (any Error).self) { try PicturePacket.prepare(packet(copies: 0)) }
        #expect(throws: (any Error).self) { try PicturePacket.prepare(packet(copies: 16)) }
        #expect(throws: (any Error).self) { try PicturePacket.prepare(Data(repeating: 0, count: 20 * 1024 * 1024 + 1)) }
    }

    @Test("SVG, malformed base64 and undecodable image bytes are rejected")
    func invalidImages() throws {
        #expect(throws: PicturePacketError.unsupportedImage) { try PicturePacket.prepare(packet(uri: "data:image/svg+xml;base64,AAAA")) }
        #expect(throws: (any Error).self) { try PicturePacket.prepare(packet(uri: "data:image/png;base64,???")) }
        #expect(throws: (any Error).self) { try PicturePacket.prepare(packet(uri: "data:image/png;base64,AAAA")) }
    }

    @Test("omitted spoken text falls back to the chosen label without rewriting it")
    func labelFallback() throws {
        let prepared = try PicturePacket.prepare(packet(spoken: false, licenseURL: false))
        #expect(prepared.board.concepts[0].spokenText == "Sample")
        #expect(prepared.board.assets[0].provenance.license == "fixture license")
    }

    private func packet(version: Int = 1, label: String = "Sample", slot: Int = 7, copies: Int = 1, uri: String? = nil,
                        spoken: Bool = true, licenseURL: Bool = true) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 3)).image { _ in UIColor.blue.setFill(); UIRectFill(CGRect(x: 0,y: 0,width: 3,height: 3)) }
        let data = try #require(image.pngData())
        var card: [String: Any] = ["id":"sample", "label":label, "slot":slot]
        if spoken { card["spokenText"] = "A saved phrase" }
        var asset: [String: Any] = ["data":uri ?? "data:image/png;base64," + data.base64EncodedString(), "source":"fixture source", "author":"fixture author", "license":"fixture license", "modifications":"Original"]
        if licenseURL { asset["license_url"] = "https://example.com/license" }
        return try JSONSerialization.data(withJSONObject: ["version":version,"selections":Array(repeating: ["card":card,"asset":asset], count:copies)])
    }
}
