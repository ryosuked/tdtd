// WorkspaceFile.swift — ファイル用の型（Persistence）
//
// JSON をそのまま受けるための型（DTO）。値は文字列のまま持ち、検証は WorkspaceCodec.swift の Validator で行う。
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

/// ファイルの形式に関わる定数の置き場（Ceremony: case の無い enum を名前空間として使う）
public enum WorkspaceFormat {
    public static let format = "todo-workspace"
    public static let schemaVersion = 2
    /// 読める版。古い版は読むときに移す
    public static let readableVersions = 1...2
    /// インポートするファイルの上限。性能の目安（5,000 件 ≒ 2 MB）の 10 倍（data_model_spec §7）
    public static let maxImportBytes = 20 * 1024 * 1024
}
