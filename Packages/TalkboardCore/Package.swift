// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TalkboardCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TalkboardCore", targets: ["TalkboardCore"])],
    targets: [
        .target(name: "TalkboardCore"),
        .testTarget(
            name: "TalkboardCoreTests",
            dependencies: ["TalkboardCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
