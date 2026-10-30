// WorkspaceView.swift — 1 つのワークスペースの画面（Features）
//
// 中央: 短冊表示（ColumnsView）か 1 欄表示（ListModeView）。右: 詳細のペイン（TaskInspector）。
// ツールバー: 表示の切り替え、完了を隠す、カテゴリの追加、書き出し、詳細のペインの出し入れ。
// 選んでいるタスクの ID（selectedTaskID）はここで持ち、両方の表示と詳細のペインに渡す。

import SwiftUI
import Persistence
import TodoCore
import UniformTypeIdentifiers

/// 1 つのワークスペース。短冊表示と 1 欄表示を切り替える（requirements F4）
struct WorkspaceView: View {
    let model: AppModel
    let store: WorkspaceStore
    @State private var exportDocument: JSONFileDocument?
    /// 選んでいるタスク。ワークスペースを切り替えると消える（保存しない）
    @State private var selectedTaskID: UUID?
    @State private var showsInspector = true

    private var viewState: WorkspaceViewState { model.viewState(store.id) }

    var body: some View {
        Group {
            if store.workspace.categories.isEmpty {
                ContentUnavailableView {
                    Label("カテゴリがありません", systemImage: "rectangle.split.3x1")
                } actions: {
                    Button("カテゴリを作る", action: addCategory)
                }
            } else {
                switch viewState.mode {
                case .columns:
                    ColumnsView(store: store, hideCompleted: viewState.hideCompleted, selection: $selectedTaskID)
                case .list:
                    ListModeView(model: model, store: store, hideCompleted: viewState.hideCompleted, selection: $selectedTaskID)
                }
            }
        }
        .navigationTitle(store.workspace.name)
        // .inspector: 右側に出し入れできるペイン（macOS 14・iPadOS 17 から）
        .inspector(isPresented: $showsInspector) {
            TaskInspector(store: store, taskID: selectedTaskID)
                .inspectorColumnWidth(min: 260, ideal: 340, max: 600)
        }
        .onChange(of: selectedTaskID) { _, id in
            if id != nil { showsInspector = true }
        }
        .toolbar {
            ToolbarItem {
                Picker("表示", selection: binding(\.mode)) {
                    Label("短冊", systemImage: "rectangle.split.3x1").tag(DisplayMode.columns)
                    Label("1 欄", systemImage: "list.bullet").tag(DisplayMode.list)
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Toggle("完了を隠す", systemImage: "checkmark.circle.badge.xmark", isOn: binding(\.hideCompleted))
            }
            ToolbarItem {
                Button("カテゴリを追加", systemImage: "rectangle.badge.plus", action: addCategory)
            }
            ToolbarItem {
                Button("書き出す", systemImage: "square.and.arrow.up") {
                    exportDocument = model.exportData(store.id).map(JSONFileDocument.init)
                }
            }
            ToolbarItem {
                Toggle("詳細", systemImage: "sidebar.right", isOn: $showsInspector)
            }
        }
        .fileExporter(
            isPresented: $exportDocument.isPresent(),
            document: exportDocument,
            contentType: .json,
            defaultFilename: store.workspace.name
        ) { result in
            if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
        }
    }

    /// 仮の名前で末尾に足す。名前は見出しのメニューから変える
    private func addCategory() {
        store.addCategory(name: "新しいカテゴリ")
    }

    /// Wiring: 表示の状態（AppModel が持つ）の 1 項目を、ツールバーの部品に結びつける口を作る。
    /// `\.mode` のような KeyPath は「どの項目か」を値として渡す書き方。`<T>` は項目の型（Bool など）に合わせる型引数
    private func binding<T>(_ keyPath: WritableKeyPath<WorkspaceViewState, T>) -> Binding<T> {
        Binding(
            get: { model.viewState(store.id)[keyPath: keyPath] },
            set: { value in model.updateViewState(store.id) { $0[keyPath: keyPath] = value } }
        )
    }
}

/// 書き出し用の文書。中身は WorkspaceCodec が作った JSON
///
/// Ceremony: .fileExporter がこの形（FileDocument）を求めるので用意している。
/// 中身は Data をそのまま渡すだけで、読み込み側（init(configuration:)）はこのアプリでは使わない
struct JSONFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
