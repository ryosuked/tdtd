// WorkspaceCodecTests.swift — Persistence の細部のテスト
//
// 検証の場所と理由まで見る。一連の流れは Features の Tests/Scenario で見る（CLAUDE.md §4）。
// リポジトリのルートの fixtures/ を読む。fixtures/ は保存形式の契約（CLAUDE.md §4）。
// - WorkspaceCodecTests: 正しいファイルが読めること、読んで書くと元と一致すること、版 1 からの移行、
//   正規化、誤りのファイル（fixtures/invalid/）をそれぞれの場所と理由で拒否すること
// - WriteCheckTests: 読めないデータを書かない（書く前の読み直しの確かめ）
// - WorkspaceRepositoryTests: 保存・読み込み・壊れたファイルの退避（一時フォルダで行う）

import Foundation
import Testing
@testable import Persistence
import TodoCore

/// リポジトリのルートの `fixtures/`（保存形式の契約）
private let fixtures = URL(filePath: #filePath)
    .deletingLastPathComponent()  // Detail
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // Persistence
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // ルート
    .appending(path: "fixtures")

private func fixture(_ path: String) throws -> Data {
    try Data(contentsOf: fixtures.appending(path: path))
}

/// テストごとの一時フォルダ（使い終わったら消す）
private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "TodoTests-\(UUID().uuidString)")
}

/// JSON の値として比べる（キーの並び・空白は問わない）
private func jsonValue(_ data: Data) throws -> NSObject {
    try JSONSerialization.jsonObject(with: data) as! NSObject
}

@Suite struct WorkspaceCodecTests {
    @Test func decodesValidFile() throws {
        let ws = try WorkspaceCodec.decode(fixture("valid/basic.json"))
        #expect(ws.name == "仕事")
        #expect(ws.categories.map(\.name) == ["企画", "空のカテゴリ"])
        #expect(ws.categories[0].color == .blue)
        #expect(ws.categories[0].tasks[0].content == "見積もりを出す\n先方に確認してから\n2 行目")
        #expect(ws.categories[0].tasks[0].due == LocalDate(year: 2026, month: 10, day: 30))
        #expect(ws.categories[0].tasks[0].completedAt == nil)
        #expect(ws.categories[0].tasks[1].isCompleted)
    }

    /// 読んで書いた結果が、JSON の値として元と一致する（data_model_spec §5）
    @Test func roundTripKeepsJSONValue() throws {
        let original = try fixture("valid/basic.json")
        let written = try WorkspaceCodec.encode(WorkspaceCodec.decode(original))
        #expect(try jsonValue(written) == jsonValue(original))
    }

    @Test func acceptsLowercaseUUIDAndNoFractionAndNull() throws {
        let json = """
        {"format":"todo-workspace","schemaVersion":2,"workspace":{
          "id":"6f1c2d3e-4a5b-4c6d-8e7f-9a0b1c2d3e4f","name":"家",
          "createdAt":"2026-10-23T08:00:00Z","updatedAt":"2026-10-23T08:00:00Z",
          "categories":[{"id":"0d3a6c2e-5b1f-4e2a-9c61-2f1b7a9e4c10","name":"買い物","color":"green",
            "createdAt":"2026-10-23T08:00:00Z",
            "tasks":[{"id":"a7e2f1b4-3c5d-4e6f-8a9b-0c1d2e3f4a5b","content":"牛乳",
              "due":null,"completedAt":null,"createdAt":"2026-10-23T08:00:00Z","unknownField":1}]}]}}
        """
        let ws = try WorkspaceCodec.decode(Data(json.utf8))
        #expect(ws.id == UUID(uuidString: "6F1C2D3E-4A5B-4C6D-8E7F-9A0B1C2D3E4F"))
        #expect(ws.categories[0].tasks[0].due == nil)
        // 書くときは任意の項目のキーを省く
        let written = String(decoding: try WorkspaceCodec.encode(ws), as: UTF8.self)
        #expect(!written.contains("completedAt"))
        #expect(!written.contains("unknownField"))
    }

    /// 版 1 は読むときに移す（data_model_spec §10.1）
    @Test func migratesVersion1() throws {
        let v1 = try WorkspaceCodec.decode(fixture("valid/v1-basic.json"))
        let v2 = try WorkspaceCodec.decode(fixture("valid/basic.json"))
        #expect(v1 == v2)
        // 書くと版 2 になる
        #expect(try jsonValue(WorkspaceCodec.encode(v1)) == jsonValue(fixture("valid/basic.json")))
    }

    /// 版 1 のアプリが書いた、タイトルに改行の入ったファイルも読める
    @Test func migratesVersion1WithNewlineInTitle() throws {
        let ws = try WorkspaceCodec.decode(fixture("valid/v1-newline-title.json"))
        #expect(ws.categories[1].tasks[0].content == "貼り付けた文\n \n2 段落目")
    }

    /// 貼り付けで混ざる文字は、誤りにせずそろえて読む（data_model_spec §3.3）
    @Test func normalizesTextOnRead() throws {
        let ws = try WorkspaceCodec.decode(fixture("valid/v2-needs-normalize.json"))
        #expect(ws.name == "仕事")
        #expect(ws.categories[0].tasks[0].content == "見積もりを出す\n先方に確認してから\n\u{3000}2 行目")
        // 書くと、そろえた形になる
        let written = try WorkspaceCodec.encode(ws)
        #expect(try jsonValue(written) == jsonValue(fixture("valid/v2-needs-normalize.expected.json")))
        // そろえた形は、読んで書いても変わらない
        #expect(try WorkspaceCodec.encode(WorkspaceCodec.decode(written)) == written)
    }

    @Test func normalizesTextOnMigration() throws {
        let ws = try WorkspaceCodec.decode(fixture("valid/v1-needs-normalize.json"))
        // タイトルの末尾の CR LF ＋ つなぎの改行 → 空行 1 つ。U+2028 → 改行
        #expect(ws.categories[0].tasks[0].content == "見積もりを出す\n\n先方に確認してから\n2 行目")
    }

    @Test(arguments: [
        ("V1-not-json", WorkspaceFileError.Kind.notJSON, ""),
        ("V2-wrong-format", .wrongFormat, "format"),
        ("V2-newer-version", .unsupportedVersion(3), "schemaVersion"),
        ("V3-missing-content", .missingOrWrongType, "workspace.categories[0].tasks[0].content"),
        ("V3-wrong-type", .missingOrWrongType, "workspace.categories[0].tasks"),
        ("V4-bad-due", .invalidValue, "workspace.categories[0].tasks[0].due"),
        ("V4-bad-color", .invalidValue, "workspace.categories[0].color"),
        ("V4-bad-uuid", .invalidValue, "workspace.id"),
        ("V4-local-time", .invalidValue, "workspace.createdAt"),
        ("V5-blank-name", .invalidText(.empty), "workspace.categories[0].name"),
        ("V5-newline-name", .invalidText(.containsNewline), "workspace.categories[0].name"),
        ("V5-blank-content", .invalidText(.empty), "workspace.categories[0].tasks[0].content"),
        ("V5-too-long-content", .invalidText(.tooLong(max: 100_000)), "workspace.categories[0].tasks[0].content"),
        ("V5-v1-blank-title", .invalidText(.empty), "workspace.categories[0].tasks[0].title"),
        ("V5-crlf-name", .invalidText(.containsNewline), "workspace.name"),
        ("V5-invisible-only-content", .invalidText(.empty), "workspace.categories[0].tasks[0].content"),
        ("V6-duplicate-id", .duplicateID, "workspace.categories[1].id"),
    ])
    func rejectsInvalidFile(name: String, kind: WorkspaceFileError.Kind, path: String) throws {
        let data = try fixture("invalid/\(name).json")
        #expect(throws: WorkspaceFileError(kind: kind, path: path)) {
            try WorkspaceCodec.decode(data)
        }
    }
}

@Suite struct WriteCheckTests {
    /// 決まりに合わないデータ（操作を通さずに作ったもの）は書かない
    @Test func refusesToWriteUnreadableData() throws {
        var ws = try WorkspaceCodec.decode(fixture("valid/basic.json"))
        ws.categories[0].name = "改行\n入り"
        #expect(throws: WorkspaceWriteError.self) { try WorkspaceCodec.encode(ws) }
    }

    @Test func repositoryDoesNotOverwriteWithUnreadableData() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "TodoTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = WorkspaceRepository(root: root)
        var ws = try WorkspaceCodec.decode(fixture("valid/basic.json"))
        try await repo.save(ws)
        ws.categories[0].tasks[0].content = " "
        await #expect(throws: WorkspaceWriteError.self) { try await repo.save(ws) }
        // 前に書いた正しいファイルが残っている
        #expect(try await repo.loadAll().workspaces.first?.categories[0].tasks[0].content != " ")
    }
}

@Suite struct WorkspaceRepositoryTests {
    @Test func saveLoadAndQuarantineDamaged() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "TodoTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = WorkspaceRepository(root: root)

        let ws = try WorkspaceCodec.decode(fixture("valid/basic.json"))
        try await repo.save(ws)
        try fixture("invalid/V1-not-json.json")
            .write(to: root.appending(path: "workspaces/broken.json"))
        var state = AppState()
        state[viewStateOf: ws.id].mode = .list
        try await repo.saveAppState(state)

        let result = try await repo.loadAll()
        #expect(result.workspaces == [ws])
        #expect(result.damagedFiles == ["broken.json"])
        #expect(result.appState[viewStateOf: ws.id].mode == .list)
        // 壊れたファイルは消さずに退避されている
        let damaged = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "damaged").path())
        #expect(damaged.count == 1)
    }

    /// 並びの記録（workspaceOrder）の順。記録に無いものは createdAt の順に末尾へ
    @Test func loadAllOrdersByRecordThenCreatedAt() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = WorkspaceRepository(root: root)
        let base = try WorkspaceCodec.decode(fixture("valid/basic.json"))
        var n = 100
        func copy(_ name: String, createdAfter seconds: TimeInterval) -> Workspace {
            var ws = base.withNewIDs {
                n += 1
                return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
            }
            ws.name = name
            ws.createdAt = base.createdAt.addingTimeInterval(seconds)
            return ws
        }
        let all = [copy("A", createdAfter: 3), copy("B", createdAfter: 1), copy("C", createdAfter: 2), copy("D", createdAfter: 0)]
        for ws in all { try await repo.save(ws) }
        var state = AppState()
        state.workspaceOrder = [all[2].id, all[0].id]  // C, A
        try await repo.saveAppState(state)

        #expect(try await repo.loadAll().workspaces.map(\.name) == ["C", "A", "D", "B"])
    }

    @Test func deleteRemovesFileAndIgnoresMissing() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = WorkspaceRepository(root: root)
        let ws = try WorkspaceCodec.decode(fixture("valid/basic.json"))
        try await repo.save(ws)
        try await repo.delete(ws.id)
        try await repo.delete(ws.id)  // 無くても誤りにしない
        #expect(try await repo.loadAll().workspaces.isEmpty)
    }

    /// 上限（20 MB）を超えるファイルは、中身を読む前に断る（data_model_spec §7）
    @Test func readImportFileReadsAndRefusesTooLarge() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = WorkspaceRepository(root: root)
        #expect(try await repo.readImportFile(at: fixtures.appending(path: "valid/basic.json"))
            == WorkspaceCodec.decode(fixture("valid/basic.json")))

        // 中身の無い大きなファイル（ディスクはほとんど使わない）
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let big = root.appending(path: "big.json")
        #expect(FileManager.default.createFile(atPath: big.path(), contents: nil))
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(WorkspaceFormat.maxImportBytes + 1))
        try handle.close()
        await #expect(throws: WorkspaceFileError(kind: .tooLarge, path: "")) {
            try await repo.readImportFile(at: big)
        }
    }

    @Test func defaultRootIsTodoFolder() throws {
        #expect(try WorkspaceRepository.defaultRoot().lastPathComponent == "Todo")
    }
}
