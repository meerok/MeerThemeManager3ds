// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MtM3",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MtM3", targets: ["MtM3"]),
        .executable(name: "mtm3-cli", targets: ["mtm3-cli"]),
        .library(name: "ThemeKit", targets: ["ThemeKit"]),
    ],
    targets: [
        .target(name: "ThemeKit", path: "Sources/ThemeKit"),
        .executableTarget(name: "MtM3", dependencies: ["ThemeKit"], path: "Sources/MtM3"),
        .executableTarget(name: "mtm3-cli", dependencies: ["ThemeKit"], path: "Sources/mtm3-cli"),
    ]
)
