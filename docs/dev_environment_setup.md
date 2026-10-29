# 開発環境

## 1. 使っている版

| 項目 | 版 | 決め方 |
|---|---|---|
| Xcode | 27.1（27A9275） | 手元のもの |
| Swift | 6.4（言語モードは Swift 6） | Xcode 付属 |
| macOS SDK | 27.0 | Xcode 付属 |
| 開発機の macOS | 26.6 | |
| 対象 OS（最小） | macOS 14.0／iPadOS 26.0（iOS も 26.0 の予定） | macOS は、少し前の Mac も使えるようにするため。14 にしたのは、使っている API（`@Observable`・`.inspector`・`ContentUnavailableView` など）がそろう最初の版だから。13 以前は Store の仕組みと右のペインの作り直しが要る |
| swift-tools-version | 6.2 | `.iOS(.v26)` が書ける版 |

## 2. プロジェクトの作り

| 項目 | 内容 |
|---|---|
| `Todo.xcodeproj` | 手で書いた。Xcode 16 以降の形式（objectVersion 77）で、`App/` をフォルダ同期にしている。ファイルを足しても `project.pbxproj` を直さなくてよい |
| パッケージの参照 | アプリのターゲットは `Packages/Features` だけを参照する。TodoCore と Persistence は Features 経由で入る |
| 署名 | アドホック署名（`CODE_SIGN_IDENTITY = "-"`）。ほかの Mac では Gatekeeper に止められる（§5）。配布するときはチームを決めて Automatic にする（OPEN_ITEMS #8） |
| サンドボックス | 有効。利用者が選んだファイルの読み書き（インポート・エクスポート）だけを許す |
| Bundle ID | `com.example.Todo`（仮。OPEN_ITEMS #8）。変えるとデータの置き場所（`~/Library/Containers/<Bundle ID>/`）も変わる |

## 3. 既知の警告

`xcodebuild` を流すと、`DVTCoreDeviceCore` の読み込みの失敗と「CoreSimulator is out of date」が出る。Xcode 27 と macOS 26 の組み合わせによるもので、macOS 向けのビルドには響かない。iPad のシミュレータを使うときは、macOS を上げるか、Xcode の追加のコンポーネントを入れる必要がある（数 GB の取得になるので、そのときに確認する）。

## 4. 版を上げるとき

1. Xcode を上げたら、§1 の表を直す
2. 対象 OS を変えるときは、`Packages/*/Package.swift` の `platforms` と、`project.pbxproj` の `MACOSX_DEPLOYMENT_TARGET`（2 か所）を合わせて直す。`#available` の分岐は書かない。macOS の最小を上げるのは、使いたい API が最小の版に無いときだけ（理由を表に書く）
3. `./scripts/test-all.sh` が通ることを確かめる
4. 作ったアプリの最小 OS は `vtool -show-build .build/DerivedData/Build/Products/Debug/Todo.app/Contents/MacOS/Todo` の `minos` で確かめる

## 5. ほかの Mac へ持っていく

`./scripts/build-release.sh` で、持っていく用のビルドを作る。`.build/release/Todo.zip`（中は `Todo.app`）をコピーして、先方で展開する。

| 項目 | 内容 | 理由 |
|---|---|---|
| 構成 | Release | デバッグビルドは中身が `Todo.debug.dylib` に分かれていて、持ち運びに向かない |
| CPU | arm64 と x86_64 の両方（ユニバーサル） | Intel の Mac でも macOS 14 なら動かせるようにするため |
| 最小 OS | macOS 14.0 | §1 |
| 権限 | サンドボックスと、利用者が選んだファイルの読み書きだけ | Xcode が足すデバッガ用の権限（`get-task-allow`）は、スクリプトで抜いて署名し直す |
| 署名 | アドホックのまま。公証（notarization）なし | Developer ID には Apple Developer Program（有料）の登録が要る（OPEN_ITEMS #8） |

### 先方の Mac で「検証できない」と言われたとき

AirDrop・ダウンロード・メールで受け取ったファイルには「ネットから来た」印（`com.apple.quarantine`）が付く。アドホック署名のアプリはこの印があると開けない。次のどれかで開く（初回だけ）。

1. 一度開こうとして止められたあと、「システム設定」→「プライバシーとセキュリティ」の下に出る「このまま開く」を押す（macOS 15 以降はこの方法）
2. macOS 14 なら、Finder で右クリック（Control＋クリック）→「開く」→ 確認でもう一度「開く」
3. ターミナルで印を外す: `xattr -dr com.apple.quarantine /Applications/Todo.app`（パスは置いた場所に合わせる）

- データは Mac ごとに別（サンドボックスの中）。中身を移すときは、ワークスペースをエクスポートして先方でインポートする
- 毎回この手順を踏まずに配るには、Developer ID の署名と公証が要る
