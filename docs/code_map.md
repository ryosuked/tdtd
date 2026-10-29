# コードの地図（レビューの手引き）

コードがどこにあり、何をしていて、どうつながっているかの案内。レビューの入口として使う。

- 仕様の正はこの文書ではない。データの形は [data_model_spec.md](data_model_spec.md)、できることは [requirements.md](requirements.md)
- 行番号は書かない（すぐずれるため）。型と関数の名前で指す
- 各ファイルの先頭に、役割と「レビューの観点」をコメントで書いてある。この文書はその索引
- Swift やネイティブアプリに詳しくなくても読めるように、コードのコメントと §6 の用語集で補っている

## 0. コメントの印

コードの中で、ぱっと見では「アプリの処理」か「書かないといけないだけのもの」か分からない定義には、行頭に印を付けている。

| 印 | 意味 | 例 |
|---|---|---|
| `Ceremony:` | Swift や SwiftUI・AppKit に求められて書いているだけで、アプリ独自の処理は含まない。読み飛ばしてよい | `public init`（値を入れるだけ）、`Codable` を付けるだけの型、`FileDocument` の形、`nonisolated let id`、`Package.swift` |
| `Wiring:` | 処理ではなく、部品どうしをつなぐだけ。決まりや処理の本体は、つなぎ先にある | `WorkspaceStore` の各操作（TodoCore を呼ぶだけ）、DTO への詰め替え、誤りの包み直し |
| （印なし） | アプリの処理や決まり。レビューで中身を見るところ | |

`Ceremony:` や `Wiring:` で検索すると、その箇所を一覧できる。

## 1. 全体の形

```text
App/TodoApp.swift                       入口だけ（ウィンドウを 1 つ出す・Mac の終了時の保存）
   │
   ▼
Packages/Features      状態と画面（SwiftUI）
   │   Stores/  AppModel ─ 持つ ─▶ WorkspaceStore（ワークスペースごとに 1 つ）
   │   Views/   RootView ▶ WorkspaceSidebar / WorkspaceView ▶ ColumnsView / ListModeView / TaskInspector
   ▼
Packages/Persistence   ファイルの読み書き・検証・置き場所
   │   WorkspaceCodec（JSON ⇔ 型、検証）  WorkspaceRepository（actor。ファイルに触るのはここだけ）
   ▼
Packages/TodoCore      純粋なロジック（Foundation だけに依存）
       Model（型） Operations（操作） TextRule・PlainText（文字列の決まり） Views（表示のための導出）
```

- 矢印は「依存する向き」。逆向きの依存は無い（TodoCore は何も知らない）
- 上の層ほど薄くする。決まり（検証・正規化・updatedAt）は TodoCore に置き、Features は呼ぶだけ

## 2. ファイルの一覧

ソースは 21 ファイル（App 1・TodoCore 7・Persistence 4・Features 9）。数は `.swift` の数で、各パッケージの `Package.swift`（設定だけ）は含まない。

### App（入口）— 1 ファイル

| ファイル | 中身 | 主な型 |
|---|---|---|
| `App/TodoApp.swift` | ウィンドウを作って RootView を出す。Mac では終了を保留して保存を書き切る | `TodoApp`、`AppDelegate` |

### TodoCore（純粋なロジック）— 7 ファイル

| ファイル | 中身 | 主な型・関数 | 関係する仕様 |
|---|---|---|---|
| `Model.swift` | データの型 | `Workspace`・`TodoCategory`・`TodoItem`・`CategoryColor` | spec §3 |
| `Operations.swift` | データを変える操作。すべて `update(now:_:)` を通る | `addTask`・`setContent`・`moveTask`・`deleteCategory` など、`Date.roundedToMilliseconds` | spec §4 |
| `TextRule.swift` | 文字列の決まり（長さ・改行・空白だけは不可） | `TextRule`・`TextRule.accept`・`EditError` | spec §3・§7 |
| `PlainText.swift` | 貼り付けで混ざる文字の正規化 | `PlainText.normalized` | spec §3.3 |
| `LocalDate.swift` | 日付だけの値（期限） | `LocalDate` | spec §3.2 |
| `Views.swift` | 表示のための導出（保存しない） | `DisplayMode`・`listSections`・`TodoItem.preview` | requirements F4 |
| `Copy.swift` | ID を振り直した複製（インポートの「複製として追加」） | `Workspace.withNewIDs` | spec §9 |

### Persistence（保存）— 4 ファイル

| ファイル | 中身 | 主な型・関数 | 関係する仕様 |
|---|---|---|---|
| `WorkspaceFile.swift` | JSON をそのまま受ける型（DTO）。版 1・版 2 | `WorkspaceFileDTO<Item>`・`TodoItemDTO`・`TodoItemV1DTO`・`WorkspaceFormat` | spec §2・§3 |
| `WorkspaceCodec.swift` | 読み書きと検証、版 1 からの移行、日時の書式 | `WorkspaceCodec.decode`・`encode`、`Validator`、`ISODate`、`WorkspaceFileError` | spec §3.2・§5・§10 |
| `WorkspaceRepository.swift` | ファイルの置き場所と入出力（actor） | `loadAll`・`save`・`readImportFile`・`saveAppState` | spec §1・§8 |
| `AppState.swift` | 表示の状態（端末ごと、エクスポートしない） | `AppState`・`WorkspaceViewState` | spec §6 |

### Features（状態と画面）— 9 ファイル（Stores 2・Views 7）

| ファイル | 中身 | 主な型 | 関係する要件 |
|---|---|---|---|
| `Stores/AppModel.swift` | アプリ全体の状態。一覧・表示の状態・誤りの表示・インポート・エクスポート | `AppModel` | F1・F5 |
| `Stores/WorkspaceStore.swift` | ワークスペース 1 つの操作の入口と、1 秒待ってからの保存 | `WorkspaceStore` | F2・F3・F6 |
| `Views/RootView.swift` | 画面の入口。読み込みの開始、インポートの確認、誤りのアラート | `RootView` | F5・F6 |
| `Views/WorkspaceSidebar.swift` | 左の一覧 | `WorkspaceSidebar` | F1 |
| `Views/WorkspaceView.swift` | 中央と右のペインの組み立て、ツールバー、書き出し | `WorkspaceView`・`JSONFileDocument` | F4・F5 |
| `Views/ColumnsView.swift` | 短冊表示 | `ColumnsView`・`CategoryColumn` | F4-1・F4-6 |
| `Views/ListModeView.swift` | 1 欄表示 | `ListModeView` | F4-2・F4-5 |
| `Views/TaskInspector.swift` | 右の詳細のペイン。Date ⇔ LocalDate の変換もここ | `TaskInspector`・`TaskDetail`・`DueEditor` | F4-9 |
| `Views/Components.swift` | 共通の部品 | `TaskRow`・`CategoryHeader`・`AddTaskField`・`renameAlert` | F3・F4-8 |

### テストと契約 — テスト 2 ファイル、fixtures 23 ファイル（valid 6・invalid 17）、スクリプト 2 ファイル

| 場所 | 中身 |
|---|---|
| `Packages/TodoCore/Tests/TodoCoreTests/OperationsTests.swift` | 操作・updatedAt・誤りの操作・冒頭の切り出し・文字列の決まり・正規化・日付 |
| `Packages/Persistence/Tests/PersistenceTests/WorkspaceCodecTests.swift` | fixtures を読む。往復の一致・版 1 からの移行・正規化・誤りのファイル・書く前の確かめ・退避 |
| `fixtures/valid/` | 正しいファイル。`basic.json`（版 2）、`v1-*.json`（版 1）、`*-needs-normalize*.json`（正規化の前と後） |
| `fixtures/invalid/` | 誤りのファイル。名前の先頭が検証の番号（`V1-`〜`V6-`）。1 つのファイルで 1 つの決まりだけを破る |
| `scripts/test-all.sh` | 全部のテストと、macOS 向けのアプリのビルド |
| `scripts/build-release.sh` | ほかの Mac へ持っていく用の Release ビルドと zip（[dev_environment_setup.md](dev_environment_setup.md) §5） |

Features にはまだテストが無い。

## 3. 処理の流れ

### 3.1 起動して読み込む

1. `TodoApp`（App）が `AppModel.live()` で AppModel を作り、`RootView` を出す
2. `RootView` の `.task` が `AppModel.load()` を呼ぶ
3. `WorkspaceRepository.loadAll()` が `workspaces/*.json` を 1 つずつ `WorkspaceCodec.decode` で読む
   - 読めないファイルは `damaged/` へ移し、名前だけを返す（上書き・削除はしない）
   - `app_state.json` は読めなければ初めの値にする
4. `AppModel` がワークスペースごとに `WorkspaceStore` を作り、最後に開いていたものを選ぶ。退避したファイルがあれば `errorMessage` で知らせる

### 3.2 操作して保存する（例: タスクを足す）

1. 画面（`AddTaskField`）が `WorkspaceStore.addTask(content:to:)` を呼ぶ
2. `WorkspaceStore.apply` が、`workspace` の複製に `Workspace.addTask`（TodoCore）を当てる
3. `Workspace.addTask` が `TextRule.accept` で、正規化（`PlainText`）してから決まりを確かめる
   - 誤りなら `EditError` を投げる → `apply` は何も変えずに `onError`（→ `AppModel.errorMessage`）で知らせ、`false` を返す → 入力欄は入力を残す
4. 決まりに合えば `Workspace.update(now:_:)` が変更を当て、値が変わったときだけ `updatedAt` を進める
5. `apply` が `workspace` を差し替え、`scheduleSave()` で 1 秒の待ちを始める（次の変更が来たら待ち直す）
6. 待ちが終わると `WorkspaceRepository.save` → `WorkspaceCodec.encode`（書いた結果を読み直して確かめる）→ `.atomic` で書く

### 3.3 インポート

1. `WorkspaceSidebar` の「読み込む」→ `RootView` の `.fileImporter` → `AppModel.importFile(at:)`
2. `WorkspaceRepository.readImportFile` が大きさ（20 MB まで）を見てから `WorkspaceCodec.decode`。版 1 はここで版 2 に移る
3. 同じ ID が無ければそのまま足す。あれば `pendingImport` に置き、`RootView` の確認で選ぶ
   - 置き換える → `WorkspaceStore.replace(with:)`
   - 複製として追加 → `Workspace.withNewIDs` で ID を振り直して足す

### 3.4 エクスポート

`WorkspaceView` の「書き出す」→ `AppModel.exportData` → `WorkspaceCodec.encode`（保存と同じ確かめを通る）→ `.fileExporter`。表示の状態は含めない。

### 3.5 背面に回る・終了する

- 背面に回ったとき: `RootView` の `scenePhase` の監視 → `AppModel.flushAll()` → 各 `WorkspaceStore.flush()`
- Mac で終了するとき: `AppDelegate.applicationShouldTerminate` が終了を保留 → `flushAll()` → 終了を許す

## 4. 決まりがどこで守られているか

| 決まり | 守っている場所 | 確かめているテスト |
|---|---|---|
| 文字列の長さ・改行・空白だけは不可 | `TextRule`（操作と読み込みの両方から呼ばれる） | `TextRuleTests`・`invalidTextIsRejectedWithoutChange`・`rejectsInvalidFile`（V5） |
| 貼り付けで混ざる文字の正規化 | `PlainText.normalized`（`TextRule.accept` の中） | `PlainTextTests`・`normalizesTextOnRead` |
| 誤りの操作でデータを変えない | `TextRule` の確かめを変更の前に置く・`WorkspaceStore.apply` は複製に当てる | `invalidTextIsRejectedWithoutChange` |
| updatedAt は値が変わったときだけ | `Workspace.update(now:_:)` | `noChangeKeepsUpdatedAt` |
| 日時はミリ秒に丸める | `Date.roundedToMilliseconds`、`ISODate` | `nowIsRoundedToMilliseconds`・`roundTripKeepsJSONValue` |
| ID の重複を許さない | `Validator.id`（`seenIDs`） | `rejectsInvalidFile`（V6） |
| 自分で読めないファイルを書かない | `WorkspaceCodec.encode` の読み直し | `WriteCheckTests` |
| 読めないファイルを上書きしない | `WorkspaceRepository.loadAll` の退避 | `saveLoadAndQuarantineDamaged` |
| 中核は現在時刻と乱数を呼ばない | TodoCore の操作は `now`・`id` を引数で受け取る。作るのは `AppModel`・`WorkspaceStore` | テストは `Fixed` の値を渡している |

## 5. レビューの進め方（おすすめ）

内側から外側へ読むと、前提が先に分かる。

| 順 | 読むもの | 見るところ |
|---|---|---|
| 1 | `docs/data_model_spec.md` §1〜§5 | データの形と決まり（以降のコードの前提） |
| 2 | TodoCore の `Model` → `TextRule`・`PlainText` → `Operations` | 操作が仕様 §4 の表どおりか。外の状態に触っていないか |
| 3 | TodoCore のテスト | 仕様の決まりがテストで押さえられているか |
| 4 | Persistence の `WorkspaceFile` → `WorkspaceCodec` → `WorkspaceRepository` | 検証の V1〜V6 の置き場所（`WorkspaceCodec.swift` の先頭のコメント）、移行、退避 |
| 5 | `fixtures/` と Persistence のテスト | 誤りの例が 1 つずつ決まりを破っているか |
| 6 | Features の `WorkspaceStore` → `AppModel` | ロジックを持たずに呼ぶだけになっているか。保存の待ち合わせで変更を取りこぼさないか |
| 7 | Features の `Views/` | 誤りの表示が 1 か所か。iPadOS に無い API（AppKit など）を使っていないか |

### 共通の観点

- Swift 6 の並行処理の決まり: 画面と Store は `@MainActor`、ファイルは actor（`WorkspaceRepository`）。`@unchecked Sendable` は使わない
- 対象 OS: macOS 14 以降。それより新しい API や `#available` の分岐が入っていないか（[dev_environment_setup.md](dev_environment_setup.md)）
- 上限や待ち時間の値に、根拠のコメントがあるか

## 6. Swift・SwiftUI の用語（読むための最小限）

コードのコメントでも、各ファイルで最初に出た箇所に一言で書いている。ここはまとめ。

### 言語

| 用語 | 意味 |
|---|---|
| `struct`（値型） | 代入や引数で渡すとコピーされる型。コピーを書き換えても元は変わらない。データの型（`Workspace` など）はすべてこれ |
| `class`（参照型） | コピーされず、どこから見ても同じ 1 つを指す型。画面の状態（`AppModel`・`WorkspaceStore`）に使う |
| `enum` | 決まった選択肢のどれか 1 つを表す型。選択肢（case）の無い enum は「関数の入れ物（名前空間）」として使う |
| `extension` | 既にある型に、別の場所から関数を足す書き方 |
| プロトコル（`Equatable` など） | 型が守る約束。型名の後ろに並べる。多くは Swift が中身を自動で作る |
| `?`（Optional）・`nil` | 値が無いこともある。`if let`・`guard let` で「あれば取り出す」 |
| `guard 条件 else { return }` | 条件に合わなければ、そこで抜ける |
| `mutating` | 値型の中で、自分自身を書き換える関数の印 |
| `inout` | 受け取った値を、関数の中で書き換えてよい引数 |
| `throws`・`try`・`do`/`catch` | 失敗すると誤りを投げる関数。呼ぶときに `try`。`throws(EditError)` は投げる誤りの型が決まっている |
| `try?` | 誤りなら nil にする |
| クロージャ（`{ ... }`）・`$0` | その場で書く小さな関数。`$0` は 1 番目の引数 |
| `init?` | 作れないことがある初期化。作れなければ nil |
| `static` | 型に 1 つだけある値・関数（1 件ごとではない） |
| 型引数（`<Item>`） | 中に入る型を、使う側で差し込む |
| `defer` | そのブロックを抜けるときに必ず実行する |
| `#if os(macOS)` | Mac でビルドするときだけ入るコード |

### 並行処理（スレッド）

| 用語 | 意味 |
|---|---|
| `async`・`await` | 途中で待つことがある関数と、その待ち。待つ間も画面は止まらない |
| `Task { }` | 後ろで非同期に動かす。呼んだ側は待たずに次へ進む |
| `actor` | 同時に 1 つの処理しか中に入れない入れ物。`WorkspaceRepository` がこれで、ファイルの書き込みが重ならない |
| `@MainActor` | 画面と同じ流れ（メインスレッド）でだけ動く。画面の状態を持つクラスに付ける |
| `Sendable` | スレッドをまたいで安全に渡せる、という約束 |
| `nonisolated` | `@MainActor` の型の中でも、ほかのスレッドから読めるようにする印 |
| `[weak self]` | クロージャがオブジェクトを掴みっぱなしにして、互いに消えなくなるのを防ぐ書き方 |

### SwiftUI（画面）

| 用語 | 意味 |
|---|---|
| `View`・`body` | 画面の部品と、その中身。使っている値が変わるたびに `body` が呼び直される |
| 修飾子（`.alert(...)` など） | 部品に見た目や動きを足す。上から順に包む |
| `@State` | その画面だけが持つ値 |
| `@Binding` | 親の画面が持つ値を借りて読み書きする |
| `@Observable` | 中の値が変わると、それを使う画面が自動で描き直されるクラスの印 |
| `@ObservationIgnored` | 変わっても描き直しに関係ない値の印 |
| `@Bindable` | `@Observable` の値の項目を、入力欄や選択に結びつける印 |
| `Binding(get:set:)` | その場で作る読み書きの口 |
| `.task`・`.onChange` | 画面が出たとき・値が変わったときに処理を始める |
| `.id(値)` | 値が変わると部品を作り直す（`@State` も初期値に戻る） |

### このアプリの言葉

| 用語 | 意味 |
|---|---|
| ドメインの型 | アプリの中で扱うデータの型（TodoCore の `Workspace`・`TodoCategory`・`TodoItem`） |
| DTO | ファイルの JSON をそのまま受けるための型（Persistence の `WorkspaceFile.swift`）。検証してからドメインの型に変える |
| Store | 画面とデータをつなぐ状態の持ち主（`AppModel`・`WorkspaceStore`）。処理は持たず TodoCore を呼ぶ |
| 正規化 | 貼り付けで混ざる改行の種類や見えない文字をそろえること（`PlainText`） |

## 7. 分かっている問題

レビューで見つけた問題と、後回しにしたことは [OPEN_ITEMS.md](../OPEN_ITEMS.md) にまとめてある。ここには書かない。

## 8. この文書の直し方

ファイルや主な型を足した・消した・名前を変えたときに、§2 の表とファイル数を直す。流れ（§3）や決まりの置き場所（§4）を変えたときも、同じ変更の中で直す。
