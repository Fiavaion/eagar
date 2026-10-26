// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EagarPeople",
    defaultLocalization: "en-GB",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EagarPeople", targets: ["EagarPeople"]),
    ],
    dependencies: [
        .package(path: "../EagarCore"),
        .package(path: "../EagarStore"),
        .package(path: "../EagarSync"),
        .package(path: "../EagarCalendar"),
    ],
    targets: [
        .target(
            name: "EagarPeople",
            dependencies: ["EagarCore", "EagarStore", "EagarSync", "EagarCalendar"],
            resources: [.process("Resources")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "EagarPeopleTests",
            dependencies: ["EagarPeople", "EagarCore", "EagarStore", "EagarSync", "EagarCalendar"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
