// Display.swift — 表示のための導出（TodoCore）
//
// 画面に出す形を、保存しているデータから導き出す純粋関数。ここで作ったものは保存しない。
// - DisplayMode: 短冊表示と 1 欄表示の区別（値は Persistence の AppState に保存）
// - listSections: 1 欄表示の並び（カテゴリの順にタスクをつなげる）
// - preview: 一覧に出す冒頭 3 行の切り出し
// 画面（SwiftUI）のコードは Features にある。ここは画面に渡す値を作るだけ。
//
// レビューの観点:
// - preview は全文を画面に渡さないための切り出し。長い中身でも計算量が冒頭だけで済むか

import Foundation

/// 表示モード（requirements F4）。データの形は変えず、見せ方だけを変える
public enum DisplayMode: String, CaseIterable, Sendable {
    /// 短冊表示: カテゴリごとの列を横に並べる
    case columns
    /// 1 欄表示: カテゴリの順につなげ、見出しで区切る
    case list
}

/// 1 欄表示の 1 区切り（カテゴリの見出しと、その中のタスク）
public struct ListSection: Equatable, Sendable, Identifiable {
    public var category: TodoCategory
    public var tasks: [TodoItem]
    /// Ceremony: Identifiable の約束で id が要る。区切りはカテゴリごとなので、カテゴリの id をそのまま使う
    public var id: UUID { category.id }
}

extension Workspace {
    /// 1 欄表示の並びを導き出す。保存しない（data_model_spec §1）
    public func listSections(hideCompleted: Bool) -> [ListSection] {
        categories.map { category in
            ListSection(category: category, tasks: category.visibleTasks(hideCompleted: hideCompleted))
        }
    }
}

extension TodoCategory {
    public func visibleTasks(hideCompleted: Bool) -> [TodoItem] {
        hideCompleted ? tasks.filter { !$0.isCompleted } : tasks
    }
}

extension TodoItem {
    /// 一覧に出す行数（requirements F4-8）。static は「型に 1 つだけある値」（タスクごとではない）
    public static let previewLines = 3
    /// 1 行あたりに切り出す最大の文字数。改行の無い長文でも、画面に渡す文字列を小さく保つため。
    /// 列の幅（280pt）に 3 行並べても余る量にした
    public static let previewLineLength = 200

    /// 一覧に出す冒頭部分。長い中身でも表示の重さが変わらないように、先頭から切り出す。
    /// 先頭の空行は飛ばす。切った場合は `isTruncated` が true
    public var preview: (text: String, isTruncated: Bool) {
        var lines: [Substring] = []
        var truncated = false
        // "\r\n" は 1 文字（書記素クラスタ）なので、"\n" ではなく isNewline で分ける
        for line in content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if lines.isEmpty, line.allSatisfy(\.isWhitespace) { continue }
            if lines.count == Self.previewLines {
                truncated = true
                break
            }
            if line.count > Self.previewLineLength {
                lines.append(line.prefix(Self.previewLineLength))
                truncated = true
            } else {
                lines.append(line)
            }
        }
        return (lines.joined(separator: "\n"), truncated)
    }
}
