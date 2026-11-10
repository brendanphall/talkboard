import SwiftUI
import TalkboardCore
import Testing
import UIKit
@testable import Talkboard

@Suite("Native picture tiles", .serialized)
@MainActor
struct TileImageTests {
    @Test("a supplied picture renders its own colors instead of the placeholder")
    func originalPicture() throws {
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0,y: 0,width: 20,height: 20))
        }
        let host = UIHostingController(rootView: TileView(concept: Concept(label: "Fixture", spokenText: "fixture"), image: picture, selected: false, onTap: {}))
        let window = UIWindow(frame: CGRect(x: 0,y: 0,width: 200,height: 200))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: 200,height: 200)).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let image = try #require(rendered.cgImage)
        var pixels = [UInt8](repeating: 0, count: 200 * 200 * 4)
        let blue = try pixels.withUnsafeMutableBytes { bytes -> Int in
            let context = try #require(CGContext(data: bytes.baseAddress, width: 200,height: 200,bitsPerComponent: 8,bytesPerRow: 800,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image,in: CGRect(x: 0,y: 0,width: 200,height: 200))
            let values = bytes.bindMemory(to: UInt8.self)
            return stride(from: 0,to: values.count,by: 4).filter { values[$0] < 60 && values[$0+1] < 100 && values[$0+2] > 180 }.count
        }
        #expect(blue > 1000)
    }
}
