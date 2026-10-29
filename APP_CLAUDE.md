# CLAUDE.md

このリポジトリで作業するときの決まり。外部の MIDI 音源を鳴らすステップシーケンサー（メロディー＋コード）を作っている。

## 0. このリポジトリ

- **Phase 2 = Web 版**（`src/`。ビルドなしの vanilla JS）。仕様とデータモデルを実証して凍結するための**参照実装**。凍結待ち（残りは実機確認 6f）。移植を始めたら、Web 版はバグ修正だけにする
- **Phase 3 = ネイティブアプリ**（`native/`。Swift 6 / SwiftUI / CoreMIDI。iPad ファースト）。**これからの主な作業**。`native/` はまだ無く、[dev_environment_setup.md](docs/phase3/dev_environment_setup.md) の手順で作る
- 進み具合はこのファイルに書かない。見る場所: Phase 2 は [cost_estimate.md](docs/phase2/cost_estimate.md)「凍結までの計画」、Phase 3 は [migration_plan.md](docs/phase3/migration_plan.md) §3、全体は [ROADMAP.md](docs/ROADMAP.md)

| 場所 | 中身 |
|---|---|
| `native/` | ネイティブアプリ（Xcode プロジェクト＋SPM ローカルパッケージ） |
| `src/` `tests/` | Web 版と、そのテスト（Vitest） |
| `fixtures/` | 両実装で共有する正解データ。**実装間の契約**（§4） |
| `docs/` | 仕様・設計。入口は [docs/README.md](docs/README.md) |
| `manual/` | 実機での手動確認の手順とチェックリスト |

## 1. 進め方

- **設計・企画は熟考する**: 前提・選択肢・利点と欠点・決めるべきことを考えてから答える。判断は資料と既存のコードを読んで机上で行うのが基本
- **動かして試すのは確認してから**: 試作・ライブラリを入れて試す・検証用のスクリプトを流すことが選択肢に入るときは、何をどう確かめるかを短く伝えて、必要かどうかを先に聞く。既存のテスト（`npm test`・`swift test`）は確認なしで流してよい。シミュレータ・実機での実行と XCUITest は頼まれたときだけ
- **大きなデータの取得は先に確認する**（目安: 数十 MB 以上、または量が読めないもの）: Xcode のプラットフォーム・シミュレータランタイム（数 GB）、Xcode 本体やツールチェーン、キャッシュのない `npm ci`、外部の Swift パッケージの取得、大きなリポジトリの clone。何をどのくらい取るかを伝えて可否を聞き、断られたら保留にする。手元のキャッシュで済む操作・Web の検索は確認不要。迷ったら確認する
- **実装は骨組みから**: 構成・ファイルの分け方・処理の流れ・つなぎ目を先に作って動く形にし、細部（作り込み・例外処理・周辺の整備）はあとで詰める。骨組みの段階で方向を確かめてもらう。これは順番の話で、仕上げを頼まれたら細部まで詰めて完遂する
- **コミットは頼まれたときだけ**

## 2. 設計の考え方

- **中核は純粋に保つ**: 状態の更新・コード展開・時刻計算は、副作用のない関数と値型で書く。UI・MIDI の入出力・時計・乱数は差し替え口（プロトコル）越しに渡し、テストでは偽物に替える。Store にロジックを書かない（配線だけ）
- **選べる方式を増やし過ぎない**: 比べるために残す方式（書類の方式・描画方式など）は早期スパイクで決めて ADR に残し、決まったら外す。早期スパイクの ADR が出る前に方式を決め打ちしない（[migration_plan](docs/phase3/migration_plan.md) Step 0.5）。Renderer は M3.5 まで MIDI だけ
- **責務と負荷で分ける**: 再生エンジンは actor にして UI（MainActor）から切り離す。高頻度に変わる再生位置は project と別のモデルにする。保存・読込のエンコードは MainActor の外で行う。UI の応答経路に `await` を置かない（[swift_ui_performance](docs/phase3/swift_ui_performance.md)）
- **上限と時間の値は根拠を書く**: 例: PPQN 336,000（retrig・gate・strum の割り算を整数にする最小公倍数）、先読み 25ms 周期・100ms 窓（背面では窓を広げる）、トラック上限 8、暴走検出 512 音
- **画面は迷わせない**: iPad 横向き・タッチ（ヒット領域 44pt 以上）を基準に作る。フィードバックは 1 か所に出す。次に鳴るパターン（NEXT）を取り違えない作りにする

## 3. 言語・ツール・依存

- **Swift**（Xcode 付属の最新安定版）を Swift 6 言語モード（Strict Concurrency 完全）で使う。`@unchecked Sendable` は使わない（使うなら ADR）
- **UI は SwiftUI**。AppKit / UIKit へのフォールバックは ADR を書いてから
- **対象 OS は実装開始時点の最新メジャーだけ**。`#available` などの分岐を書かない
- **Apple 公式のツールだけで完結させる**（Xcode / swift / xcodebuild）。プロジェクト生成ツール（XcodeGen・Tuist）、SwiftLint、MIDIKit などは入れない。依存を足すなら ADR に書き、最終の更新・リリースの頻度・メンテナーの数を確かめる。フォーマッタは Xcode 内蔵の swift-format
- **版と更新の手順**: 使った Xcode の版、対象 OS と swift-tools-version を上げる手順は [dev_environment_setup.md](docs/phase3/dev_environment_setup.md) に書く
- **用語は MIDI と音楽の標準の言葉にそろえる**（Note On/Off、CC、PPQN、ゲート、ベロシティなど）。用語集は `シーケンサー実装_用語集.md`
- **Web 版**: vanilla JS＋ES modules、バンドラーもフレームワークも無し。依存は開発用（Vitest・TypeScript）だけ。`// @ts-check` を付けたファイルだけ型検査される（`src/` と `manual/` が対象、`tests/` は対象外）。新しいファイルには `// @ts-check` と JSDoc を付ける

## 4. テスト

- **`fixtures/` が両実装の契約**。挙動の正は Web 版。食い違ったら「仕様書 → fixtures → 両実装」の順で直し、実装を先に変えて挙動を変えない。fixtures を変えたら `npm test` と `swift test` の両方を流す
- **Swift は swift-testing**。SequencerCore のカバレッジ 80% 以上。Web のテストは同じ値（仮想時計の時刻を含む）で移植する。MIDIEngine は `RecordingMIDIOutput` で送り出す列と時刻を確かめる
- **テストは外に通信しない**（アプリ自体も通信しない）
- **確かめたことと確かめていないことを分けて書く**: 音・タイミング（±1ms）・USB／IDAM の経路・背面での再生・操作感など、実機でしか確かめられないことは、手動の手順とチェックリストに載せる。Web 版は [RUNBOOK_6f](manual/RUNBOOK_6f.md)＋[CHECKLIST_6f](manual/CHECKLIST_6f.md)（期待値は [manual_verification_6f](docs/phase2/manual_verification_6f.md)）
- **Web 版のゴールデンテストとプロパティテスト**（`eventsGolden.test.js`・`eventsProperty.test.js` ほか）は、時刻計算や乱数を変えると動く。変えるときは fixtures を意図して更新する

## 5. ドキュメント

- **平易な日本語で書く**。文は短く、表を使う。コードのコメントも日本語（既存に合わせる）
- **読めば分かることは書かない**。件数や進み具合など、すぐ古くなる値をこのファイルに書かない
- **どの文書が正か**（食い違ったら負けた側を直す）:

| 対象 | 正 |
|---|---|
| データ形式 | [data_model_spec.md](docs/shared/data_model_spec.md) |
| 再生・発音の意味論 | [scheduler_spec.md](docs/shared/scheduler_spec.md)／[event_engine_design.md](docs/shared/event_engine_design.md) |
| 出力の構造（Trig と Renderer） | `Software_Modular_Sequencer_Development_Strategy.md` |
| UI | Phase 2 は `sequencer_layout_spec.md`（追加分は `docs/phase2/`）。Phase 3 は [requirements_phase3.md](docs/phase3/requirements_phase3.md)、作る順番と基準は [platform_strategy.md](docs/phase3/platform_strategy.md) |
| ネイティブの構成 | [native_architecture.md](docs/phase3/native_architecture.md) |
| 移植の手順 | [migration_plan.md](docs/phase3/migration_plan.md)。`docs/phase3/porting/`（P01〜P09）は設計の材料で、決まったものは仕様書か ADR に移す |

- **未決・矛盾は [spec_issues.md](docs/shared/spec_issues.md) に集める**。進み具合は cost_estimate（Phase 3 は工数表を作る）、技術的な難所は [technical_risks.md](docs/shared/technical_risks.md)。ほかの文書に散らさない
- **今と違う案は別の文書にする**: 既存の文書を書き換えず、案の文書を起こしてリンクする。採ったら元の文書に「採った形」とリンクを足す
- **設計の判断は ADR に残す**（背景・選択肢・決定・理由・影響。採用した案と採らなかった案を表にする）。両実装に関わるものは `docs/shared/adr/`、ネイティブだけのものは `docs/phase3/adr/`
- **文書を増やし過ぎない**。選択肢を外すときは、文書もあわせて減らす
- 状態の印は ✅ 完了／🟡 途中／⏳ 未着手／❌ 対象外
- `requirements_phase1.md`・`IMPLEMENTATION_PLAN.md`・`FILE_STRUCTURE_PLAN.md` は Phase 1 の凍結文書で、今の構成とは違う。Phase 2 以降の変更は `docs/` にだけ書く

## 6. プロジェクト固有

### 6.1 ネイティブアプリの構成

```text
native/
├── MidiSeq.xcodeproj      # 名前は仮
├── App/                   # 入口だけ（薄く）
├── Packages/              # SPM ローカルパッケージ
│   ├── SequencerCore/     # 純粋ロジック。Foundation だけに依存
│   ├── MIDIEngine/        # CoreMIDI・再生エンジン（actor）
│   └── （Persistence・PreviewSynth・DesignSystem・Features は、必要になったマイルストーンで足す）
└── scripts/test-all.sh    # 全パッケージのテストを横断して流す
```

- **依存の向き**（逆流禁止）: App → Features → DesignSystem／MIDIEngine → SequencerCore／Persistence → SequencerCore。SequencerCore は何にも依存しない
- **状態**: `ProjectStore`（`@Observable`・`@MainActor`、書類ごとに 1 つ）が値型の `Project` を持ち、更新は SequencerCore の純粋関数を呼んで代入するだけ。再生位置は別の `TransportModel` に分ける
- **再生エンジン**: `PlaybackEngine` は actor。時刻の打刻は actor の外（呼び出し側）で行う。op の適用と窓の確定を別の `await` に分けない。project の更新と op は 1 回の呼び出し（`apply(project:ops:)`）でまとめて渡す（[P03](docs/phase3/porting/P03_scheduler_runtime_port.md)）
- **プラットフォーム**: iPad が基準。macOS は常にビルド・起動できる状態を保つ。iPhone もビルドは通す（レイアウトは Go 判断まで手を付けない）。`#if os()` は App 層と、Features 内のファイル分割（`+macOS.swift` など）にだけ使う

### 6.2 両実装で守る不変条件（Web で確定し、Swift へそのまま移す）

1. **整数 tick の時間モデル**（[ADR-0001](docs/shared/adr/0001-internal-time-representation.md)）: `PPQN = 336_000`、16 分音符 1 つ = `84_000` tick。音楽上の時刻は整数 tick（Swift は `Int64`）。ms はテンポで変わる派生値。ただし窓の境界と frontier は整数にならないので `Double` のまま扱う（[P01](docs/phase3/porting/P01_numeric_semantics.md) §3）
2. **窓分割の不変性**: 境界の tick はちょうど 1 つの半開区間に属し、`[a,b)`＋`[b,c)` の結果は `[a,c)` と同じ。先読み窓を広げても出力が変わらないのはこのため
3. **決定的な乱数**（[ADR-0002](docs/shared/adr/0002-prob-rng-algorithm.md)）: PROB は `rand(seed, trackId, loopCount, step, draw)` のカウンタ方式。Swift は `UInt32` でビット単位まで一致させ、trackId のハッシュは UTF-16 コードユニットで計算する（[P02](docs/phase3/porting/P02_rng_bit_exact.md)）
4. **スタックノート防止**: 発音中の音の正は ActiveNoteTracker。Note Off を予約しても、実際に送られるまで音を忘れない。予約の取り消しが保証されない場合の経路（Chrome は `MIDIOutput.clear()` を実装していない）は Swift でも残す（[P04](docs/phase3/porting/P04_cleanup_coremidi.md) §3）。Off・sweep・ghost の処理は特に慎重に直す
5. **64 ステップ固定**: 各トラックの `steps` は LEN に関係なく常に 64 個（4 ページ×16）。LEN を縮めてもデータは残る。`dataIndex = page*16 + (s % stepsPerPage)` で、再生位置とデータの位置は別物。トラック上限はデータモデルで 8。UI の上限（Phase 2 は 4、Phase 3 は 8）は Store 層で課し、core に 4 を書かない
6. **Trig と Renderer**: core が作るのは出力先によらない Trig。MIDI のバイト列は Renderer より後ろで作る
7. **出力に効く順序は挿入順で保つ**: JS の Map・Set は挿入順、Swift の Dictionary・Set は順不同。送り出す列に効く箇所は配列か順序付きの辞書にする。パニックはチャンネルの昇順（[P01](docs/phase3/porting/P01_numeric_semantics.md) §4・[P04](docs/phase3/porting/P04_cleanup_coremidi.md) §5）
8. **core は現在時刻を呼ばない**: 時刻は引数で受け取る（Web は `nowIso`）

### 6.3 データとファイル互換

- スキーマの正は [data_model_spec.md](docs/shared/data_model_spec.md)（`schemaVersion: 2`）。範囲外の値と整数でない数値は**エラー**にする（丸めない）。未知のフィールドは捨てる。v1 からの移行は無い
- **互換の定義**: 相手の書いたファイルを読めること、読んで正規化して書いた結果が JSON の値として一致すること。バイト単位の一致ではない（[P06](docs/phase3/porting/P06_serialization_codable.md) §2）。Web 版との相互互換は MUST
- Swift の `Step` は全フィールドを持つ平らな struct にして、書き出しはトラックの種類で決める。meta の日時は文字列のまま持つ。エラーの文言は等価性の対象外
- MIDI ポートは保存しない（環境の状態）
- **スキーマを変えるとき**: `SCHEMA_VERSION` を上げ、data_model_spec に変更履歴と移行規則を同じ変更で書き、fixtures と両実装を合わせて直す

### 6.4 コマンド

ネイティブ（`native/` を作った後）:

```bash
cd native/Packages/SequencerCore && swift test   # パッケージ単位
./native/scripts/test-all.sh                     # 全パッケージのテスト＋macOS 向けビルド
```

Web:

```bash
npm test                                  # Vitest 全件
npm run typecheck                         # tsc --noEmit（出力なし）
npx vitest run tests/scheduler.test.js    # 1 ファイル
npx vitest run -t "swing"                 # 名前で絞る
npx serve                                 # 起動（または python3 -m http.server 8000）
```

Web 版の起動は、リポジトリのルートを HTTP で配信して Chrome か Edge で `index.html` を開く（Web MIDI が要る。Safari・Firefox・`file://` は不可）。スケジューラ単体の試験画面は `manual/poly_scheduler.html`。

### 6.5 Web 版（参照実装）の要点

- **層**: `src/core/`（純粋ロジック。DOM・Web API・`Date` を使わない）→ `src/engine/`（再生・MIDI 入出力）→ `src/ui/`（DOM・Store）。依存は一方向で、配線は `src/main.js` だけ
- **Store**: `src/ui/store.js` は自前の Redux 風。reducer は純粋で、状態は `{ project, view }`（project は保存する書類、view は保存しない画面の状態）。アクションの一覧はファイル冒頭。Swift への対応表は [P05](docs/phase3/porting/P05_store_action_mapping.md)
- **再生の流れ**: `events.js resolveWindow()`（半開区間の Trig を作る）→ `scheduler.js`（発音管理・先読み）→ `midiOut.js`。`driver.js` が 25ms ごとに `scheduler.tick()` を呼び、`playbackController.js` が Store とつなぐ
- **データモデル**: `src/core/model.js`（作成・正規化・更新。引数を書き換えない）、`src/core/serialize.js`（JSON の入出力と検証）、ファイル操作は `src/ui/fileio.js`
