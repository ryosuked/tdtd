// ColumnsView.swift — 短冊表示（Features）
//
// カテゴリごとに縦長の列（CategoryColumn）を作り、横に並べる。requirements F4-1・F4-6。
// 行（TaskRow）・見出し（CategoryHeader）・追加の入力欄（AddTaskField）は Components.swift にある。

import SwiftUI
import TodoCore

/// 短冊表示: カテゴリごとの列を横に並べる。幅が足りなければ横にスクロールする（requirements F4-1・F4-6）
struct ColumnsView: View {
    let store: WorkspaceStore
    let hideCompleted: Bool
    @Binding var selection: UUID?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(store.workspace.categories) { category in
                    CategoryColumn(store: store, category: category, hideCompleted: hideCompleted, selection: $selection)
                }
            }
            .padding()
        }
    }
}

struct CategoryColumn: View {
    let store: WorkspaceStore
    let category: TodoCategory
    let hideCompleted: Bool
    @Binding var selection: UUID?
    @State private var newContent = ""

    /// 列の幅。iPad の縦向き（約 820pt）でも 2 列半ほどが見える幅にした
    static let width: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CategoryHeader(store: store, category: category)
            ScrollView {
                // LazyVStack: 縦の並び。見えている分だけ作るので、件数が多くても重くならない
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(category.visibleTasks(hideCompleted: hideCompleted)) { task in
                        TaskRow(store: store, task: task)
                            .padding(.horizontal, 6)
                            .background(
                                selection == task.id ? Color.accentColor.opacity(0.18) : .clear,
                                in: .rect(cornerRadius: 8)
                            )
                            // List ではないので選択の仕組みが無い。叩いたら選択の ID を書き換え、背景で示す
                            .onTapGesture { selection = task.id }
                    }
                }
            }
            AddTaskField(content: $newContent) { store.addTask(content: $0, to: category.id) }
        }
        .padding(12)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}
