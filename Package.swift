// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Akuo",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AkuoCore", targets: ["AkuoCore"]),
        .library(name: "AkuoMac", targets: ["AkuoMac"]),
        .executable(name: "Akuo", targets: ["Akuo"]),
    ],
    targets: [
        .target(name: "AkuoCore"),
        .target(name: "AkuoMac", dependencies: ["AkuoCore"]),
        .executableTarget(name: "Akuo", dependencies: ["AkuoCore", "AkuoMac"]),
        .testTarget(name: "AkuoCoreTests", dependencies: ["AkuoCore"]),
        .testTarget(name: "AkuoMacTests", dependencies: ["AkuoCore", "AkuoMac"]),
    ],
    swiftLanguageModes: [.v5]
)
