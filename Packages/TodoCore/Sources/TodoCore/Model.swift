// Model.swift — データの型（TodoCore）
//
// ワークスペース → カテゴリ → タスクの 3 段の値型。JSON の形（data_model_spec §3）と 1 対 1 に対応する。
// どれも値型（struct）で、変更は Operations.swift の操作だけを通す。
// 末尾に、日時をミリ秒にそろえる補助（Date の extension）がある。
//
// レビューの観点:
// - ここには検証が無い。誤りの状態を持ち込まないのは、操作（Operations.swift）と
//   読み込み（Persistence の WorkspaceCodec.swift の Validator）の役目
// - 並び順の欄（order）や所属カテゴリの ID を持たない。配列の順と入れ子の位置がそれを表す（ADR-0001）

import Foundation

// struct は「値型」: 代入や引数で渡すとコピーされる。どこかでコピーを書き換えても、元には影響しない。
// 型名の後ろの Equatable などは「この型が守る約束（プロトコル）」の一覧。
// Ceremony: Equatable（== で比べられる）・Hashable（辞書のキーや集合に入れられる）・
//   Sendable（スレッドをまたいで安全に渡せる）・Identifiable（画面の一覧で id で 1 件ずつ区別できる）。
//   中身の処理は Swift が自動で作るので、ここでは名前を並べるだけ。下の 3 つの型も同じ

/// ワークスペース。インポート・エクスポートの単位（data_model_spec §3）
public struct Workspace: Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// 配列の順 = 表示の順
    public var categories: [TodoCategory]
    public var createdAt: Date
    /// ファイルの中の、どこかが最後に変わった日時
    public var updatedAt: Date

    // Ceremony: パッケージの外（Persistence・Features）から作れるように、public の init を手で書く。
    // 中身は引数をそのまま入れるだけ（`= []` は省略したときの既定値）。下の 2 つの init も同じ
    public init(id: UUID, name: String, categories: [TodoCategory] = [], createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.categories = categories
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// カテゴリ。JSON では `categories[]` の要素。
/// `Category` は ObjectiveC モジュールの型とぶつかるので `TodoCategory` にする
public struct TodoCategory: Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: CategoryColor
    /// 配列の順 = 表示の順
    public var tasks: [TodoItem]
    public var createdAt: Date

    public init(id: UUID, name: String, color: CategoryColor = .gray, tasks: [TodoItem] = [], createdAt: Date) {
        self.id = id
        self.name = name
        self.color = color
        self.tasks = tasks
        self.createdAt = createdAt
    }
}

/// タスク。`Task` は Swift の並行処理とぶつかるので `TodoItem` にする
public struct TodoItem: Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// タスクの中身。タイトルとメモには分けない（data_model_spec §3）
    public var content: String
    /// 型の後ろの `?` は「値が無い（nil）こともある」の意味。期限は付けないこともある
    public var due: LocalDate?
    /// nil なら未完了
    public var completedAt: Date?
    public var createdAt: Date

    public init(
        id: UUID, content: String, due: LocalDate? = nil,
        completedAt: Date? = nil, createdAt: Date
    ) {
        self.id = id
        self.content = content
        self.due = due
        self.completedAt = completedAt
        self.createdAt = createdAt
    }

    /// 保存しない値。読むたびに completedAt から求める（計算プロパティ）
    public var isCompleted: Bool { completedAt != nil }
}

/// カテゴリの色。16 進の色値ではなくパレット名で持つ（data_model_spec §3.1）
/// enum は「決まった選択肢のどれか 1 つ」を表す型。`: String` で各選択肢に文字列（rawValue）が付き、JSON にはこの文字列で書く。
/// CaseIterable は「全選択肢の一覧（allCases）を取れる」約束。色を選ぶメニューで使う
public enum CategoryColor: String, CaseIterable, Sendable {
    case gray, red, orange, yellow, green, teal, blue, indigo, purple, pink
}

// MARK: - 日時
// 保存の書式はミリ秒まで（data_model_spec §3.2）。操作が打つ日時も、ここでミリ秒に丸めてそろえる

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
