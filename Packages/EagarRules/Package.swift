// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarRules",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarRules", targets: ["EagarRules"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
    ],
    targets: [
        .target(
            name: "EagarRules",
            dependencies: [.product(name: "EagarCore", package: "EagarCore")],
            resources: [.copy("Schemas")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarRulesTests",
            dependencies: ["EagarRules"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
