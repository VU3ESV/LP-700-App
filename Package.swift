// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LP-700-App",
    platforms: [.macOS(.v14)],
    products: [
        // Standalone .app
        .executable(name: "LP-700-App", targets: ["LP700AppMain"]),
        // Plugin library consumed by the Amateur Radio Suite container
        .library(name: "LP700App", targets: ["LP700App"]),
    ],
    dependencies: [
        .package(path: "../RadioPluginKit"),
    ],
    targets: [
        .target(
            name: "LP700App",
            dependencies: [
                .product(name: "RadioPluginKit", package: "RadioPluginKit"),
            ],
            path: "Sources/LP700App"
        ),
        .executableTarget(
            name: "LP700AppMain",
            dependencies: ["LP700App"],
            path: "Sources/LP700AppMain"
        ),
        .testTarget(
            name: "LP700AppTests",
            dependencies: ["LP700App"],
            path: "Tests/LP700AppTests"
        ),
    ]
)
