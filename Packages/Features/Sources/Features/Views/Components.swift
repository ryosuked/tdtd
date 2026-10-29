// Components.swift — 両方の表示で使う部品（Features）
//
// - TaskRow: タスク 1 行（完了の丸、冒頭 3 行、期限、右クリックのメニュー）
// - CategoryHeader: カテゴリの見出し（色、名前、未完了の数、メニュー）
// - AddTaskField: タスクを足す 3 行の入力欄
// - renameAlert: 名前を変えるアラート（ワークスペースとカテゴリで共用）
// - CategoryColor の色と表示名

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
                        store.moveTask(task.id, to: category.id, at: category.tasks.count)
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

// Ceremony: 下の RenameAlert（ViewModifier）を、`.renameAlert(...)` の形で書けるようにするだけ
extension View {
    /// 名前を変える入力のアラート。空白だけの名前は受け付けない
    func renameAlert<Item>(
        item: Binding<Item?>, title: LocalizedStringKey, current: KeyPath<Item, String>,
        onCommit: @escaping (Item, String) -> Void
    ) -> some View {
        modifier(RenameAlert(item: item, title: title, current: current, onCommit: onCommit))
    }
}

/// ViewModifier は「ほかの画面に機能を足す部品」。ここではアラートを足す。
/// `<Item>` はワークスペース（WorkspaceStore）とカテゴリ（TodoCategory）のどちらにも使うための型引数
private struct RenameAlert<Item>: ViewModifier {
    @Binding var item: Item?
    let title: LocalizedStringKey
    let current: KeyPath<Item, String>
    let onCommit: (Item, String) -> Void
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } })) {
                TextField("名前", text: $text)
                Button("キャンセル", role: .cancel) { item = nil }
                Button("OK") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let item, !trimmed.isEmpty { onCommit(item, trimmed) }
                    item = nil
                }
            }
            // アラートを開くたびに、入力欄を今の名前で埋める（前回の入力が残らないように）
            .onChange(of: item != nil) { _, shown in
                if shown, let item { text = item[keyPath: current] }
            }
    }
}

// 以下は、色の名前（TodoCore の CategoryColor）から、画面の色と日本語の表示名への対応表

extension CategoryColor {
    /// パレット名から実際の色へ。ライト・ダークはシステムの色に任せる
    var swatch: Color {
        switch self {
        case .gray: .gray
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        }
    }

    var label: String {
        switch self {
        case .gray: "グレー"
        case .red: "赤"
        case .orange: "オレンジ"
        case .yellow: "黄"
        case .green: "緑"
        case .teal: "青緑"
        case .blue: "青"
        case .indigo: "藍"
        case .purple: "紫"
        case .pink: "ピンク"
        }
    }
}
