// AppModel.swift — アプリ全体の状態（Features）
//
// 画面の一番上（RootView）が持つ状態。ワークスペースの一覧（WorkspaceStore の配列）、
// 表示の状態（AppState）、誤りの表示、インポートの途中の状態を持つ。
// ロジックは持たず、TodoCore の関数と Persistence の WorkspaceRepository を呼ぶだけ。
//
// レビューの観点:
// - 誤りの表示は errorMessage 1 か所に集めているか（RootView の alert が出す）
// - ファイルの入出力は Task の中で await し、画面の応答を止めていないか

import Foundation
import Observation
import Persistence
import TodoCore

/// アプリ全体の状態: ワークスペースの一覧、表示の状態、誤りの表示、インポート
///
/// 読み方:
/// - class は「参照型」: コピーされず、画面のどこから見ても同じ 1 つを指す（struct と違う）。final は継承させない印
/// - @Observable: 中の値が変わると、その値を使っている画面が自動で描き直される
/// - @MainActor: 画面と同じ流れ（メインスレッド）でだけ動く。画面の状態を安全に書き換えるため
/// - `public private(set) var`: 外から読めるが、書き換えられるのはこのクラスの中だけ
@Observable @MainActor
public final class AppModel {
    public private(set) var stores: [WorkspaceStore] = []
    public private(set) var appState = AppState()
    public private(set) var isLoaded = false
    /// 誤りは 1 か所に出す
    public var errorMessage: String?
    /// ID がすでにあるワークスペースのインポート。置き換えるか複製するかを選んでもらう
    public var pendingImport: Workspace?

    /// 選んでいるワークスペース。変わるたびに「最後に開いたもの」として保存する
    public var selectedID: UUID? {
        didSet {
            guard selectedID != oldValue else { return }
            appState.lastOpenedWorkspaceId = selectedID
            saveAppState()
        }
    }

    // @ObservationIgnored: 変わっても画面に関係ない値。描き直しの対象から外す
    @ObservationIgnored private let repository: WorkspaceRepository
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let newID: () -> UUID
    /// 後ろで動かしているファイルの入出力の、最後の 1 つ（inBackground）。次の入出力と flushAll がこれを待つ
    @ObservationIgnored private var lastBackground: Task<Void, Never>?

    // 現在時刻と ID の作り方を外から渡せるようにしている（テストで決まった値に替えるため）。
    // 省略すると本物（Date.init・UUID.init）になる。@escaping は「受け取った関数を後で使うために保持する」の印
    public init(
        repository: WorkspaceRepository,
        now: @escaping () -> Date = Date.init,
        newID: @escaping () -> UUID = UUID.init
    ) {
        self.repository = repository
        self.now = now
        self.newID = newID
    }

    /// 既定の置き場所で作る（App/TodoApp.swift から呼ぶ）。テストでは init に偽物の時計と ID を渡す
    public static func live() -> AppModel {
        let root = (try? WorkspaceRepository.defaultRoot())
            ?? FileManager.default.temporaryDirectory.appending(path: "Todo")
        return AppModel(repository: WorkspaceRepository(root: root))
    }

    public var selectedStore: WorkspaceStore? {
        stores.first { $0.id == selectedID }
    }

    // MARK: 読み込み

    /// 起動時に 1 回だけ呼ぶ（RootView の .task）。読めなかったファイルは退避済みで、名前だけを知らせる
    ///
    /// async は「途中で待つことがある関数」の印。中の `await` で、ファイルの読み込み（actor）が終わるのを待つ。
    /// 待っている間も画面は止まらない
    public func load() async {
        guard !isLoaded else { return }
        do {
            let result = try await repository.loadAll()
            appState = result.appState
            stores = result.workspaces.map(makeStore)
            // 並びの記録に無いファイル（インポート直後に落ちたなど）があれば、記録を今の並びに合わせる
            if appState.workspaceOrder != stores.map(\.id) { syncOrder() }
            // 最後に開いていたものを選ぶ。消えていたら先頭
            let last = appState.lastOpenedWorkspaceId
            selectedID = stores.contains { $0.id == last } ? last : stores.first?.id
            if !result.damagedFiles.isEmpty {
                errorMessage = "読めないファイルがあったので退避しました: \(result.damagedFiles.joined(separator: ", "))"
            }
        } catch {
            errorMessage = "データを読み込めませんでした。\(error.localizedDescription)"
        }
        isLoaded = true
    }

    // MARK: ワークスペース

    public func addWorkspace(name: String) {
        let t = now().roundedToMilliseconds
        let ws = Workspace(id: newID(), name: name, createdAt: t, updatedAt: t)
        insert(ws)
    }

    public func deleteWorkspace(_ id: UUID) {
        stores.removeAll { $0.id == id }
        appState.workspaces[id.uuidString] = nil
        if selectedID == id { selectedID = stores.first?.id }
        syncOrder()
        inBackground("削除できませんでした。") { try await $0.delete(id) }
    }

    public func moveWorkspaces(fromOffsets source: IndexSet, toOffset destination: Int) {
        stores.move(fromOffsets: source, toOffset: destination)
        syncOrder()
    }

    // MARK: 表示の状態

    public func viewState(_ id: UUID) -> WorkspaceViewState {
        appState[viewStateOf: id]
    }

    public func updateViewState(_ id: UUID, _ change: (inout WorkspaceViewState) -> Void) {
        var state = appState[viewStateOf: id]
        change(&state)
        guard state != appState[viewStateOf: id] else { return }
        appState[viewStateOf: id] = state
        saveAppState()
    }

    // MARK: インポート・エクスポート

    /// ファイルを読み、同じ ID が無ければそのまま足す。あれば pendingImport に置き、
    /// RootView の確認（置き換える／複製として追加）を待つ（data_model_spec §9）
    public func importFile(at url: URL) async {
        do {
            let ws = try await repository.readImportFile(at: url)
            if stores.contains(where: { $0.id == ws.id }) {
                pendingImport = ws
            } else {
                insert(ws)
            }
        } catch let error as WorkspaceFileError {
            errorMessage = "読み込めませんでした。" + error.message
        } catch {
            report("読み込めませんでした。", error)
        }
    }

    public func resolvePendingImport(replace: Bool) {
        guard let ws = pendingImport else { return }
        pendingImport = nil
        if replace, let store = stores.first(where: { $0.id == ws.id }) {
            store.replace(with: ws)
            selectedID = ws.id
        } else {
            insert(ws.withNewIDs(newID))
        }
    }

    public func exportData(_ id: UUID) -> Data? {
        guard let store = stores.first(where: { $0.id == id }) else { return nil }
        do {
            return try WorkspaceCodec.encode(store.workspace)
        } catch {
            report("書き出せませんでした。", error)
            return nil
        }
    }

    // MARK: 保存

    /// 待っている保存をすべて書き切る（背面に回る・終了するとき。テストでも使う）。
    /// ワークスペースごとの 1 秒の待ちと、後ろで動かしている入出力（追加・削除・表示の状態）の両方を待つ
    public func flushAll() async {
        for store in stores { await store.flush() }
        await lastBackground?.value
    }

    private func insert(_ ws: Workspace) {
        let store = makeStore(ws)
        stores.append(store)
        syncOrder()
        selectedID = ws.id
        // ファイルは Store の保存で書く（書く経路を 1 つにして、古い中身で上書きしないため）
        store.scheduleSave()
    }

    /// Wiring: WorkspaceStore に、同じ置き場所・時計・ID の作り方と、誤りの知らせ先（errorMessage）を渡して作る。
    /// `[weak self]` は、Store が AppModel を掴みっぱなしにして互いに消えなくなるのを防ぐ書き方
    private func makeStore(_ ws: Workspace) -> WorkspaceStore {
        WorkspaceStore(
            workspace: ws, repository: repository, now: now, newID: newID,
            onError: { [weak self] in self?.errorMessage = $0 }
        )
    }

    private func syncOrder() {
        appState.workspaceOrder = stores.map(\.id)
        saveAppState()
    }

    /// 表示の状態を書く。変更のたびに別の Task で書くので、続けて変えると順が入れ替わりうる（OPEN_ITEMS に記録）
    private func saveAppState() {
        let state = appState
        inBackground("表示の状態を保存できませんでした。") { try await $0.saveAppState(state) }
    }

    /// ファイルの入出力を後ろで動かす。画面の操作は待たずに次へ進み、失敗したら errorMessage に出す。
    /// 1 本の列に並べる（前のものが終わってから始める）ので、書く順が入れ替わらない。flushAll で終わりを待てる。
    /// `Task { }` は「後ろで非同期に動かす」。`@Sendable` は「別の流れに渡してよい関数」の印
    private func inBackground(
        _ failure: String, _ work: @escaping @Sendable (WorkspaceRepository) async throws -> Void
    ) {
        let repository = repository
        let previous = lastBackground
        lastBackground = Task {
            await previous?.value
            do { try await work(repository) } catch { report(failure, error) }
        }
    }

    private func report(_ message: String, _ error: any Error) {
        errorMessage = message + error.localizedDescription
    }
}
