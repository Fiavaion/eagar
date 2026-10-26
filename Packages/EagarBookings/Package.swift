// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarBookings",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarBookings", targets: ["EagarBookings"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
        .package(path: "../EagarStore"),
        .package(path: "../EagarSecurity"),
        .package(path: "../EagarCalendar"),
        .package(path: "../EagarFeeds"),
        // Tests only: the mock cdbooking server and fakes (PRD M2), and the sync gate for B-8.
        .package(path: "../EagarTestSupport"),
        .package(path: "../EagarSync"),
    ],
    targets: [
        .target(
            name: "EagarBookings",
            dependencies: [
                "EagarCore", "EagarStore", "EagarSecurity",
                .product(name: "EagarCalendar", package: "EagarCalendar"),
                .product(name: "EagarFeeds", package: "EagarFeeds"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarBookingsTests",
            dependencies: [
                "EagarBookings", "EagarCore", "EagarStore", "EagarSecurity",
                .product(name: "EagarCalendar", package: "EagarCalendar"),
                .product(name: "EagarFeeds", package: "EagarFeeds"),
                .product(name: "EagarTestSupport", package: "EagarTestSupport"),
                .product(name: "EagarSync", package: "EagarSync"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
