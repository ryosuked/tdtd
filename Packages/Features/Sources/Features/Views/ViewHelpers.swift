// ViewHelpers.swift — 画面の部品から使う補助（Features）
//
// - renameAlert: 名前を変えるアラート（ワークスペースとカテゴリで共用）
// - Binding.isPresent: 「値があるときだけ出す」アラート・確認・ファイルの保存の出し入れ
// - CategoryColor の色と表示名

import SwiftUI
import TodoCore

// Ceremony: 下の RenameAlert（ViewModifier）を、`.renameAlert(...)` の形で書けるようにするだけ
extension View {
    /// 名前を変える入力のアラート。空白だけの名前は受け付けない
    func renameAlert<Item: Sendable>(
        item: Binding<Item?>, title: LocalizedStringKey, current: KeyPath<Item, String>,
        onCommit: @escaping (Item, String) -> Void
    ) -> some View {
        modifier(RenameAlert(item: item, title: title, current: current, onCommit: onCommit))
    }
}

/// ViewModifier は「ほかの画面に機能を足す部品」。ここではアラートを足す。
/// `<Item>` はワークスペース（WorkspaceStore）とカテゴリ（TodoCategory）のどちらにも使うための型引数
private struct RenameAlert<Item: Sendable>: ViewModifier {
    @Binding var item: Item?
    let title: LocalizedStringKey
    let current: KeyPath<Item, String>
    let onCommit: (Item, String) -> Void
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $item.isPresent()) {
                TextField("名前", text: $text)
                Button("キャンセル", role: .cancel) { item = nil }
                Button("OK") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let item, !trimmed.isEmpty { onCommit(item, trimmed) }
                    item = nil
                }
            }
            // アラートを開くたびに、入力欄を今の名前で埋める（前回の入力が残らないように）
            .onChange(of: item != nil) { _, shown in
                if shown, let item { text = item[keyPath: current] }
            }
    }
}

extension Binding {
    /// 「値があるか」を Bool として読み書きする口。アラートなどの isPresented に渡す。
    /// 閉じる（false を書く）と値を nil に戻す。`where Value == Wrapped?` は「中身が Optional の Binding だけに使える」の意味
    ///
    /// 例: `.alert("エラー", isPresented: $model.errorMessage.isPresent())`
    func isPresent<Wrapped: Sendable>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(get: { wrappedValue != nil }, set: { if !$0 { wrappedValue = nil } })
    }
}

// 以下は、色の名前（TodoCore の CategoryColor）から、画面の色と日本語の表示名への対応表

extension CategoryColor {
    /// パレット名から実際の色へ。ライト・ダークはシステムの色に任せる
    var swatch: Color {
        switch self {
        case .gray: .gray
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        }
    }

    var label: String {
        switch self {
        case .gray: "グレー"
        case .red: "赤"
        case .orange: "オレンジ"
        case .yellow: "黄"
        case .green: "緑"
        case .teal: "青緑"
        case .blue: "青"
        case .indigo: "藍"
        case .purple: "紫"
        case .pink: "ピンク"
        }
    }
}
