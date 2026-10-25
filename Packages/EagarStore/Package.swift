// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarStore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarStore", targets: ["EagarStore"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
    ],
    targets: [
        .target(
            name: "EagarStore",
            dependencies: ["EagarCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarStoreTests",
            dependencies: ["EagarStore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
