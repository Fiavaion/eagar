// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarCore", targets: ["EagarCore"]),
    ],
    targets: [
        .target(
            name: "EagarCore",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarCoreTests",
            dependencies: ["EagarCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
