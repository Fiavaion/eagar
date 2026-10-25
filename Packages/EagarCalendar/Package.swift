// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarCalendar",
    defaultLocalization: "en-GB",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarCalendar", targets: ["EagarCalendar"]),
        // Test doubles (FakeEventStore, SpyNotificationScheduler), as in EagarAI (D-002).
        .library(name: "EagarCalendarTestSupport", targets: ["EagarCalendarTestSupport"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
        .package(path: "../EagarStore"),
    ],
    targets: [
        .target(
            name: "EagarCalendar",
            dependencies: ["EagarCore", "EagarStore"],
            resources: [.process("Resources")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "EagarCalendarTestSupport",
            dependencies: ["EagarCalendar", "EagarCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarCalendarTests",
            dependencies: ["EagarCalendar", "EagarCalendarTestSupport", "EagarCore", "EagarStore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
