// AppState.swift — 表示の状態（Persistence）
//
// ワークスペースのデータとは別に保存する、端末ごとの見え方の設定（data_model_spec §6）。
// エクスポートしない。壊れていても困らないので、読めなければ黙って初めの値に戻す
// （ワークスペースのファイルとは扱いが違う。WorkspaceRepository.loadAll）。

import Foundation
import TodoCore

/// 表示の状態（data_model_spec §6）。エクスポートしない。壊れていたら初めの値に戻す
///
/// Ceremony: Codable を付けるだけで、app_state.json との変換を Swift が自動で作る（下の WorkspaceViewState も同じ）
public struct AppState: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var workspaceOrder: [UUID] = []
    public var lastOpenedWorkspaceId: UUID?
    /// キーは UUID の文字列。UUID をキーにすると JSONEncoder が配列で書くため
    public var workspaces: [String: WorkspaceViewState] = [:]

    // Ceremony: パッケージの外から、すべて既定の値で作れるようにする空の init（下の WorkspaceViewState も同じ）
    public init() {}

    /// `appState[viewStateOf: id]` の形で、ワークスペースごとの表示の状態を読み書きする口。
    /// まだ無いワークスペースは初めの値を返す
    public subscript(viewStateOf id: UUID) -> WorkspaceViewState {
        get { workspaces[id.uuidString] ?? WorkspaceViewState() }
        set { workspaces[id.uuidString] = newValue }
    }
}

public struct WorkspaceViewState: Codable, Equatable, Sendable {
    public var displayMode: String = DisplayMode.columns.rawValue
    public var hideCompleted: Bool = false
    public var collapsedCategoryIds: [UUID] = []
    public var lastUsedCategoryId: UUID?

    public init() {}

    /// 知らない値は短冊表示にする
    ///
    /// ファイルには文字列（displayMode）で持ち、コードからは DisplayMode（enum）で扱うための変換。
    /// get は読むとき、set は書くときの処理
    public var mode: DisplayMode {
        get { DisplayMode(rawValue: displayMode) ?? .columns }
        set { displayMode = newValue.rawValue }
    }
}
