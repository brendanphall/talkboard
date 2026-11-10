import Foundation

public enum BoardCodecError: Error, Hashable, Sendable {
    /// The file is not a readable board.
    case unreadable
    /// The file was written by a format version this build does not know. It is refused,
    /// never reset, so a newer board is not overwritten by an older build
    /// (spec, "No destructive silent migration").
    case unsupportedSchemaVersion(Int)
    /// The file holds fields this build does not know. Saving it would drop them, so it is
    /// refused. Rule: any new persisted field means a new schema version.
    case unknownFields([String])
    /// The board describes something unsafe to show or save.
    case invalid([BoardIssue])
}

/// Reads and writes a board as JSON. Both directions validate, so an unsafe board is never
/// written and never shown.
public enum BoardCodec {
    /// Listed one by one: a new version needs its own reader or migration, never an assumption.
    public static let supportedSchemaVersions: Set<Int> = [1]

    public static func encode(_ board: Board, knownBoards: Set<BoardID> = []) throws -> Data {
        let issues = board.issues(knownBoards: knownBoards)
        guard issues.isEmpty else { throw BoardCodecError.invalid(issues) }
        return try makeEncoder().encode(board)
    }

    public static func decode(_ data: Data, knownBoards: Set<BoardID> = []) throws(BoardCodecError) -> Board {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw .unreadable }
        guard supportedSchemaVersions.contains(header.schemaVersion) else {
            throw .unsupportedSchemaVersion(header.schemaVersion)
        }
        guard let board = try? decoder.decode(Board.self, from: data) else { throw .unreadable }
        let unknown = unknownFields(in: data, keptBy: board)
        guard unknown.isEmpty else { throw .unknownFields(unknown) }
        let issues = board.issues(knownBoards: knownBoards)
        guard issues.isEmpty else { throw .invalid(issues) }
        return board
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Field paths present in the file but lost when the decoded board is written back.
    private static func unknownFields(in data: Data, keptBy board: Board) -> [String] {
        guard let input = try? JSONSerialization.jsonObject(with: data),
              let rewritten = try? makeEncoder().encode(board),
              let output = try? JSONSerialization.jsonObject(with: rewritten)
        else { return [] }
        return fieldPaths(input).subtracting(fieldPaths(output)).map(render).sorted()
    }

    private enum PathStep: Hashable {
        case key(String)
        case index(Int)
    }

    /// Every non-null field as a structured path, so a key that looks like a path
    /// ("grid.rows") never matches a real nested field.
    private static func fieldPaths(_ value: Any, under prefix: [PathStep] = []) -> Set<[PathStep]> {
        if let object = value as? [String: Any] {
            return object.reduce(into: Set<[PathStep]>()) { paths, field in
                guard !(field.value is NSNull) else { return }
                let path = prefix + [.key(field.key)]
                paths.insert(path)
                paths.formUnion(fieldPaths(field.value, under: path))
            }
        }
        if let array = value as? [Any] {
            return array.enumerated().reduce(into: Set<[PathStep]>()) { paths, element in
                paths.formUnion(fieldPaths(element.element, under: prefix + [.index(element.offset)]))
            }
        }
        return []
    }

    private static func render(_ path: [PathStep]) -> String {
        path.reduce(into: "") { text, step in
            switch step {
            case .key(let key): text += text.isEmpty ? key : ".\(key)"
            case .index(let index): text += "[\(index)]"
            }
        }
    }
}
