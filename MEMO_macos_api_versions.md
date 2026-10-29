# メモ: macOS の最小の版と API（2026-10-24）

macOS の最小を 26 から 14 に下げたときに確かめたことの走り書き。決まったことの正は [dev_environment_setup.md](docs/dev_environment_setup.md) §1。

- API の版は、Apple の文書ではなく知識をもとに書いた。採るときは文書で確かめる
- SDK 27（macOS 27）の API は確かな形で把握していないので、入れていない

## 1. 14 に下げて除外した API

無い。コードは 1 行も変えていない。

| 確かめたこと | 結果 |
|---|---|
| 最小 14 でのビルド | 誤りも警告も出なかった。最小より新しい API を使うと、コンパイラが誤りにする |
| `#available`・`@available` の分岐 | 無い（分岐から外したものも無い） |
| 新しめのもの | 型付きの throws（Swift 6）、`Sequence.count(where:)`、`Task.sleep(for:)`（13）、`@Observable`・`.inspector`（14）はどれも通った |
| できたアプリの最小 OS | `minos 14.0`、`LSMinimumSystemVersion 14.0` |

`.toggleStyle(.checkbox)` を外したのは版のためではなく、iPadOS に無い API だったから。

### 14 にしたことで起きること

| 事項 | 中身 |
|---|---|
| これから使えない API | Mac と共有するコードでは、macOS 15〜26 で増えた API を使えない |
| 見た目は OS ごとに変わる | SDK 27 でビルドしているので、macOS 26 では Liquid Glass が自動で付き、14・15 では従来の見た目になる |
| 動きの違いは、コンパイラでは見つからない | 入力欄の Return、右のペインの幅や出し入れなどは、14・15 の上で動かすまで分からない（[OPEN_ITEMS](OPEN_ITEMS.md)） |

## 2. 15 以降の API で、今の機能に使う意味のあるもの

今の機能では無い。候補は、予定のドラッグ＆ドロップの 1 つだけ。

### 今の機能

| 機能 | 15 以降の API | 使う意味 |
|---|---|---|
| 保存・読み込み（JSON） | macOS 15 で Foundation の JSONEncoder／JSONDecoder が Swift で書き直され、速くなった | API ではなく実行時の改善。最小 14 のままでも、15 以降の Mac では自動で効く |
| 保存の待ち合わせ | `Observations`（26） | 今の「操作のたびに `scheduleSave()`」で足りる |
| `app_state.json` の書き込みの順 | `Mutex`（15） | actor で 1 本の列に並べれば済む |
| 右のペインの編集 | `TextEditor` の書式付きテキスト（26）、`TextField` の選択範囲（15） | 中身は書式なしの文字列だけと決めた（requirements F3-1）ので要らない。貼り付けの対策は data_model_spec §3.3 |
| 見た目 | `.glassEffect` など（26） | macOS 26 では自動で付く。自分で指定する場面は無い |
| ウィンドウ | 初めの位置・大きさの指定など（15） | あれば少し便利という程度 |

### 予定の機能

| 予定の機能 | 15 以降の API | 判断 |
|---|---|---|
| ドラッグでの並べ替え・カテゴリ間の移動 | 複数の項目をまとめてドラッグする仕組み（`dragContainer` など）、ドラッグ中の状態の受け取り（26） | **唯一の候補。** 1 件ずつなら 13 からある `.draggable`／`.dropDestination` と `List` の `.onMove` で作れる。まとめて動かしたくなったら、最小を上げるかをそのとき決める |
| 1 欄表示でカテゴリを畳む | `Section(isExpanded:)` は 14 からある | 最小 14 のままで作れる |
| Mac のキーボード操作 | `.onKeyPress` は 14 から。修飾キーで変わるメニュー項目などは 15 | 基本の操作は 14 で作れる |
| 取り消し（Undo） | `UndoManager` は以前からある | 版は関係ない |
