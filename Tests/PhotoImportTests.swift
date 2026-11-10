import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Talkboard

@Suite("Photo preparation")
struct PhotoImportTests {
    @Test("empty and corrupt input fail without producing image bytes")
    func invalidInput() {
        #expect(throws: PhotoImportError.emptyImage) { try PhotoImport.prepare(Data()) }
        #expect(throws: PhotoImportError.invalidImage) { try PhotoImport.prepare(Data("not an image".utf8)) }
    }

    @Test("input larger than 25 MiB is rejected before decoding")
    func encodedSizeLimit() {
        let oversized = Data(repeating: 0, count: 25 * 1024 * 1024 + 1)
        #expect(throws: PhotoImportError.fileTooLarge) { try PhotoImport.prepare(oversized) }
    }

    @Test("JPEG, PNG and HEIC become JPEG without enlarging a small image", arguments: [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier])
    func smallImage(type: String) throws {
        let input = try fixture(width: 120, height: 80, type: type)
        let result = try PhotoImport.prepare(input)
        let source = try #require(CGImageSourceCreateWithData(result as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 120)
        #expect(image.height == 80)
    }

    @Test("large images downsample to 1024 pixels and preserve aspect ratio")
    func downsample() throws {
        let result = try PhotoImport.prepare(fixture(width: 2048, height: 1024))
        let source = try #require(CGImageSourceCreateWithData(result as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 1024)
        #expect(image.height == 512)
    }

    @Test("EXIF rotations and mirrors become upright pixels without an orientation tag", arguments: 1...8)
    func uprightOrientation(orientation: Int) throws {
        let result = try PhotoImport.prepare(fixture(width: 120, height: 80, orientation: orientation))
        let source = try #require(CGImageSourceCreateWithData(result as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == (orientation >= 5 ? 80 : 120))
        #expect(image.height == (orientation >= 5 ? 120 : 80))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        #expect(properties[kCGImagePropertyOrientation as String] == nil)
        // Source quadrants, top row first: red, green, blue, yellow.
        let expected = [
            [0, 1, 2, 3], [1, 0, 3, 2], [3, 2, 1, 0], [2, 3, 0, 1],
            [0, 2, 1, 3], [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2],
        ][orientation - 1]
        #expect(try quadrantColors(image) == expected)
    }

    @Test("re-encoding omits source location and camera metadata")
    func privateMetadataOmitted() throws {
        let input = try fixture(width: 120, height: 80, metadata: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.3, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Invented test camera"],
        ])
        let original = try #require(CGImageSourceCreateWithData(input as CFData, nil))
        let originalProperties = try #require(CGImageSourceCopyPropertiesAtIndex(original, 0, nil) as? [String: Any])
        #expect(originalProperties[kCGImagePropertyGPSDictionary as String] != nil)
        let result = try PhotoImport.prepare(input)
        let source = try #require(CGImageSourceCreateWithData(result as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        #expect(properties[kCGImagePropertyGPSDictionary as String] == nil)
        #expect(properties[kCGImagePropertyTIFFDictionary as String] == nil)
    }

    @Test("transparent PNG pixels become white in the JPEG")
    func transparentBackground() throws {
        let result = try PhotoImport.prepare(fixture(width: 80, height: 80, type: UTType.png.identifier, transparent: true))
        let source = try #require(CGImageSourceCreateWithData(result as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixels = try rgba(image)
        #expect(pixels[0] > 245 && pixels[1] > 245 && pixels[2] > 245)
    }

    @Test("over 100 million advertised pixels are rejected before full image decoding")
    func oversizedPixelDimensions() throws {
        var input = try fixture(width: 2, height: 2)
        // JPEG SOF stores height then width. Changing its header needs no large allocation.
        let marker = try #require(input.indices.dropLast(8).first {
            input[$0] == 0xff && [0xc0, 0xc1, 0xc2].contains(input[$0 + 1])
        })
        input.replaceSubrange((marker + 5)..<(marker + 9), with: [0x27, 0x10, 0x27, 0x11]) // 10001 x 10000
        // ImageIO can reject the mismatched huge header before returning dimensions.
        #expect(throws: (any Error).self) { try PhotoImport.prepare(input) }
    }

    @Test("a truncated undecodable JPEG header is rejected")
    func truncatedInput() throws {
        let input = try fixture(width: 120, height: 80)
        #expect(throws: PhotoImportError.invalidImage) { try PhotoImport.prepare(Data(input.prefix(32))) }
    }
}

private func fixture(width: Int, height: Int, type: String = UTType.jpeg.identifier,
                     orientation: Int = 1, transparent: Bool = false,
                     metadata: [CFString: Any] = [:]) throws -> Data {
    let colors: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 0, 255]]
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    if !transparent {
        for y in 0..<height {
            for x in 0..<width {
                let color = colors[(y >= height / 2 ? 2 : 0) + (x >= width / 2 ? 1 : 0)]
                let offset = (y * width + x) * 4
                pixels.replaceSubrange(offset..<offset + 4, with: color)
            }
        }
    }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
    var properties = metadata
    properties[kCGImagePropertyOrientation] = orientation
    properties[kCGImageDestinationLossyCompressionQuality] = 1.0
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

private func rgba(_ image: CGImage) throws -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try pixels.withUnsafeMutableBytes { bytes in
        let context = try #require(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                            bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return pixels
}

private func quadrantColors(_ image: CGImage) throws -> [Int] {
    let pixels = try rgba(image)
    return [(1, 1), (3, 1), (1, 3), (3, 3)].map { x, y in
        let offset = ((image.height * y / 4) * image.width + image.width * x / 4) * 4
        let r = pixels[offset] > 180, g = pixels[offset + 1] > 180, b = pixels[offset + 2] > 180
        if r && g { return 3 }
        if r { return 0 }
        if g { return 1 }
        if b { return 2 }
        return -1
    }
}
