// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CaptionCore",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "CaptionCore", targets: ["CaptionCore"]),
        .executable(name: "CaptionProbe", targets: ["CaptionProbe"])
    ],
    targets: [
        .binaryTarget(name: "whisper", path: "Frameworks/whisper.xcframework"),
        .target(name: "CaptionCore", dependencies: ["whisper"]),
        .executableTarget(name: "CaptionProbe", dependencies: ["CaptionCore"]),
        .testTarget(name: "CaptionCoreTests", dependencies: ["CaptionCore"])
    ],
    swiftLanguageModes: [.v5]
)
