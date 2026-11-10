import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PhotoImportError: Error, Equatable, LocalizedError {
    case emptyImage, fileTooLarge, invalidImage, dimensionsTooLarge, encodingFailed

    var message: String {
        switch self {
        case .emptyImage: "That photo is empty. Choose another photo."
        case .fileTooLarge: "That photo is too large. Choose a photo smaller than 25 MB."
        case .invalidImage: "That photo could not be opened. Try another photo."
        case .dimensionsTooLarge: "That photo has too many pixels. Choose a smaller photo."
        case .encodingFailed: "That photo could not be prepared. Try another photo."
        }
    }

    var errorDescription: String? { message }
}

enum PhotoImport {
    static func prepare(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw PhotoImportError.emptyImage }
        guard data.count <= 25 * 1024 * 1024 else { throw PhotoImportError.fileTooLarge }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw PhotoImportError.invalidImage
        }
        // Check metadata before decoding; division avoids overflowing a width * height product.
        guard width <= 100_000_000 / height else { throw PhotoImportError.dimensionsTooLarge }
        guard CGImageSourceGetStatus(source) == .statusComplete else { throw PhotoImportError.invalidImage }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw PhotoImportError.invalidImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoImportError.encodingFailed
        }
        // Re-encode pixels only, omitting location, camera and original orientation metadata.
        // ImageIO composites alpha onto white when the JPEG destination has no background override.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoImportError.encodingFailed }
        return output as Data
    }
}
