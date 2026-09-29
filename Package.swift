// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Heartbeat",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Heartbeat",
            path: "Sources/Heartbeat"
        ),
        .testTarget(
            name: "HeartbeatTests",
            dependencies: ["Heartbeat"],
            path: "Tests/HeartbeatTests"
        )
    ]
)
