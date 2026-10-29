// WorkspaceRepository.swift — ファイルの置き場所と入出力（Persistence）
//
// アプリの中でファイルに触るのはここだけ。actor なので、呼び出しは MainActor の外で順に実行される。
// 呼ぶ側は Features の AppModel（読み込み・インポート・表示の状態）と WorkspaceStore（保存）。
//
// 置き場所（root 以下）:
//   workspaces/<ID>.json  ワークスペース 1 つ = 1 ファイル
//   damaged/              起動時に読めなかったファイルの退避先
//   app_state.json        表示の状態（AppState.swift）
//
// レビューの観点:
// - 読めないファイルを上書き・削除せず、退避しているか（データを失わせない）
// - 書き込みが原子的か（.atomic）

import Foundation
import TodoCore

/// ファイルの置き場所と読み書き（data_model_spec §1・§8）。
/// actor にして、エンコードと書き込みを MainActor の外で行う
///
/// actor は「同時に 1 つの処理しか中に入れない入れ物」。呼ぶ側は await を付けて順番を待つ。
/// そのため、2 つの保存が同時に同じファイルへ書くことは起きない。画面のスレッドも止めない
public actor WorkspaceRepository {
    public struct LoadResult: Sendable {
        public var workspaces: [Workspace]
        public var appState: AppState
        /// 読めずに `damaged/` へ移したファイルの名前
        public var damagedFiles: [String]
    }

    private let root: URL
    private var workspacesDir: URL { root.appending(path: "workspaces", directoryHint: .isDirectory) }
    private var damagedDir: URL { root.appending(path: "damaged", directoryHint: .isDirectory) }
    private var appStateURL: URL { root.appending(path: "app_state.json") }
    private let fm = FileManager.default

    public init(root: URL) {
        self.root = root
    }

    /// 既定の置き場所（Application Support の下）
    public static func defaultRoot() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Todo", directoryHint: .isDirectory)
    }

    public func loadAll() throws -> LoadResult {
        try fm.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
        var workspaces: [Workspace] = []
        var damaged: [String] = []
        let files = try fm.contentsOfDirectory(at: workspacesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        for url in files {
            do {
                workspaces.append(try WorkspaceCodec.decode(Data(contentsOf: url)))
            } catch {
                // 上書きしない。退避して知らせる。
                // 置いたままにすると、同じ ID で新しく保存したときに上書きされて元に戻せなくなる
                try moveToDamaged(url)
                damaged.append(url.lastPathComponent)
            }
        }
        // 表示の状態は失っても困らないので、読めなければ初めの値にする（退避しない）。
        // `try?` は「誤りなら nil にする」、`??` は「nil なら右の値を使う」
        let appState = (try? JSONDecoder().decode(AppState.self, from: Data(contentsOf: appStateURL))) ?? AppState()
        return LoadResult(workspaces: order(workspaces, by: appState), appState: appState, damagedFiles: damaged)
    }

    /// encode の中の読み直しの確かめに通らなければ、書かずに誤りを投げる（前に書いたファイルが残る）
    public func save(_ workspace: Workspace) throws {
        try fm.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
        try WorkspaceCodec.encode(workspace).write(to: fileURL(workspace.id), options: .atomic)
    }

    public func delete(_ id: UUID) throws {
        let url = fileURL(id)
        if fm.fileExists(atPath: url.path(percentEncoded: false)) {
            try fm.removeItem(at: url)
        }
    }

    /// インポートするファイルを読む。上限を超えるものは中身を読む前に断る（data_model_spec §7）
    public func readImportFile(at url: URL) throws -> Workspace {
        // サンドボックスの外のファイルは、利用者が選んだものだけ、この開始と終了の間に読める
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= WorkspaceFormat.maxImportBytes else {
            throw WorkspaceFileError(kind: .tooLarge, path: "")
        }
        return try WorkspaceCodec.decode(Data(contentsOf: url))
    }

    public func saveAppState(_ state: AppState) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: appStateURL, options: .atomic)
    }

    private func fileURL(_ id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString).json")
    }

    private func moveToDamaged(_ url: URL) throws {
        try fm.createDirectory(at: damagedDir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        try fm.moveItem(at: url, to: damagedDir.appending(path: "\(stamp)-\(url.lastPathComponent)"))
    }

    /// `workspaceOrder` の順。載っていないものは `createdAt` の順に末尾へ
    private func order(_ workspaces: [Workspace], by state: AppState) -> [Workspace] {
        let rank = Dictionary(uniqueKeysWithValues: state.workspaceOrder.enumerated().map { ($1, $0) })
        return workspaces.sorted { a, b in
            switch (rank[a.id], rank[b.id]) {
            case let (x?, y?): x < y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.createdAt < b.createdAt
            }
        }
    }
}
