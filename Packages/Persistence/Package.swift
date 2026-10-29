// swift-tools-version: 6.2
// Ceremony: パッケージの設定（名前・対象 OS・依存するパッケージ）。処理は書いていない
import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [.macOS(.v14), .iOS(.v26)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(path: "../TodoCore")
    ],
    targets: [
        .target(name: "Persistence", dependencies: ["TodoCore"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    ]
)
