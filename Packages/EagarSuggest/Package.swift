// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarSuggest",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarSuggest", targets: ["EagarSuggest"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
        .package(path: "../EagarStore"),
    ],
    targets: [
        .target(
            name: "EagarSuggest",
            dependencies: ["EagarCore", "EagarStore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarSuggestTests",
            dependencies: ["EagarSuggest", "EagarCore", "EagarStore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
