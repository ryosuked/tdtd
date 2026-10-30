// WorkspaceFile.swift — ファイル用の型（Persistence）
//
// JSON をそのまま受けるための型（DTO）。値は文字列のまま持ち、検証は WorkspaceCodec.swift の Validator で行う。
// 末尾に、書くときの「ドメインの型 → DTO」の詰め替えがある（読むときの逆向きは検証を伴うので Validator）。
// タスクの形だけが版で違う（版 1: title・note、版 2: content）ので、タスクの型を型引数にして入れ物を使い回す。
//
// 対応関係:   JSON の各階層  ⇔  ここの DTO  ⇔  TodoCore の型
//   ファイル全体      WorkspaceFileDTO     —
//   workspace         WorkspaceDTO         Workspace
//   categories[]      CategoryDTO          TodoCategory
//   tasks[]           TodoItemDTO（版 2）   TodoItem
//                     TodoItemV1DTO（版 1、読むときだけ）

import Foundation
import TodoCore

// Ceremony: このファイルの型はすべて、Codable（または Decodable）を付けるだけで JSON との変換を Swift が自動で作る。
//   プロパティ名がそのまま JSON のキー名になる。処理は書いていない。
//   `<Item: Codable>` は型引数: 中に入るタスクの型を、使う側（版 1 か版 2 か）で差し込む。

/// 版を見分けるために、先に読む部分
struct FileHeaderDTO: Decodable {
    var format: String
    var schemaVersion: Int
}

struct WorkspaceFileDTO<Item: Codable>: Codable {
    var format: String
    var schemaVersion: Int
    var workspace: WorkspaceDTO<Item>
}

struct WorkspaceDTO<Item: Codable>: Codable {
    var id: String
    var name: String
    var categories: [CategoryDTO<Item>]
    var createdAt: String
    var updatedAt: String
}

struct CategoryDTO<Item: Codable>: Codable {
    var id: String
    var name: String
    var color: String
    var tasks: [Item]
    var createdAt: String
}

/// 版 2 のタスク
struct TodoItemDTO: Codable {
    var id: String
    var content: String
    // 任意の項目。キーが無くても null でも nil。書くときはキーを省く
    var due: String?
    var completedAt: String?
    var createdAt: String
}

/// 版 1 のタスク。読むときだけ使う（data_model_spec §10.1）
struct TodoItemV1DTO: Codable {
    var id: String
    var title: String
    var note: String
    var due: String?
    var completedAt: String?
    var createdAt: String
}

// MARK: - ドメイン → DTO
// Wiring: 以下 3 つは、TodoCore の型を DTO に詰め替えるだけ（日時と UUID を文字列にする）。
// 書くのは常に版 2 の形なので、型引数は TodoItemDTO に決めている

extension WorkspaceDTO<TodoItemDTO> {
    init(_ w: Workspace) {
        self.init(
            id: w.id.uuidString, name: w.name,
            categories: w.categories.map(CategoryDTO.init),
            createdAt: ISODate.format(w.createdAt), updatedAt: ISODate.format(w.updatedAt)
        )
    }
}

extension CategoryDTO<TodoItemDTO> {
    init(_ c: TodoCategory) {
        self.init(
            id: c.id.uuidString, name: c.name, color: c.color.rawValue,
            tasks: c.tasks.map(TodoItemDTO.init), createdAt: ISODate.format(c.createdAt)
        )
    }
}

extension TodoItemDTO {
    init(_ t: TodoItem) {
        self.init(
            id: t.id.uuidString, content: t.content,
            due: t.due?.string, completedAt: t.completedAt.map(ISODate.format),
            createdAt: ISODate.format(t.createdAt)
        )
    }
}

/// ファイルの形式に関わる定数の置き場（Ceremony: case の無い enum を名前空間として使う）
public enum WorkspaceFormat {
    public static let format = "todo-workspace"
    public static let schemaVersion = 2
    /// インポートするファイルの上限。性能の目安（5,000 件 ≒ 2 MB）の 10 倍（data_model_spec §7）
    public static let maxImportBytes = 20 * 1024 * 1024
}
