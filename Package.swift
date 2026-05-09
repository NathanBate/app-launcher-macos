// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppLauncher",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "AppLauncher", targets: ["AppLauncher"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "AppLauncher",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
