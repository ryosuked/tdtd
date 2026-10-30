// ScenarioTests.swift — 道具としての一連の流れのテスト（Features）
//
// 画面と同じ呼び方で AppModel・WorkspaceStore を動かし、使う人の流れが通ることを確かめる。
// 細かい値や表記（検証の場所・文言・正規化の表など）は見ない。それは各パッケージの Detail のテストの役目。
// - 時計と ID は TestEnvironment の偽物で、結果を毎回同じにする
// - ファイルは一時フォルダに書く。「起動し直す」は、同じフォルダで AppModel を作り直すこと
// - 保存は 1 秒待たずに flushAll で書き切る
//
// 流し方: scripts/test.sh scenario

import Foundation
import Testing
import Features
import Persistence
import TodoCore

/// 1 つのテストで使う、一時フォルダ・偽の時計・偽の ID
@MainActor
final class TestEnvironment {
    let root = FileManager.default.temporaryDirectory.appending(path: "TodoScenario-\(UUID().uuidString)")
    private var seconds: TimeInterval = 0
    private var lastID = 0

    deinit { try? FileManager.default.removeItem(at: root) }

    /// `place` ごとに別の置き場所（別の Mac の代わり）。同じ `place` で作り直すと「起動し直し」になる
    func makeModel(place: String = "main") -> AppModel {
        AppModel(
            repository: WorkspaceRepository(root: root.appending(path: place)),
            now: { [unowned self] in
                seconds += 1
                return Date(timeIntervalSince1970: 1_761_206_400 + seconds)
            },
            newID: { [unowned self] in
                lastID += 1
                return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", lastID))!
            }
        )
    }

    /// 起動して読み込んだ AppModel
    func launch(place: String = "main") async -> AppModel {
        let model = makeModel(place: place)
        await model.load()
        return model
    }
}

/// リポジトリのルートの `fixtures/`
private let fixtures = URL(filePath: #filePath)
    .deletingLastPathComponent()  // Scenario
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // Features
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // ルート
    .appending(path: "fixtures")

@MainActor
@Suite struct ScenarioTests {
    @Test func 作って編集して保存し起動し直すと同じものが出る() async throws {
        let env = TestEnvironment()
        let model = await env.launch()
        #expect(model.stores.isEmpty)

        model.addWorkspace(name: "仕事")
        let store = try #require(model.selectedStore)
        #expect(store.addCategory(name: "今日"))
        #expect(store.addCategory(name: "来週"))
        let (today, nextWeek) = (store.workspace.categories[0].id, store.workspace.categories[1].id)
        #expect(store.addTask(content: "見積もりを出す\n金額は先方と相談", to: today))
        #expect(store.addTask(content: "請求書", to: today))
        let (estimate, invoice) = (store.workspace.categories[0].tasks[0].id, store.workspace.categories[0].tasks[1].id)
        #expect(store.setContent(estimate, "見積もりを出す\n金額は来週決める"))
        store.setCompleted(estimate, true)
        store.setDue(invoice, LocalDate(year: 2026, month: 11, day: 2))
        store.moveTaskToEnd(invoice, of: nextWeek)
        await model.flushAll()

        let reopened = await env.launch()
        #expect(reopened.stores.map(\.workspace) == [store.workspace])
        #expect(reopened.selectedID == store.id)
        #expect(model.errorMessage == nil && reopened.errorMessage == nil)
    }

    @Test func 決まりに合わない入力はデータを変えずに誤りを出す() async throws {
        let env = TestEnvironment()
        let model = await env.launch()
        model.addWorkspace(name: "仕事")
        let store = try #require(model.selectedStore)
        #expect(store.addCategory(name: "今日"))
        let before = store.workspace

        #expect(!store.addTask(content: " \n ", to: before.categories[0].id))
        #expect(model.errorMessage != nil)
        model.errorMessage = nil
        #expect(!store.addCategory(name: "改行\nあり"))
        #expect(model.errorMessage != nil)
        #expect(store.workspace == before)
    }

    @Test func 書き出したファイルを別の置き場所で読み込み置き換えや複製ができる() async throws {
        let env = TestEnvironment()
        let model = await env.launch()
        model.addWorkspace(name: "仕事")
        let store = try #require(model.selectedStore)
        #expect(store.addCategory(name: "今日"))
        #expect(store.addTask(content: "請求書", to: store.workspace.categories[0].id))
        let file = env.root.appending(path: "仕事.json")
        try #require(model.exportData(store.id)).write(to: file)

        // 初めて読み込む: そのまま足される
        let other = await env.launch(place: "other")
        await other.importFile(at: file)
        #expect(other.stores.map(\.workspace) == [store.workspace])

        // 同じものをもう一度: 確認を待つ → 複製として追加すると、ID を振り直して別のものになる
        await other.importFile(at: file)
        #expect(other.pendingImport?.id == store.id)
        other.resolvePendingImport(replace: false)
        #expect(other.stores.count == 2)
        #expect(other.stores[1].id != store.id)
        #expect(other.stores[1].workspace.categories.map(\.name) == ["今日"])

        // 手元で変えてから読み込み、置き換えると、ファイルの中身に戻る
        let imported = other.stores[0]
        #expect(imported.addCategory(name: "手元で足した"))
        await other.importFile(at: file)
        other.resolvePendingImport(replace: true)
        #expect(imported.workspace == store.workspace)

        await other.flushAll()
        let reopened = await env.launch(place: "other")
        #expect(reopened.stores.count == 2)
        #expect(other.errorMessage == nil)
    }

    @Test func 版1のファイルを読み込むと版2として扱われる() async throws {
        let env = TestEnvironment()
        let model = await env.launch()
        await model.importFile(at: fixtures.appending(path: "valid/v1-basic.json"))
        let store = try #require(model.selectedStore)
        #expect(store.workspace.categories[0].tasks[0].content == "見積もりを出す\n先方に確認してから\n2 行目")

        // 書き出すと版 2 の形になる
        let data = try #require(model.exportData(store.id))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 2)
        #expect(model.errorMessage == nil)
    }

    @Test func 壊れたファイルは退避してほかは読める() async throws {
        let env = TestEnvironment()
        let model = await env.launch()
        model.addWorkspace(name: "仕事")
        await model.flushAll()
        let broken = env.root.appending(path: "main/workspaces/broken.json")
        try Data("{ 壊れている".utf8).write(to: broken)

        let reopened = await env.launch()
        #expect(reopened.stores.map(\.workspace.name) == ["仕事"])
        #expect(reopened.errorMessage?.contains("broken.json") == true)
        let damaged = try FileManager.default.contentsOfDirectory(atPath: env.root.appending(path: "main/damaged").path())
        #expect(damaged.count == 1)
    }

    @Test func 消したワークスペースは起動し直しても戻らない() async throws {
        let env = TestEnvironment()
        let model = await env.launch()
        model.addWorkspace(name: "残す")
        model.addWorkspace(name: "消す")
        await model.flushAll()
        model.deleteWorkspace(try #require(model.selectedID))
        await model.flushAll()

        let reopened = await env.launch()
        #expect(reopened.stores.map(\.workspace.name) == ["残す"])
    }

    @Test func 表示の状態と並び順は起動し直しても残る() async throws {
        let env = TestEnvironment()
        let model = await env.launch()
        model.addWorkspace(name: "A")
        model.addWorkspace(name: "B")
        let b = try #require(model.selectedID)
        model.updateViewState(b) {
            $0.mode = .list
            $0.hideCompleted = true
        }
        model.moveWorkspaces(fromOffsets: [1], toOffset: 0)
        await model.flushAll()

        let reopened = await env.launch()
        #expect(reopened.stores.map(\.workspace.name) == ["B", "A"])
        #expect(reopened.selectedID == b)
        #expect(reopened.viewState(b).mode == .list)
        #expect(reopened.viewState(b).hideCompleted)
    }
}
