// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarTestSupport",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarTestSupport", targets: ["EagarTestSupport"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
        .package(path: "../EagarSecurity"),
        .package(path: "../EagarLedger"),
        .package(path: "../EagarAI"),
    ],
    targets: [
        .target(
            name: "EagarTestSupport",
            dependencies: [
                "EagarCore", "EagarSecurity", "EagarLedger",
                .product(name: "EagarAI", package: "EagarAI"),
                .product(name: "EagarAITestSupport", package: "EagarAI"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarTestSupportTests",
            dependencies: ["EagarTestSupport"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
