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
        // 細部のテスト（fixtures の契約・検証の場所と理由まで見る）。scripts/test.sh detail で流す
        .testTarget(name: "PersistenceDetailTests", dependencies: ["Persistence"], path: "Tests/Detail"),
    ]
)
