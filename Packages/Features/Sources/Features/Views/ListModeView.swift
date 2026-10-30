// ListModeView.swift — 1 欄表示（Features）
//
// 全カテゴリのタスクを 1 本のリストに並べる。並びは TodoCore の listSections で導き出す（保存しない）。
// 下の入力欄で、カテゴリを選んでタスクを足す。requirements F4-2・F4-5。

import SwiftUI
import Persistence
import TodoCore

/// 1 欄表示: カテゴリの順にタスクをつなげ、見出しで区切る（requirements F4-2・F4-5）
struct ListModeView: View {
    let model: AppModel
    let store: WorkspaceStore
    let hideCompleted: Bool
    @Binding var selection: UUID?
    @State private var newContent = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.workspace.listSections(hideCompleted: hideCompleted)) { section in
                    Section {
                        ForEach(section.tasks) { task in
                            TaskRow(store: store, task: task).tag(task.id)
                        }
                    } header: {
                        CategoryHeader(store: store, category: section.category)
                    }
                }
            }
            Divider()
            HStack(alignment: .bottom) {
                Picker("カテゴリ", selection: categoryBinding) {
                    ForEach(store.workspace.categories) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
                AddTaskField(content: $newContent) { content in
                    guard let id = categoryBinding.wrappedValue else { return false }
                    return store.addTask(content: content, to: id)
                }
            }
            .padding(12)
        }
    }

    /// 最初に選ばれているのは、最後に使ったカテゴリ。無ければ先頭
    ///
    /// 選んだカテゴリは保存しない画面の値ではなく、表示の状態（lastUsedCategoryId）に書く。次に開いたときも残すため
    private var categoryBinding: Binding<UUID?> {
        Binding(
            get: {
                // 最後に使ったカテゴリが消えていたら、先頭にする
                let last = model.viewState(store.id).lastUsedCategoryId.flatMap { store.workspace.category($0) }
                return (last ?? store.workspace.categories.first)?.id
            },
            set: { id in model.updateViewState(store.id) { $0.lastUsedCategoryId = id } }
        )
    }
}
