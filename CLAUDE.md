# CLAUDE.md

このリポジトリで作業するときの決まり。ワークスペース → カテゴリ → タスクの 3 段で管理する Todo アプリを、Swift のネイティブアプリとして作っている。

## 0. このリポジトリ

| 場所 | 中身 |
|---|---|
| `docs/` | 要件・仕様・ADR。入口は [requirements.md](docs/requirements.md) |
| [docs/code_map.md](docs/code_map.md) | コードの地図（ファイルの役割・処理の流れ・決まりの置き場所）。レビューの入口 |
| `OPEN_ITEMS.md` | 未決・仮決めの事項。ここ 1 か所にまとめる |
| `App/`・`Packages/`・`Todo.xcodeproj` | アプリ本体（§6.1） |
| `fixtures/` | ワークスペースのファイルの正解例（`valid/`）と誤り例（`invalid/`）。保存形式の契約（§4） |
| `scripts/` | テストとビルドを横断して流すスクリプト |

- 進み具合はこのファイルに書かない
- `APP_CLAUDE.md`・`DEVELOP_CLAUDE.md` は、ほかのプロジェクトから持ってきた参考の資料。この CLAUDE.md の元にしたもので、ここでの決まりではない

## 1. 進め方

- **設計・企画は熟考する**: 前提・選択肢・利点と欠点・決めるべきことを考えてから答える。判断は資料と既存のコードを読んで机上で行うのが基本
- **動かして試すのは確認してから**: 試作・ライブラリを入れて試す・検証用のスクリプトを流すことが選択肢に入るときは、何をどう確かめるかを短く伝えて、必要かどうかを先に聞く。既存のテスト（`swift test`・`xcodebuild test` の単体テスト）は確認なしで流してよい。シミュレータ・実機での実行と XCUITest は頼まれたときだけ
- **大きなデータの取得は先に確認する**（目安: 数十 MB 以上、または量が読めないもの）: Xcode のプラットフォーム・シミュレータランタイム（数 GB）、Xcode 本体やツールチェーン、外部の Swift パッケージの取得。何をどのくらい取るかを伝えて可否を聞き、断られたら保留にする。手元のキャッシュで済む操作・Web の検索は確認不要。迷ったら確認する
- **実装は骨組みから**: 構成・ファイルの分け方・処理の流れ・つなぎ目を先に作って動く形にし、細部（作り込み・例外処理・周辺の整備）はあとで詰める。骨組みの段階で方向を確かめてもらう。これは順番の話で、仕上げを頼まれたら細部まで詰めて完遂する
- **仮決めの上に積みすぎない**: `OPEN_ITEMS.md` の仮決めに乗る作業は、乗っていることを伝えてから進める
- **コミットは頼まれたときだけ**

## 2. 設計の考え方

- **中核は純粋に保つ**: データの更新・検証・並び順の導出は、副作用のない関数と値型で書く。現在時刻・ID の生成・ファイルの入出力は引数か差し替え口（プロトコル）で渡し、テストでは偽物に替える。Store にロジックを書かない（配線だけ）
- **状態を持たない作りを優先する**: 導き出せるもの（1 欄表示の並び、件数など）は保存しない。保存するときは、それで何を得るかを書く
- **選べる方式を増やし過ぎない**: 比べるために残した方式は、決着したら ADR に残して外す
- **責務と負荷で分ける**: エンコード・書き込み・読み込みは MainActor の外で行う。UI の応答経路に `await` を置かない
- **上限と時間の値は根拠を書く**: 例: インポートの上限 20 MB（性能目安 5,000 件 ≒ 2 MB の 10 倍）、保存の待ち 1 秒（入力のたびにファイルを書かないため）。仕様書に根拠と一緒に書く
- **データを失わせない**: 読めないファイルは上書きせず退避する。書き込みは原子的に行う。削除には確認を挟む
- **画面は迷わせない**: Apple の HIG に従う。タッチのヒット領域は 44pt 以上。誤りは 1 か所に出す。出す情報は必要なものだけ

## 3. 言語・ツール・依存

- **Swift**（Xcode 付属の最新安定版）を Swift 6 言語モード（Strict Concurrency 完全）で使う。`@unchecked Sendable` は使わない（使うなら ADR）。強制アンラップ（`!`）と `Any` は避ける
- **UI は SwiftUI**。AppKit / UIKit へのフォールバックは ADR を書いてから
- **対象 OS は、プラットフォームごとに最小の版を 1 つ決める**: macOS 14 以降、iPadOS 26 以降（iOS も 26 以降の予定）。最小の版より新しい API は使わず、`#available` などの分岐を書かない。macOS と iPadOS で共有するコード（Features 以下）は、実質 macOS 14 の API に縛られる（[dev_environment_setup.md](docs/dev_environment_setup.md)）
- **画面は macOS と iPadOS の両方を対象に設計する。ビルドと動作の確認は、今は macOS だけ**。Features では iPadOS でも使える SwiftUI の API を使い、AppKit に頼らない
- **Apple 公式のツールだけで完結させる**（Xcode / swift / xcodebuild）。プロジェクト生成ツール（XcodeGen・Tuist）や SwiftLint は入れない。フォーマッタは Xcode 内蔵の swift-format。依存を足すなら ADR に書き、最終の更新・リリースの頻度・メンテナーの数を確かめる
- **保存は Foundation だけで行う**（JSON ＋ `Codable`）。SwiftData・Core Data は使わない（[ADR-0001](docs/adr/0001-storage-and-structure.md)）
- **版と更新の手順**: 使った Xcode の版、対象 OS と swift-tools-version を上げる手順は [dev_environment_setup.md](docs/dev_environment_setup.md) に書く
- **公開する API と込み入った処理には DocC の書式でコメントを書く**。コメントは日本語

## 4. テスト

- **Swift は swift-testing**。TodoCore・Persistence は、ソースの**各ファイル**の行カバレッジを 90% 以上にする（細部のテストで測る。`test.sh detail` は下回ると失敗する）
- **テストは 2 種類に分け、フォルダ（テストのターゲット）も分ける**。`scripts/test.sh scenario|detail|all` で選んで流す

| 種類 | 置き場所 | 見るもの | 見ないもの |
|---|---|---|---|
| シナリオ | `Packages/Features/Tests/Scenario/` | 道具としての一連の流れ（作る → 編集 → 保存 → 起動し直す → 書き出し・読み込み など）。AppModel・WorkspaceStore を画面と同じ呼び方で動かす | 細かい値・表記・誤りの場所や文言 |
| 細部 | `Packages/<パッケージ>/Tests/Detail/` | 値・表記・検証の場所と理由・正規化の表など。カバレッジはこちらで満たす（`test.sh detail` が % を出す） | 部品をまたぐ流れ |

- 流れを足したら（新しい機能の操作など）シナリオに 1 本足す。決まりや表記を足したら細部に足す
- **`fixtures/` が保存形式の契約**: 正しいファイル（読んで書くと JSON の値として一致する）と、誤りのファイル（検証の V1〜V6 をそれぞれ 1 つずつ破ったもの）を置く。仕様を変えるときは「仕様書 → fixtures → 実装」の順で直す
- **バグを直すときは、再現するテストを先に足す**
- **テストは外に通信しない**（アプリ自体も通信しない）。時計と ID の生成は偽物に替え、結果を決まった値にする
- **確かめたことと確かめていないことを分けて書く**: ドラッグの操作感・各端末のレイアウト・共有シートやファイルの保存の経路など、実機やシミュレータでしか確かめられないことは、手動の確認の一覧に載せる（必要になったら `docs/manual_checklist.md` を起こす）

## 5. ドキュメント

- **平易な日本語で書く**。文は短く、表を使う
- **読めば分かることは書かない**。件数や進み具合など、すぐ古くなる値をこのファイルに書かない
- **どの文書が正か**（食い違ったら負けた側を直す）:

| 対象 | 正 |
|---|---|
| できること・対象外 | [requirements.md](docs/requirements.md) |
| データ形式・検証・保存の手順 | [data_model_spec.md](docs/data_model_spec.md) |
| 設計の判断 | `docs/adr/` |
| 未決・仮決め | [OPEN_ITEMS.md](OPEN_ITEMS.md) |

- **未決・矛盾は `OPEN_ITEMS.md` に集める**。ほかの文書には「未決（OPEN_ITEMS #n）」とだけ書く。決まったら該当する文書を直して、OPEN_ITEMS から消す
- **今と違う案は別の文書にする**: 既存の文書を書き換えず、案の文書を起こしてリンクする。採ったら元の文書に「採った形」とリンクを足す
- **設計の判断は ADR に残す**（背景・選択肢・決定・理由・影響。採った案と採らなかった案を表にし、その形で失うものを書く）
- **文書を増やし過ぎない**。選択肢を外すときは、文書もあわせて減らす
- **コードの地図を保つ**: ファイルや主な型を足す・消す・名前を変えるときは、同じ変更の中で [code_map.md](docs/code_map.md) を直す。各ファイルの先頭には、役割と「レビューの観点」をコメントで書く
- **コメントは Swift に詳しくない人にも読めるように書く**: Swift・SwiftUI の書き方は、そのファイルで最初に出た箇所に一言で意味を添える（まとめは code_map §6）。冗長にしない。ぱっと見で処理か分からない定義には印を付ける: 言語や SwiftUI に求められて書くだけのものは `Ceremony:`、部品をつなぐだけのものは `Wiring:`
- 状態の印は ✅ 完了・確定／🟡 途中・仮決め／⏳ 未着手／❌ 対象外

## 6. プロジェクト固有

### 6.1 構成

```text
<リポジトリのルート>/
├── Todo.xcodeproj         # 手書き。App/ はフォルダ同期なので、ファイルを足してもプロジェクトを直さなくてよい。名前は仮（OPEN_ITEMS #8）
├── App/                   # 入口だけ（薄く）。#if os() はここと Features のファイル分割にだけ使う
├── Packages/              # SPM ローカルパッケージ
│   ├── TodoCore/          # 純粋ロジック（型・操作・1 欄表示の並びの導出）。Foundation だけに依存
│   ├── Persistence/       # JSON の読み書き・検証・ファイルの置き場所・表示の状態（AppState）
│   └── Features/          # Store（AppModel・WorkspaceStore）と画面。DesignSystem は必要になったら分ける
└── scripts/
    ├── test.sh            # テストを種類ごとに選んで流す（scenario・detail・all）
    ├── test-all.sh        # 全部のテスト＋macOS 向けのアプリのビルド
    └── build-release.sh   # ほかの Mac へ持っていく用の Release ビルドと zip
```

- **依存の向き**（逆流禁止）: App → Features → Persistence → TodoCore。TodoCore は何にも依存しない
- **状態**: `AppModel`（`@Observable`・`@MainActor`）がワークスペースの一覧・表示の状態・誤りの表示を持つ。`WorkspaceStore`（開いているワークスペースごとに 1 つ）が値型の `Workspace` を持ち、更新は TodoCore の操作を呼ぶだけ。保存は 1 秒待ってから `WorkspaceRepository`（actor）で書く。ワークスペースのファイルを書くのは `WorkspaceStore` の保存だけ（AppModel は書かない。古い中身で上書きしないため）。AppModel が後ろで動かす入出力（削除・表示の状態）は 1 本の列に並べ、`flushAll` で待てる
- **プラットフォーム**: 画面は Mac と iPad を対象に設計する。ビルドと確認は今は Mac だけ。基準の端末は未決（OPEN_ITEMS #1）。iPhone は後で足すので、レイアウトには手を付けない

### 6.2 守る決まり（詳しくは [data_model_spec.md](docs/data_model_spec.md)）

1. **入れ子の構造**: workspace → categories[] → tasks[]。並び順は配列の順そのもので、`order` の欄を持たない。1 欄表示の並びは導き出す（保存しない）
2. **型の名前**: `Workspace`・`TodoCategory`・`TodoItem`。`Task` は Swift の並行処理と、`Category` は ObjectiveC モジュールの型とぶつかるので使わない（JSON のキーは仕様どおり）
3. **中核は現在時刻を呼ばない**: `now` を引数で受け取り、ミリ秒に丸めて打つ。ID も引数で受け取る（生成は Store が差し替え口から行う）
4. **`updatedAt` はワークスペースだけが持つ**。どの変更でも `now` にする。同期をしないので、カテゴリとタスクには持たせない
5. **完了は `completedAt` 1 つで表す**。`isDone` を別に持たない
6. **期限は日付だけ（`LocalDate`）**。`Date` にしない（タイムゾーンで日付がずれるため）
7. **色はパレット名**で持つ。16 進の色値にしない

### 6.3 データとファイル互換

- スキーマの正は [data_model_spec.md](docs/data_model_spec.md)（`format: "todo-workspace"`、`schemaVersion: 2`。版 1 は読むときに移す）
- **同期はしない**。データの受け渡しはインポート・エクスポートだけ
- 保存のファイルとエクスポートのファイルは同じ形式（整形した JSON のテキスト）。表示の状態はエクスポートしない。YAML にしないのは、Foundation で読み書きできず、外部の依存が要るため
- 検証は厳しく: 範囲外・書式違い・ID の重複は**誤り**にする（丸めない・勝手に直さない）。知らない項目は捨てる。アプリより新しい `schemaVersion` は拒否する
- **互換の定義**: 正しいファイルを読んで書いた結果が、JSON の値として一致すること。バイト単位の一致ではない
- 検証は「ファイル用の型（DTO）→ ドメインの型」の変換の中で行い、ドメインの型には誤りの状態を持ち込まない
- **文字列の決まり（長さ・改行・空白だけは不可）は TodoCore の `TextRule` 1 か所に置く**。読み込みの検証と操作の両方がこれを使う。操作は決まりに合わなければ誤りを投げ、データを変えない
- **自分で読めないファイルを書かない**: 保存とエクスポートは、エンコードした結果を読み込みの検証にかけてから書く
- **スキーマを変えるとき**: `schemaVersion` を上げ、data_model_spec に変更履歴と移行の規則を同じ変更で書き、fixtures と実装を合わせて直す

### 6.4 コマンド

```bash
./scripts/test.sh scenario                # シナリオだけ（一連の流れ。数秒）
./scripts/test.sh detail                  # 細部だけ（値・表記まで。カバレッジも出す）
./scripts/test.sh                         # 両方
./scripts/test-all.sh                     # 両方＋macOS 向けのアプリのビルド
cd Packages/TodoCore && swift test        # パッケージ単位（Persistence も同じ。Features はシナリオ）
open .build/DerivedData/Build/Products/Debug/Todo.app   # test-all.sh のビルドを起動する
./scripts/build-release.sh                # ほかの Mac 用: .build/release/Todo.zip を作る
```

- ほかの Mac で開くときの手順と制約は [dev_environment_setup.md](docs/dev_environment_setup.md) §5

- データの置き場所（サンドボックスの中）: `~/Library/Containers/com.example.Todo/Data/Library/Application Support/Todo/`
