// swift-tools-version: 6.2
// Ceremony: パッケージの設定（名前・対象 OS・依存するパッケージ）。処理は書いていない
import PackageDescription

let package = Package(
    name: "Features",
    // 画面は macOS と iPadOS の両方を対象に設計する。ビルドの確認は今は macOS だけ
    platforms: [.macOS(.v14), .iOS(.v26)],
    products: [
        .library(name: "Features", targets: ["Features"])
    ],
    dependencies: [
        .package(path: "../TodoCore"),
        .package(path: "../Persistence"),
    ],
    targets: [
        .target(name: "Features", dependencies: ["TodoCore", "Persistence"]),
        // シナリオのテスト（道具としての一連の流れを AppModel から通す）。scripts/test.sh scenario で流す
        .testTarget(name: "ScenarioTests", dependencies: ["Features", "Persistence", "TodoCore"], path: "Tests/Scenario"),
    ]
)
