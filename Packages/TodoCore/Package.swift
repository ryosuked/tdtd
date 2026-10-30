// swift-tools-version: 6.2
// Ceremony: パッケージの設定（名前・対象 OS・依存するパッケージ）。処理は書いていない
import PackageDescription

let package = Package(
    name: "TodoCore",
    // iPadOS は画面設計の対象。ビルドの確認は今は macOS だけ
    platforms: [.macOS(.v14), .iOS(.v26)],
    products: [
        .library(name: "TodoCore", targets: ["TodoCore"])
    ],
    targets: [
        .target(name: "TodoCore"),
        // 細部のテスト（値・表記まで見て、カバレッジを満たす）。scripts/test.sh detail で流す
        .testTarget(name: "TodoCoreDetailTests", dependencies: ["TodoCore"], path: "Tests/Detail"),
    ]
)
