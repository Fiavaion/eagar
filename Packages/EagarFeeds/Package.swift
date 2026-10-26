// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarFeeds",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarFeeds", targets: ["EagarFeeds"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
        .package(path: "../EagarStore"),
        .package(path: "../EagarCalendar"),
    ],
    targets: [
        .target(
            name: "EagarFeeds",
            dependencies: [
                "EagarCore", "EagarStore",
                .product(name: "EagarCalendar", package: "EagarCalendar"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarFeedsTests",
            dependencies: [
                "EagarFeeds", "EagarCore", "EagarStore",
                .product(name: "EagarCalendar", package: "EagarCalendar"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
