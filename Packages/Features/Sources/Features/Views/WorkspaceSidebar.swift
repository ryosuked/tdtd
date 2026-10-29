// WorkspaceSidebar.swift — 左のワークスペースの一覧（Features）
//
// 選択・追加・名前の変更・削除（確認あり）・並べ替え・インポートの開始。requirements F1。

import SwiftUI
import TodoCore

/// ワークスペースの一覧（requirements F1）
struct WorkspaceSidebar: View {
    @Bindable var model: AppModel
    @Binding var isImporting: Bool
    @State private var renaming: WorkspaceStore?
    @State private var deleting: WorkspaceStore?

    var body: some View {
        // List(selection:) は、行を選ぶと選んだ行の tag の値を selectedID に入れる
        List(selection: $model.selectedID) {
            // ForEach: 配列の要素ごとに行を作る（要素は id で区別される）
            ForEach(model.stores) { store in
                Text(store.workspace.name)
                    .tag(store.id)
                    .contextMenu {
                        Button("名前を変更…") { renaming = store }
                        Button("削除…", role: .destructive) { deleting = store }
                    }
            }
            .onMove { model.moveWorkspaces(fromOffsets: $0, toOffset: $1) }
        }
        .navigationTitle("ワークスペース")
        .toolbar {
            ToolbarItemGroup {
                Button("読み込む", systemImage: "square.and.arrow.down") { isImporting = true }
                Button("ワークスペースを追加", systemImage: "plus") {
                    model.addWorkspace(name: "新しいワークスペース")
                }
            }
        }
        .renameAlert(item: $renaming, title: "ワークスペースの名前", current: \.workspace.name) { store, name in
            store.rename(name)
        }
        .confirmationDialog(
            "「\(deleting?.workspace.name ?? "")」を削除しますか",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let id = deleting?.id { model.deleteWorkspace(id) }
            }
        } message: {
            Text("中のカテゴリとタスクもすべて消えます。")
        }
    }
}
