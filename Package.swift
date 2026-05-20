// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ColimaBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "ColimaBarCore",
            path: "Sources/ColimaBarCore"
        ),
        .executableTarget(
            name: "ColimaBar",
            dependencies: ["ColimaBarCore"],
            path: "Sources/ColimaBar"
        ),
        .executableTarget(
            name: "ColimaBarTests",
            dependencies: ["ColimaBarCore"],
            path: "Tests/ColimaBarTests"
        )
    ]
)
