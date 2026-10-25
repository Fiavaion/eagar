// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarAI",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarAI", targets: ["EagarAI"]),
        // Test doubles (RecordingProvider). Lives here because EagarTestSupport depends on
        // EagarAI, and a test-only dependency back on EagarTestSupport would be a package cycle.
        .library(name: "EagarAITestSupport", targets: ["EagarAITestSupport"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
        .package(path: "../EagarStore"),
        .package(path: "../EagarSecurity"),
        .package(path: "../EagarLedger"),
    ],
    targets: [
        .target(
            name: "EagarAI",
            dependencies: ["EagarCore", "EagarStore", "EagarSecurity", "EagarLedger"],
            resources: [.process("Resources")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "EagarAITestSupport",
            dependencies: ["EagarAI", "EagarCore", "EagarStore", "EagarLedger"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarAITests",
            dependencies: ["EagarAI", "EagarAITestSupport", "EagarCore", "EagarStore", "EagarSecurity", "EagarLedger"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
