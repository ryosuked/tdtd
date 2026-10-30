// WorkspaceCodec.swift — ワークスペースのファイルの読み書きと検証（Persistence）
//
// 読む: Data → FileHeaderDTO で版を見る → 版ごとの DTO →（版 1 なら migrateV1 で版 2 の形へ）→ Validator で検証しつつドメインの型へ
// 書く: ドメインの型 → DTO（WorkspaceFile.swift）→ JSON。書いた結果を読み直して元と一致するのを確かめてから返す
//
// レビューの観点:
// - 検証の V1〜V6（data_model_spec §5）が、どこで確かめられているか
//     V1 JSON として読める        … decodeDTO（JSONDecoder の誤りを変換）
//     V2 format・schemaVersion    … decode の先頭
//     V3 必須の項目・型           … decodeDTO（Codable の keyNotFound・typeMismatch）
//     V4 UUID・日時・日付・色名   … Validator の id・date・localDate・category
//     V5 文字列の決まり           … Validator.text（TodoCore の TextRule.accept）。版 1 のタイトルだけは migrateV1
//     V6 ID の重複                … Validator.id（seenIDs）
// - 版 1 からの移し方（migrateV1）が data_model_spec §10.1 と合っているか
// - 日時のミリ秒を自前で読み書きしている理由（ISODate のコメント）

import Foundation
import TodoCore

/// 読み込みの誤り。最初に見つけた 1 つを、場所と一緒に返す（data_model_spec §5）
///
/// Ceremony: Error の約束を守ると throw で投げられる。CustomStringConvertible は print やテストの失敗表示で使う文字列（description）
public struct WorkspaceFileError: Error, Equatable, CustomStringConvertible {
    public enum Kind: Equatable, Sendable {
        case notJSON            // V1
        case wrongFormat        // V2
        case unsupportedVersion(Int)  // V2
        case missingOrWrongType // V3
        case invalidValue       // V4
        case invalidText(TextRule.Violation)  // V5
        case duplicateID        // V6
        case tooLarge
    }

    public var kind: Kind
    /// 例: `workspace.categories[2].tasks[5].due`
    public var path: String

    public var description: String { "\(kind) at \(path)" }
}

/// 書く前の確かめに通らなかった。自分で読めないファイルを書かないため（data_model_spec §8）
public struct WorkspaceWriteError: Error, CustomStringConvertible {
    /// 読み直したときの誤り。nil なら、読めたが元と一致しなかった
    public var readError: WorkspaceFileError?

    public var description: String {
        readError.map { "written file is not readable: \($0)" } ?? "written file does not round-trip"
    }
}

/// ワークスペースのファイルの読み書き。状態を持たない関数だけなので、case の無い enum（名前空間）にしている
public enum WorkspaceCodec {
    public static func decode(_ data: Data) throws(WorkspaceFileError) -> Workspace {
        // 2 回に分けて読む。先に format と schemaVersion だけを読み、版に合った DTO で読み直す
        let header = try decodeDTO(FileHeaderDTO.self, from: data)
        guard header.format == WorkspaceFormat.format else {
            throw WorkspaceFileError(kind: .wrongFormat, path: "format")
        }
        // 古い版は、先に今の版（2）の DTO に移す。検証は版によらず 1 通り
        let dto: WorkspaceDTO<TodoItemDTO>
        switch header.schemaVersion {
        case 2: dto = try decodeDTO(WorkspaceFileDTO<TodoItemDTO>.self, from: data).workspace
        case 1: dto = try migrateV1(decodeDTO(WorkspaceFileDTO<TodoItemV1DTO>.self, from: data).workspace)
        default: throw WorkspaceFileError(kind: .unsupportedVersion(header.schemaVersion), path: "schemaVersion")
        }
        var validator = Validator()
        return try validator.workspace(dto, path: "workspace")
    }

    /// 書き出す。書いた結果を読み直して、元と一致することを確かめてから返す
    ///
    /// 保存（WorkspaceRepository.save）とエクスポート（AppModel.exportData）の両方がここを通る。
    /// 読み直しは書き出しと同じだけの時間がかかるが、「アプリが書いたのに読めないファイル」を
    /// 二度と作らないための確かめなので、省かない（data_model_spec §8）
    public static func encode(_ workspace: Workspace) throws -> Data {
        let data = try encodeUnchecked(workspace)
        do {
            guard try decode(data) == workspace else { throw WorkspaceWriteError(readError: nil) }
        } catch let error as WorkspaceFileError {
            throw WorkspaceWriteError(readError: error)
        }
        return data
    }

    private static func encodeUnchecked(_ workspace: Workspace) throws -> Data {
        let dto = WorkspaceFileDTO(
            format: WorkspaceFormat.format,
            schemaVersion: WorkspaceFormat.schemaVersion,
            workspace: WorkspaceDTO(workspace)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(dto)
    }

    /// Wiring: JSONDecoder を呼び、Swift の誤り（DecodingError）をこのアプリの誤り（WorkspaceFileError）に包み直す
    private static func decodeDTO<T: Decodable>(_ type: T.Type, from data: Data) throws(WorkspaceFileError) -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            throw mapDecodingError(error)
        } catch {
            throw WorkspaceFileError(kind: .notJSON, path: "")
        }
    }

    /// JSONDecoder の誤りを、検証の番号（V1・V3）と場所（例: workspace.categories[0].name）に読み替える
    private static func mapDecodingError(_ error: DecodingError) -> WorkspaceFileError {
        func path(_ codingPath: [any CodingKey]) -> String {
            codingPath.reduce("") { result, key in
                if let i = key.intValue { return result + "[\(i)]" }
                return result.isEmpty ? key.stringValue : result + "." + key.stringValue
            }
        }
        switch error {
        case .dataCorrupted(let context) where context.codingPath.isEmpty:
            return WorkspaceFileError(kind: .notJSON, path: "")
        case .keyNotFound(let key, let context):
            return WorkspaceFileError(kind: .missingOrWrongType, path: path(context.codingPath + [key]))
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return WorkspaceFileError(kind: .missingOrWrongType, path: path(context.codingPath))
        // Ceremony: 将来 Swift が誤りの種類を増やしても、ここで止まらないための書き方
        @unknown default:
            return WorkspaceFileError(kind: .missingOrWrongType, path: "")
        }
    }
}

// MARK: - 版 1 → 版 2（data_model_spec §10.1）

extension WorkspaceCodec {
    /// 版 1 のタスク（title・note）を、版 2 の形（content）に移す。ほかの階層はそのまま写す。
    ///
    /// 文字列の確かめはここでもする。空のタイトルは、メモとつなぐと空でなくなり、移した後では見つけられないため。
    /// 誤りの場所は版 1 のファイルにあるキー（title・note）で返す。ほかの検証は、移した後に Validator が行う
    fileprivate static func migrateV1(
        _ ws: WorkspaceDTO<TodoItemV1DTO>
    ) throws(WorkspaceFileError) -> WorkspaceDTO<TodoItemDTO> {
        var categories: [CategoryDTO<TodoItemDTO>] = []
        for (ci, c) in ws.categories.enumerated() {
            var tasks: [TodoItemDTO] = []
            for (ti, t) in c.tasks.enumerated() {
                let path = "workspace.categories[\(ci)].tasks[\(ti)]"
                let title = try Validator.text(t.title, .legacyTaskTitle, path: path + ".title")
                let content = try Validator.text(
                    t.note.isEmpty ? title : title + "\n" + t.note, .taskContent, path: path + ".note"
                )
                tasks.append(TodoItemDTO(
                    id: t.id, content: content, due: t.due, completedAt: t.completedAt, createdAt: t.createdAt
                ))
            }
            categories.append(CategoryDTO(id: c.id, name: c.name, color: c.color, tasks: tasks, createdAt: c.createdAt))
        }
        return WorkspaceDTO(
            id: ws.id, name: ws.name, categories: categories, createdAt: ws.createdAt, updatedAt: ws.updatedAt
        )
    }
}

// MARK: - DTO → ドメイン（検証）

/// DTO を検証しながらドメインの型へ変える。最初に見つけた誤りで止める（場所は path で渡していく）。
/// 上から順に確かめるので、誤りが 2 つあるファイルでは、ファイルの中で先に出てくる方を返す
private struct Validator {
    /// V6（ID の重複）のため、読んだ ID をすべて覚えておく。ワークスペース・カテゴリ・タスクを通して重複を許さない
    var seenIDs: Set<UUID> = []

    mutating func workspace(_ dto: WorkspaceDTO<TodoItemDTO>, path: String) throws(WorkspaceFileError) -> Workspace {
        let id = try id(dto.id, path: path + ".id")
        let name = try Self.text(dto.name, .workspaceName, path: path + ".name")
        var categories: [TodoCategory] = []
        for (i, c) in dto.categories.enumerated() {
            categories.append(try category(c, path: "\(path).categories[\(i)]"))
        }
        return Workspace(
            id: id, name: name, categories: categories,
            createdAt: try date(dto.createdAt, path: path + ".createdAt"),
            updatedAt: try date(dto.updatedAt, path: path + ".updatedAt")
        )
    }

    mutating func category(_ dto: CategoryDTO<TodoItemDTO>, path: String) throws(WorkspaceFileError) -> TodoCategory {
        let id = try id(dto.id, path: path + ".id")
        let name = try Self.text(dto.name, .categoryName, path: path + ".name")
        guard let color = CategoryColor(rawValue: dto.color) else {
            throw WorkspaceFileError(kind: .invalidValue, path: path + ".color")
        }
        var tasks: [TodoItem] = []
        for (i, t) in dto.tasks.enumerated() {
            tasks.append(try task(t, path: "\(path).tasks[\(i)]"))
        }
        return TodoCategory(
            id: id, name: name, color: color, tasks: tasks,
            createdAt: try date(dto.createdAt, path: path + ".createdAt")
        )
    }

    mutating func task(_ dto: TodoItemDTO, path: String) throws(WorkspaceFileError) -> TodoItem {
        TodoItem(
            id: try id(dto.id, path: path + ".id"),
            content: try Self.text(dto.content, .taskContent, path: path + ".content"),
            due: try localDate(dto.due, path: path + ".due"),
            completedAt: try dateIfPresent(dto.completedAt, path: path + ".completedAt"),
            createdAt: try date(dto.createdAt, path: path + ".createdAt")
        )
    }

    mutating func id(_ s: String, path: String) throws(WorkspaceFileError) -> UUID {
        guard let uuid = UUID(uuidString: s) else {
            throw WorkspaceFileError(kind: .invalidValue, path: path)
        }
        guard seenIDs.insert(uuid).inserted else {
            throw WorkspaceFileError(kind: .duplicateID, path: path)
        }
        return uuid
    }

    func date(_ s: String, path: String) throws(WorkspaceFileError) -> Date {
        guard let d = ISODate.parse(s) else {
            throw WorkspaceFileError(kind: .invalidValue, path: path)
        }
        return d
    }

    /// 任意の項目の日時。キーが無い・null なら nil
    func dateIfPresent(_ s: String?, path: String) throws(WorkspaceFileError) -> Date? {
        guard let s else { return nil }
        return try date(s, path: path)
    }

    /// 任意の項目の日付。キーが無い・null なら nil
    func localDate(_ s: String?, path: String) throws(WorkspaceFileError) -> LocalDate? {
        guard let s else { return nil }
        guard let d = LocalDate(string: s) else {
            throw WorkspaceFileError(kind: .invalidValue, path: path)
        }
        return d
    }

    /// 文字列の決まりは TodoCore の TextRule に一本化している。
    /// 正規化（data_model_spec §3.3）してから確かめ、正規化した形で持つ。版 1 の移行（migrateV1）からも使う
    static func text(_ s: String, _ rule: TextRule, path: String) throws(WorkspaceFileError) -> String {
        do {
            return try rule.accept(s)
        } catch {
            throw WorkspaceFileError(kind: .invalidText(error), path: path)
        }
    }
}

// MARK: - 日時の書式

/// ISO 8601・UTC。書くときはミリ秒付き、読むときはミリ秒なしも受け付ける（data_model_spec §3.2）。
/// ミリ秒の部分は自前で整数として読み書きする。Foundation の書式は小数を切り捨てるため、
/// 浮動小数点の誤差で `.999` が `.998` になり、往復で値が変わる
enum ISODate {
    private static let seconds = Date.ISO8601FormatStyle()

    static func format(_ date: Date) -> String {
        var (secs, ms) = date.millisecondsSince1970.quotientAndRemainder(dividingBy: 1000)
        if ms < 0 { secs -= 1; ms += 1000 }
        let whole = seconds.format(Date(timeIntervalSince1970: Double(secs)))  // 例: 2026-10-23T08:00:00Z
        let frac = String(ms)
        return whole.dropLast() + "." + String(repeating: "0", count: 3 - frac.count) + frac + "Z"
    }

    static func parse(_ s: String) -> Date? {
        guard s.hasSuffix("Z") else { return nil }
        var body = s.dropLast()
        var ms: Int64 = 0
        if let dot = body.firstIndex(of: ".") {
            let frac = body[body.index(after: dot)...]
            guard frac.count == 3, frac.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int64(frac)
            else { return nil }
            ms = v
            body = body[..<dot]
        }
        guard let whole = try? seconds.parse(body + "Z") else { return nil }
        return Date(millisecondsSince1970: whole.millisecondsSince1970 + ms)
    }
}
