// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarLedger",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarLedger", targets: ["EagarLedger"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
        .package(path: "../EagarStore"),
        .package(path: "../EagarSecurity"),
    ],
    targets: [
        .target(
            name: "EagarLedger",
            dependencies: ["EagarCore", "EagarStore", "EagarSecurity"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarLedgerTests",
            dependencies: ["EagarLedger", "EagarCore", "EagarStore", "EagarSecurity"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
