import Foundation
import UIKit
import TalkboardCore

/// Licensed prototype artwork, separate from the person's stored images.
@MainActor
enum AlphaSymbolLibrary {
    static let assets: [Asset] = {
        guard let url = Bundle.main.url(forResource: "alpha-symbols", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let assets = try? JSONDecoder().decode([Asset].self, from: data) else { return [] }
        return assets
    }()

    static let urls: [AssetID: URL] = Dictionary(uniqueKeysWithValues: assets.compactMap { asset in
        Bundle.main.url(forResource: asset.filename, withExtension: nil).map { (asset.id, $0) }
    })

    static let images: [AssetID: UIImage] = {
        var result: [AssetID: UIImage] = [:]
        for asset in assets {
            guard let url = Bundle.main.url(forResource: asset.filename, withExtension: nil),
                  let image = UIImage(contentsOfFile: url.path) else { continue }
            result[asset.id] = image
        }
        return result
    }()

    static func asset(for word: String) -> Asset? {
        assets.first { $0.id.rawValue == "alpha-symbol-\(word)" }
    }
}
