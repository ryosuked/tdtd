// Components.swift — 両方の表示で使う部品（Features）
//
// - TaskRow: タスク 1 行（完了の丸、冒頭 3 行、期限、右クリックのメニュー）
// - CategoryHeader: カテゴリの見出し（色、名前、未完了の数、メニュー）
// - AddTaskField: タスクを足す 3 行の入力欄
// 部品から使う補助（名前の変更のアラート・色の対応表など）は ViewHelpers.swift にある。

import SwiftUI
import TodoCore

/// タスク 1 行。左の丸で完了を切り替え、中身は冒頭の 3 行だけを出す（requirements F4-8）
struct TaskRow: View {
    let store: WorkspaceStore
    let task: TodoItem

    var body: some View {
        let preview = task.preview
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                store.setCompleted(task.id, !task.isCompleted)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Color.accentColor : .secondary)
                    .imageScale(.large)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // 画面の読み上げ（VoiceOver）が読む名前。アイコンだけのボタンには必ず付ける
            .accessibilityLabel(task.isCompleted ? "未完了に戻す" : "完了にする")

            VStack(alignment: .leading, spacing: 2) {
                // 全文ではなく切り出した冒頭を渡す。長い中身でもレイアウトの重さが変わらない
                Text(preview.isTruncated ? preview.text + "…" : preview.text)
                    .lineLimit(TodoItem.previewLines)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                if let due = task.due {
                    Label(due.string, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        // 右クリック（iPad では長押し）で出るメニュー
        .contextMenu {
            Menu("カテゴリへ移す") {
                ForEach(store.workspace.categories) { category in
                    Button(category.name) {
                        store.moveTaskToEnd(task.id, of: category.id)
                    }
                }
            }
            Button("削除", role: .destructive) { store.deleteTask(task.id) }
        }
    }
}

/// カテゴリの見出し。名前の変更・色・削除のメニューを持つ
struct CategoryHeader: View {
    let store: WorkspaceStore
    let category: TodoCategory
    @State private var renaming: TodoCategory?
    @State private var confirmingDelete = false

    var body: some View {
        HStack {
            Circle().fill(category.color.swatch).frame(width: 10, height: 10)
            Text(category.name).font(.headline)
            Text("\(category.tasks.count { !$0.isCompleted })")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("名前を変更…") { renaming = category }
                Picker("色", selection: Binding(
                    get: { category.color },
                    set: { store.setCategoryColor(category.id, to: $0) }
                )) {
                    ForEach(CategoryColor.allCases, id: \.self) { color in
                        Text(color.label).tag(color)
                    }
                }
                Divider()
                Button("削除…", role: .destructive) {
                    // タスクが残っていなければ確認しない（requirements F2-2）
                    if category.tasks.isEmpty { store.deleteCategory(category.id) } else { confirmingDelete = true }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .renameAlert(item: $renaming, title: "カテゴリの名前", current: \.name) { category, name in
            store.renameCategory(category.id, to: name)
        }
        .confirmationDialog(
            "「\(category.name)」を削除しますか", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) { store.deleteCategory(category.id) }
        } message: {
            Text("中のタスク \(category.tasks.count) 件も消えます。")
        }
    }
}

/// タスクを足す入力欄。3 行分の高さで、複数行を入れられる（requirements F3-2）。
/// Return か ＋ ボタンで足す。改行は貼り付けか Option＋Return で入れる
struct AddTaskField: View {
    @Binding var content: String
    /// 足せたら true を返す。足せなかったときは入力を消さない
    let onAdd: (String) -> Bool

    /// 先にそろえてから前後の空白を除く。逆にすると、末尾の「改行＋見えない文字」の改行が残る
    private var trimmed: String {
        PlainText.normalized(content).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("タスクを追加", text: $content, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            Button("追加", systemImage: "plus.circle.fill", action: add)
                .labelStyle(.iconOnly)
                .imageScale(.large)
                .buttonStyle(.borderless)
                .disabled(trimmed.isEmpty)
        }
    }

    private func add() {
        let value = trimmed
        guard !value.isEmpty, onAdd(value) else { return }
        content = ""
    }
}
