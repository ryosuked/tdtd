// TaskInspector.swift — 右の詳細のペイン（Features）
//
// 選んだタスクの全文を出し、編集する（中身・完了・カテゴリ・期限・削除）。requirements F4-9。
//
// レビューの観点:
// - 編集中の文字列（draft）と保存しているデータ（task.content）を分けている理由（TaskDetail のコメント）

import SwiftUI
import TodoCore

/// 右の詳細のペイン。選んだタスクの中身を全文で出し、編集できる（requirements F4-9）
struct TaskInspector: View {
    let store: WorkspaceStore
    let taskID: UUID?

    var body: some View {
        // `if let a, let b = ...` は「nil でなければ取り出して使う」書き方。どちらかが nil なら else へ
        if let taskID, let found = store.workspace.task(taskID) {
            TaskDetail(store: store, task: found.task, category: found.category)
                // .id: この値が変わると部品を作り直す。別のタスクを選ぶと、draft なども初期値に戻る
                .id(taskID)
        } else {
            ContentUnavailableView(
                "タスクを選んでください", systemImage: "sidebar.right",
                description: Text("一覧でタスクを選ぶと、ここに中身が出ます。")
            )
        }
    }
}

private struct TaskDetail: View {
    let store: WorkspaceStore
    let task: TodoItem
    let category: TodoCategory
    /// 編集中の中身。決まりに合うときだけ Store へ渡す（空にした途中などで誤りを出し続けないため）
    ///
    /// 保存しているデータ（task.content）とは別に持つ。決まりに合わない途中の文字列（全部消した瞬間など）も
    /// 画面には出し続けたいが、データには入れないため。別のタスクを選ぶと .id(taskID) で作り直され、初期値に戻る
    @State private var draft: String
    @State private var problem: TextRule.Violation?

    init(store: WorkspaceStore, task: TodoItem, category: TodoCategory) {
        self.store = store
        self.task = task
        self.category = category
        // Ceremony: @State の初期値を引数から決めるときの書き方（`_draft` は @State の入れ物そのもの）
        _draft = State(initialValue: task.content)
    }

    // 上から: 完了とカテゴリ → 中身の編集 → 文字数と誤り → 期限 → 日時と削除
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow
            editor
            counterRow
            DueEditor(due: Binding(get: { task.due }, set: { store.setDue(task.id, $0) }))
            footerRow
        }
        .padding()
    }

    // 以下は body を段ごとに分けたもの。`some View` は「何かの画面の部品を返す」の意味

    private var statusRow: some View {
        HStack {
            Toggle(isOn: Binding(get: { task.isCompleted }, set: { store.setCompleted(task.id, $0) })) {
                Text(task.isCompleted ? "完了" : "未完了")
            }
            Spacer()
            Picker("カテゴリ", selection: Binding(
                get: { category.id }, set: { store.moveTaskToEnd(task.id, of: $0) }
            )) {
                ForEach(store.workspace.categories) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    /// 決まりに合わない間は枠を赤くする
    private var editor: some View {
        TextEditor(text: $draft)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(.background, in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(problem == nil ? AnyShapeStyle(.separator) : AnyShapeStyle(.red))
            )
            .frame(maxHeight: .infinity)
            .onChange(of: draft) { _, value in commit(value) }
    }

    private var counterRow: some View {
        HStack {
            if let problem {
                Text("中身は\(problem.message)").foregroundStyle(.red)
            }
            Spacer()
            Text("\(PlainText.normalized(draft).count.formatted()) / \(TextRule.taskContent.maxLength.formatted()) 文字")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private var footerRow: some View {
        HStack {
            Text("作成: \(task.createdAt.formatted(date: .abbreviated, time: .shortened))")
            if let completedAt = task.completedAt {
                Text("完了: \(completedAt.formatted(date: .abbreviated, time: .shortened))")
            }
            Spacer()
            Button("削除", systemImage: "trash", role: .destructive) { store.deleteTask(task.id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// 貼り付けで混ざる文字は Store に渡すときにそろう（data_model_spec §3.3）。
    /// 編集中の文字列は書き換えない（カーソルが飛ぶため）。そろえた後の形で比べ、変わったときだけ渡す
    private func commit(_ value: String) {
        do {
            let normalized = try TextRule.taskContent.accept(value)
            problem = nil
            if normalized != task.content { store.setContent(task.id, normalized) }
        } catch {
            problem = error
        }
    }
}

/// 期限。日付だけを扱う。外すこともできる
private struct DueEditor: View {
    @Binding var due: LocalDate?

    var body: some View {
        HStack {
            Toggle("期限", isOn: Binding(
                get: { due != nil },
                set: { due = $0 ? (due ?? LocalDate(Date(), in: .current)) : nil }
            ))
            if let current = due {
                DatePicker(
                    "期限", selection: Binding(get: { current.date(in: .current) }, set: { due = LocalDate($0, in: .current) }),
                    displayedComponents: .date
                )
                .labelsHidden()
            }
            Spacer()
        }
    }
}
