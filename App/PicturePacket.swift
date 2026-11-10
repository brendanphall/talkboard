import Foundation
import TalkboardCore

struct PreparedPictureBoard {
    let board: Board
    let media: [AssetID: Data]
}

enum PicturePacketError: Error, Equatable { case invalid, unsupportedImage }

/// A bounded bridge for local caregiver comparison exports, not a general board format.
enum PicturePacket {
    private struct Packet: Decodable { let version: Int; let selections: [Selection] }
    private struct Selection: Decodable { let card: Card; let asset: Picture }
    private struct Card: Decodable { let id: String; let label: String; let slot: Int; let spokenText: String? }
    private struct Picture: Decodable {
        let data: String; let source: String; let author: String; let license: String
        let modifications: String; let license_url: String?
    }
    static func prepare(_ data: Data) throws -> PreparedPictureBoard {
        guard data.count <= 20 * 1024 * 1024 else { throw PicturePacketError.invalid }
        let packet = try JSONDecoder().decode(Packet.self, from: data)
        guard packet.version == 1, (1...15).contains(packet.selections.count) else { throw PicturePacketError.invalid }
        var board = Board(name: "My board", grid: GridSize(rows: 3, columns: 5))
        var media: [AssetID: Data] = [:]
        for selection in packet.selections {
            guard (0..<15).contains(selection.card.slot), !selection.card.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PicturePacketError.invalid }
            let picture = selection.asset
            let prefixes = ["data:image/png;base64,", "data:image/jpeg;base64,"]
            guard let prefix = prefixes.first(where: { picture.data.hasPrefix($0) }) else {
                throw PicturePacketError.unsupportedImage
            }
            guard let bytes = Data(base64Encoded: String(picture.data.dropFirst(prefix.count))) else { throw PicturePacketError.invalid }
            let jpeg = try PhotoImport.prepare(bytes)
            let assetID = AssetID()
            let asset = Asset(id: assetID, kind: .image, filename: assetID.rawValue + ".jpg",
                provenance: Provenance(source: picture.source, author: picture.author,
                    license: picture.license + (picture.license_url.map { " (\($0))" } ?? ""),
                    modifications: picture.modifications + " Prepared as upright JPEG, longest edge at most 1024 pixels."))
            let concept = Concept(id: ConceptID(rawValue: selection.card.id), label: selection.card.label,
                spokenText: selection.card.spokenText ?? selection.card.label, imageID: assetID)
            board.concepts.append(concept)
            board.cells.append(Cell(position: Position(row: selection.card.slot / 5, column: selection.card.slot % 5), conceptID: concept.id))
            board.assets.append(asset); media[assetID] = jpeg
        }
        _ = try BoardCodec.encode(board)
        return PreparedPictureBoard(board: board, media: media)
    }
}
