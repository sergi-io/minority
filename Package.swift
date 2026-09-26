// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GestureControl",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "GestureControl", targets: ["GestureControl"])],
    targets: [
        .executableTarget(name: "GestureControl"),
        .testTarget(name: "GestureControlTests", dependencies: ["GestureControl"])
    ]
)
