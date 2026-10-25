// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarSecurity",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarSecurity", targets: ["EagarSecurity"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
    ],
    targets: [
        .target(
            name: "EagarSecurity",
            dependencies: ["EagarCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarSecurityTests",
            dependencies: ["EagarSecurity"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
