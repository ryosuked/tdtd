// Operations.swift — データを変える操作（TodoCore）
//
// 画面からの操作は、すべて Features の WorkspaceStore を経由してここの関数に来る。
// 1 つの関数が、data_model_spec §4 の操作の表の 1 行に対応する。
//
// レビューの観点:
// - 外の状態（時計・乱数・ファイル）に触っていないか。現在時刻と ID は引数で受け取る
// - 文字列を受け取る操作は、変更の前に TextRule で確かめているか（誤りならデータは変わらない）
// - updatedAt は update(now:_:) だけが書く。値が変わらない操作では動かない

import Foundation

// extension は「既にある型（ここでは Model.swift の Workspace）に関数を足す」書き方。
// 型の定義とは別のファイルに、操作だけをまとめるために使っている。
extension Workspace {
    /// 変更を当てる。値が変わったときだけ `updatedAt` を `now` にする
    ///
    /// すべての操作がこれを通る。複製（next）に当ててから比べるので、
    /// 「存在しない ID を指定した」「同じ値を入れた」操作では updatedAt も動かない（data_model_spec §4）。
    /// 比べるのは全体の == なので件数に比例するが、5,000 件でも 1 操作あたり数 ms に収まる
    ///
    /// 読み方: mutating は「自分自身（値）を書き換える関数」の印。
    /// `change` は呼ぶ側がその場で書く小さな関数（クロージャ）で、inout は「受け取った値を中で書き換えてよい」の印
    mutating func update(now: Date, _ change: (inout Workspace) -> Void) {
        var next = self
        change(&next)
        guard next != self else { return }
        next.updatedAt = now.roundedToMilliseconds
        self = next
    }

    // MARK: ワークスペース

    // 読み方（以下の操作に共通）:
    // - throws(EditError): 失敗すると EditError を投げる。呼ぶ側は try を付けて呼ぶ
    // - `{ $0.name = name }` はクロージャ。$0 は 1 番目の引数（ここでは書き換え中の Workspace の複製）
    public mutating func rename(_ name: String, now: Date) throws(EditError) {
        // 先に確かめる。誤りならここで投げて抜けるので、下の update は実行されない（データは変わらない）
        let name = try TextRule.workspaceName.acceptForEdit(name)
        update(now: now) { $0.name = name }
    }

    // MARK: カテゴリ

    /// 末尾に足す
    public mutating func addCategory(id: UUID, name: String, color: CategoryColor = .gray, now: Date) throws(EditError) {
        let name = try TextRule.categoryName.acceptForEdit(name)
        update(now: now) {
            $0.categories.append(TodoCategory(id: id, name: name, color: color, createdAt: now.roundedToMilliseconds))
        }
    }

    public mutating func renameCategory(_ categoryID: UUID, to name: String, now: Date) throws(EditError) {
        let name = try TextRule.categoryName.acceptForEdit(name)
        update(now: now) { ws in
            ws.withCategory(categoryID) { $0.name = name }
        }
    }

    public mutating func setCategoryColor(_ categoryID: UUID, to color: CategoryColor, now: Date) {
        update(now: now) { ws in
            ws.withCategory(categoryID) { $0.color = color }
        }
    }

    /// `index` は動かした後の位置
    public mutating func moveCategory(_ categoryID: UUID, to index: Int, now: Date) {
        update(now: now) { ws in
            guard let from = ws.categories.firstIndex(where: { $0.id == categoryID }) else { return }
            let category = ws.categories.remove(at: from)
            ws.categories.insert(category, at: min(max(index, 0), ws.categories.count))
        }
    }

    /// 中のタスクも消える
    public mutating func deleteCategory(_ categoryID: UUID, now: Date) {
        update(now: now) { $0.categories.removeAll { $0.id == categoryID } }
    }

    // MARK: タスク

    /// カテゴリの末尾に足す
    public mutating func addTask(id: UUID, content: String, to categoryID: UUID, now: Date) throws(EditError) {
        let content = try TextRule.taskContent.acceptForEdit(content)
        update(now: now) { ws in
            ws.withCategory(categoryID) {
                $0.tasks.append(TodoItem(id: id, content: content, createdAt: now.roundedToMilliseconds))
            }
        }
    }

    public mutating func setContent(_ taskID: UUID, _ content: String, now: Date) throws(EditError) {
        let content = try TextRule.taskContent.acceptForEdit(content)
        update(now: now) { ws in
            ws.withTask(taskID) { $0.content = content }
        }
    }

    /// nil で期限を外す
    public mutating func setDue(_ taskID: UUID, _ due: LocalDate?, now: Date) {
        update(now: now) { ws in
            ws.withTask(taskID) { $0.due = due }
        }
    }

    public mutating func setCompleted(_ taskID: UUID, _ completed: Bool, now: Date) {
        update(now: now) { ws in
            ws.withTask(taskID) {
                guard $0.isCompleted != completed else { return }
                $0.completedAt = completed ? now.roundedToMilliseconds : nil
            }
        }
    }

    /// 同じカテゴリの中の並べ替えと、別のカテゴリへの移動の両方に使う。`index` は移す先での位置
    ///
    /// `index` は「抜いた後の配列」での位置。同じカテゴリの中で下へ動かすときは、
    /// 抜いた分だけ番号が 1 つ詰まることに注意（範囲外は末尾に丸める）
    public mutating func moveTask(_ taskID: UUID, to categoryID: UUID, at index: Int, now: Date) {
        update(now: now) { ws in
            // 移す先が無いときに先に抜いてしまうと、タスクが消えるので、先に確かめる。
            // guard 条件 else { return } は「条件に合わなければ、ここで抜ける」書き方
            guard ws.categories.contains(where: { $0.id == categoryID }),
                  let (ci, ti) = ws.taskPosition(taskID)
            else { return }
            let task = ws.categories[ci].tasks.remove(at: ti)
            ws.withCategory(categoryID) {
                $0.tasks.insert(task, at: min(max(index, 0), $0.tasks.count))
            }
        }
    }

    public mutating func deleteTask(_ taskID: UUID, now: Date) {
        update(now: now) { ws in
            guard let (ci, ti) = ws.taskPosition(taskID) else { return }
            ws.categories[ci].tasks.remove(at: ti)
        }
    }

    // MARK: 探す

    public func category(_ categoryID: UUID) -> TodoCategory? {
        categories.first { $0.id == categoryID }
    }

    /// 戻り値の `(task:, category:)` は 2 つの値の組（タプル）。見つからなければ nil
    public func task(_ taskID: UUID) -> (task: TodoItem, category: TodoCategory)? {
        guard let (ci, ti) = taskPosition(taskID) else { return nil }
        return (categories[ci].tasks[ti], categories[ci])
    }

    /// タスクの位置（カテゴリの番号、タスクの番号）。全カテゴリを先頭から探す（件数に比例）
    func taskPosition(_ taskID: UUID) -> (category: Int, task: Int)? {
        for (ci, category) in categories.enumerated() {
            if let ti = category.tasks.firstIndex(where: { $0.id == taskID }) { return (ci, ti) }
        }
        return nil
    }

    /// Wiring: ID で探して、見つかったら change に渡すだけ。見つからなければ何もしない（下の withTask も同じ）
    private mutating func withCategory(_ categoryID: UUID, _ change: (inout TodoCategory) -> Void) {
        guard let i = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        change(&categories[i])
    }

    private mutating func withTask(_ taskID: UUID, _ change: (inout TodoItem) -> Void) {
        guard let (ci, ti) = taskPosition(taskID) else { return }
        change(&categories[ci].tasks[ti])
    }
}

extension Date {
    /// 1970 年からのミリ秒（整数）。保存の書式はこの値で書く
    public var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }

    /// ミリ秒（整数）から Date を作る
    public init(millisecondsSince1970 ms: Int64) {
        self.init(timeIntervalSince1970: Double(ms) / 1000)
    }

    /// ミリ秒に丸める。保存の書式（ミリ秒まで）と往復させても値が変わらないようにするため。
    /// 切り捨てにしないのは、浮動小数点の誤差で 1 ms 下がることがあり、何度かけても同じ値になる保証が無いため
    public var roundedToMilliseconds: Date {
        Date(millisecondsSince1970: millisecondsSince1970)
    }
}
