// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarBrief",
    defaultLocalization: "en-GB",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarBrief", targets: ["EagarBrief"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
        .package(path: "../EagarStore"),
        .package(path: "../EagarCalendar"),
        .package(path: "../EagarAI"),
        .package(path: "../EagarSuggest"),
    ],
    targets: [
        .target(
            name: "EagarBrief",
            dependencies: [
                "EagarCore", "EagarStore", "EagarSuggest",
                .product(name: "EagarCalendar", package: "EagarCalendar"),
                .product(name: "EagarAI", package: "EagarAI"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarBriefTests",
            dependencies: [
                "EagarBrief", "EagarCore", "EagarStore", "EagarSuggest",
                .product(name: "EagarCalendar", package: "EagarCalendar"),
                .product(name: "EagarAI", package: "EagarAI"),
                .product(name: "EagarAITestSupport", package: "EagarAI"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
