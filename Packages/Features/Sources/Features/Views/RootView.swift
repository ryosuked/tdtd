// RootView.swift — 画面の入口（Features）
//
// 左: ワークスペースの一覧（WorkspaceSidebar）、右: 選んだワークスペース（WorkspaceView）。
// アプリ全体に関わるもの（読み込みの開始、インポートの選択と確認、誤りのアラート、背面に回ったときの保存）もここに置く。

import SwiftUI
import TodoCore
import UniformTypeIdentifiers

// SwiftUI の画面の読み方（Views/ のファイルに共通）:
// - `struct 名前: View` が 1 つの画面の部品。`body` に中身を書く
// - 使っている値が変わるたびに body が呼び直され、画面が描き直される。だから body に重い処理を置かない
// - `.alert(...)` のように後ろに続く `.xxx` は修飾子（modifier）。見た目や動きを、上から順に包んで足していく
// - 値の持ち方の印:
//     @State     この画面だけが持つ値（変わると描き直す）
//     @Binding   親の画面が持つ値を借りて、読み書きする
//     @Bindable  @Observable の値（AppModel など）の項目を、入力欄や選択に結びつけるための印
// - `Binding(get: { ... }, set: { ... })` は、その場で作る読み書きの口。get で今の値を返し、set で変えたときの処理をする

/// 画面の入口。左にワークスペースの一覧、右に選んだワークスペース
public struct RootView: View {
    @Bindable var model: AppModel
    // アプリが前面か背面か（scenePhase）を、システムから受け取る
    @Environment(\.scenePhase) private var scenePhase
    @State private var isImporting = false

    // Ceremony: パッケージの外（App）から作れるように、public の init を書く
    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            WorkspaceSidebar(model: model, isImporting: $isImporting)
        } detail: {
            if let store = model.selectedStore {
                WorkspaceView(model: model, store: store)
                    .id(store.id)
            } else if model.isLoaded {
                ContentUnavailableView(
                    "ワークスペースがありません", systemImage: "square.stack",
                    description: Text("左の ＋ から作るか、ファイルを読み込んでください。")
                )
            }
        }
        // .task: 画面が出たときに 1 回、非同期の処理を始める
        .task { await model.load() }
        // 背面に回ったら、1 秒の待ちを待たずに保存する（iPad で強制終了されても失わないため）。
        // Mac の終了時は App/TodoApp.swift の AppDelegate が書き切る
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.flushAll() } }
        }
        // ファイルを選ぶ画面。isImporting が true になると開く（`$` を付けると Binding として渡す）
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): Task { await model.importFile(at: url) }
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "同じワークスペースがすでにあります",
            isPresented: $model.pendingImport.isPresent(),
            titleVisibility: .visible
        ) {
            Button("置き換える", role: .destructive) { model.resolvePendingImport(replace: true) }
            Button("複製として追加") { model.resolvePendingImport(replace: false) }
            Button("キャンセル", role: .cancel) { model.pendingImport = nil }
        } message: {
            Text("「\(model.pendingImport?.name ?? "")」をどう読み込みますか。")
        }
        .alert("エラー", isPresented: $model.errorMessage.isPresent()) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
