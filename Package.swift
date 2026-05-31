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
        // Git URL (not a sibling path) so CI — which checks out only this repo —
        // can resolve it. The Amateur Radio Suite container, as the root package,
        // overrides this with its local `../RadioPluginKit` path for suite dev.
        .package(url: "https://github.com/VU3ESV/RadioPluginKit.git", from: "1.0.0"),
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
