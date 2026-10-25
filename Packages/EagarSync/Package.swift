// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarSync",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarSync", targets: ["EagarSync"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
        .package(path: "../EagarStore"),
    ],
    targets: [
        .target(
            name: "EagarSync",
            dependencies: ["EagarCore", "EagarStore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarSyncTests",
            dependencies: ["EagarSync", "EagarCore", "EagarStore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
