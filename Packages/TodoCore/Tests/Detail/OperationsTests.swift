// OperationsTests.swift — TodoCore の細部のテスト
//
// 値と表記まで見る。一連の流れは Features の Tests/Scenario で見る（CLAUDE.md §4）。
// 時刻と ID は Fixed の決まった値を使う（テストの結果を毎回同じにするため）。
// - OperationsTests: 操作ごとの結果と updatedAt の決まり（data_model_spec §4）、誤りの操作でデータが変わらないこと
// - PreviewTests: 一覧に出す冒頭 3 行の切り出し
// - TextRuleTests・PlainTextTests: 文字列の決まりと正規化（§3.3）
// - LocalDateTests: 日付の文字列の読み書き、Date との変換

import Foundation
import Testing
@testable import TodoCore

/// テスト用の決まった ID と時刻
enum Fixed {
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }
    static func time(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_761_206_400 + seconds)
    }
}

private func emptyWorkspace() -> Workspace {
    Workspace(id: Fixed.id(1), name: "仕事", createdAt: Fixed.time(0), updatedAt: Fixed.time(0))
}

/// カテゴリ A（id 10）とタスク（id 20〜）を持つワークスペース
private func workspace(tasks: [String]) throws -> Workspace {
    var ws = emptyWorkspace()
    try ws.addCategory(id: Fixed.id(10), name: "A", now: Fixed.time(1))
    for (i, content) in tasks.enumerated() {
        try ws.addTask(id: Fixed.id(20 + i), content: content, to: Fixed.id(10), now: Fixed.time(1))
    }
    return ws
}

@Suite struct OperationsTests {
    @Test func addCategoryAppendsAndTouchesUpdatedAt() throws {
        var ws = emptyWorkspace()
        try ws.addCategory(id: Fixed.id(10), name: "企画", now: Fixed.time(5))
        try ws.addCategory(id: Fixed.id(11), name: "開発", now: Fixed.time(6))
        #expect(ws.categories.map(\.name) == ["企画", "開発"])
        #expect(ws.categories[0].color == .gray)
        #expect(ws.categories[0].createdAt == Fixed.time(5))
        #expect(ws.updatedAt == Fixed.time(6))
    }

    @Test func noChangeKeepsUpdatedAt() throws {
        var ws = emptyWorkspace()
        try ws.rename("仕事", now: Fixed.time(9))
        try ws.renameCategory(Fixed.id(99), to: "無い", now: Fixed.time(9))
        #expect(ws.updatedAt == Fixed.time(0))
    }

    @Test func multilineContentIsAllowed() throws {
        var ws = try workspace(tasks: ["1 行目\n2 行目\r\n3 行目"])
        try ws.setContent(Fixed.id(20), "書き換えた\n中身", now: Fixed.time(2))
        #expect(ws.categories[0].tasks[0].content == "書き換えた\n中身")
        #expect(ws.updatedAt == Fixed.time(2))
    }

    /// 決まりに合わない操作は誤りを投げ、データを変えない
    @Test func invalidTextIsRejectedWithoutChange() throws {
        var ws = try workspace(tasks: ["元の中身"])
        let before = ws
        #expect(throws: EditError(rule: .taskContent, violation: .empty)) {
            try ws.setContent(Fixed.id(20), " \n ", now: Fixed.time(2))
        }
        #expect(throws: EditError(rule: .taskContent, violation: .tooLong(max: 100_000))) {
            try ws.addTask(id: Fixed.id(30), content: String(repeating: "あ", count: 100_001), to: Fixed.id(10), now: Fixed.time(2))
        }
        #expect(throws: EditError(rule: .categoryName, violation: .containsNewline)) {
            try ws.renameCategory(Fixed.id(10), to: "1\n2", now: Fixed.time(2))
        }
        #expect(ws == before)
        // ちょうど上限は通る
        try ws.addTask(id: Fixed.id(30), content: String(repeating: "あ", count: 100_000), to: Fixed.id(10), now: Fixed.time(2))
    }

    @Test func completeAndUncomplete() throws {
        var ws = try workspace(tasks: ["見積もり"])
        ws.setCompleted(Fixed.id(20), true, now: Fixed.time(3))
        #expect(ws.categories[0].tasks[0].completedAt == Fixed.time(3))
        // 完了済みをもう一度完了にしても日時は変わらない
        ws.setCompleted(Fixed.id(20), true, now: Fixed.time(4))
        #expect(ws.categories[0].tasks[0].completedAt == Fixed.time(3))
        #expect(ws.updatedAt == Fixed.time(3))
        ws.setCompleted(Fixed.id(20), false, now: Fixed.time(5))
        #expect(ws.categories[0].tasks[0].completedAt == nil)
    }

    @Test func setAndClearDue() throws {
        var ws = try workspace(tasks: ["見積もり"])
        let due = LocalDate(year: 2026, month: 10, day: 30)
        ws.setDue(Fixed.id(20), due, now: Fixed.time(2))
        #expect(ws.categories[0].tasks[0].due == due)
        ws.setDue(Fixed.id(20), nil, now: Fixed.time(3))
        #expect(ws.categories[0].tasks[0].due == nil)
    }

    @Test func moveTaskAcrossCategories() throws {
        var ws = emptyWorkspace()
        try ws.addCategory(id: Fixed.id(10), name: "A", now: Fixed.time(1))
        try ws.addCategory(id: Fixed.id(11), name: "B", now: Fixed.time(1))
        try ws.addTask(id: Fixed.id(20), content: "1", to: Fixed.id(10), now: Fixed.time(1))
        try ws.addTask(id: Fixed.id(21), content: "2", to: Fixed.id(10), now: Fixed.time(1))
        try ws.addTask(id: Fixed.id(22), content: "3", to: Fixed.id(11), now: Fixed.time(1))
        ws.moveTask(Fixed.id(21), to: Fixed.id(11), at: 0, now: Fixed.time(2))
        #expect(ws.categories[0].tasks.map(\.content) == ["1"])
        #expect(ws.categories[1].tasks.map(\.content) == ["2", "3"])
        // 同じカテゴリの中の並べ替え。範囲外の位置は末尾にする
        ws.moveTask(Fixed.id(21), to: Fixed.id(11), at: 99, now: Fixed.time(3))
        #expect(ws.categories[1].tasks.map(\.content) == ["3", "2"])
        #expect(ws.task(Fixed.id(21))?.category.id == Fixed.id(11))
    }

    @Test func deleteCategoryRemovesItsTasks() throws {
        var ws = try workspace(tasks: ["1"])
        ws.deleteCategory(Fixed.id(10), now: Fixed.time(2))
        #expect(ws.categories.isEmpty)
        #expect(ws.task(Fixed.id(20)) == nil)
    }

    @Test func setCategoryColorTouchesUpdatedAt() throws {
        var ws = try workspace(tasks: [])
        ws.setCategoryColor(Fixed.id(10), to: .blue, now: Fixed.time(5))
        #expect(ws.categories[0].color == .blue)
        #expect(ws.updatedAt == Fixed.time(5))
    }

    /// 範囲外の位置は端に丸める。無い ID では何も変えない
    @Test func moveCategoryClampsIndexAndIgnoresUnknownID() throws {
        var ws = try workspace(tasks: [])
        try ws.addCategory(id: Fixed.id(11), name: "B", now: Fixed.time(1))
        try ws.addCategory(id: Fixed.id(12), name: "C", now: Fixed.time(1))
        ws.moveCategory(Fixed.id(12), to: -5, now: Fixed.time(2))
        #expect(ws.categories.map(\.name) == ["C", "A", "B"])
        ws.moveCategory(Fixed.id(12), to: 99, now: Fixed.time(3))
        #expect(ws.categories.map(\.name) == ["A", "B", "C"])
        let before = ws
        ws.moveCategory(Fixed.id(99), to: 0, now: Fixed.time(4))
        #expect(ws == before)
    }

    @Test func deleteTaskAndIgnoreUnknownID() throws {
        var ws = try workspace(tasks: ["1", "2"])
        ws.deleteTask(Fixed.id(20), now: Fixed.time(2))
        #expect(ws.categories[0].tasks.map(\.content) == ["2"])
        let before = ws
        ws.deleteTask(Fixed.id(20), now: Fixed.time(3))
        #expect(ws == before)
    }

    @Test func findCategoryAndTask() throws {
        let ws = try workspace(tasks: ["1"])
        #expect(ws.category(Fixed.id(10))?.name == "A")
        #expect(ws.category(Fixed.id(99)) == nil)
        #expect(ws.task(Fixed.id(20))?.category.id == Fixed.id(10))
    }

    @Test func listSectionsHideCompleted() throws {
        var ws = try workspace(tasks: ["1", "2"])
        ws.setCompleted(Fixed.id(20), true, now: Fixed.time(2))
        #expect(ws.listSections(hideCompleted: true).map(\.id) == [Fixed.id(10)])
        #expect(ws.listSections(hideCompleted: true)[0].tasks.map(\.content) == ["2"])
        #expect(ws.listSections(hideCompleted: false)[0].tasks.count == 2)
    }

    @Test func nowIsRoundedToMilliseconds() throws {
        var ws = emptyWorkspace()
        try ws.rename("家", now: Date(timeIntervalSince1970: 1.2345678))
        #expect(ws.updatedAt == Date(millisecondsSince1970: 1235))
    }

    @Test func withNewIDsReplacesEveryID() throws {
        let ws = try workspace(tasks: ["1", "2"])
        var n = 100
        let copy = ws.withNewIDs { n += 1; return Fixed.id(n) }
        #expect(copy.id == Fixed.id(101))
        #expect(copy.categories[0].id == Fixed.id(102))
        #expect(copy.categories[0].tasks.map(\.id) == [Fixed.id(103), Fixed.id(104)])
        #expect(copy.categories[0].tasks.map(\.content) == ["1", "2"])
    }
}

@Suite struct PreviewTests {
    private func preview(_ content: String) -> (String, Bool) {
        let p = TodoItem(id: Fixed.id(1), content: content, createdAt: Fixed.time(0)).preview
        return (p.text, p.isTruncated)
    }

    @Test func shortContentIsShownAsIs() {
        #expect(preview("1\n2\n3") == ("1\n2\n3", false))
    }

    @Test func cutsAfterThreeLinesAndSkipsLeadingBlankLines() {
        #expect(preview("\n \n1\n2\r\n3\n4") == ("1\n2\n3", true))
    }

    @Test func cutsLongLine() {
        let (text, truncated) = preview(String(repeating: "あ", count: 1000))
        #expect(text.count == TodoItem.previewLineLength)
        #expect(truncated)
    }
}

@Suite struct TextRuleTests {
    @Test func rules() {
        #expect(TextRule.taskContent.violation(in: "a\nb") == nil)
        #expect(TextRule.taskContent.violation(in: "\n\t ") == .empty)
        #expect(TextRule.workspaceName.violation(in: "a\nb") == .containsNewline)
        #expect(TextRule.workspaceName.violation(in: String(repeating: "x", count: 101)) == .tooLong(max: 100))
        // 書記素クラスタで数える（絵文字の結合も 1 文字）
        #expect(TextRule.workspaceName.violation(in: String(repeating: "👨‍👩‍👧", count: 100)) == nil)
    }
}

@Suite struct LocalDateTests {
    @Test(arguments: ["2026-10-30", "2024-02-29", "0001-01-01"])
    func validDates(_ s: String) {
        #expect(LocalDate(string: s)?.string == s)
    }

    @Test(arguments: ["2026-02-29", "2026-13-01", "2026-1-01", "2026/10/30", "２０２６-10-30", "2026-10-30T00:00"])
    func invalidDates(_ s: String) {
        #expect(LocalDate(string: s) == nil)
    }

    // Date ⇔ LocalDate。暦はグレゴリオ暦に固定し、利用者の暦（和暦など）に左右されない（OPEN_ITEMS の不具合 A2）

    /// 2026-10-29T15:30:00Z は、東京では 30 日、ロサンゼルスでは 29 日
    @Test(arguments: [("Asia/Tokyo", "2026-10-30"), ("America/Los_Angeles", "2026-10-29"), ("UTC", "2026-10-29")])
    func fromDate(_ zone: String, _ expected: String) throws {
        let instant = Date(timeIntervalSince1970: 1_793_287_800)  // 2026-10-29T15:30:00Z
        let tz = try #require(TimeZone(identifier: zone))
        #expect(LocalDate(instant, in: tz)?.string == expected)
    }

    @Test func ordersByYearMonthDay() throws {
        let dates = try ["2026-10-30", "2025-12-31", "2026-02-01"].map { try #require(LocalDate(string: $0)) }
        #expect(dates.sorted().map(\.string) == ["2025-12-31", "2026-02-01", "2026-10-30"])
    }

    @Test func toDateIsStartOfDayInTheZone() throws {
        let tz = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let date = try #require(LocalDate(string: "2026-10-30")).date(in: tz)
        #expect(date == Date(timeIntervalSince1970: 1_793_286_000))  // 2026-10-29T15:00:00Z = 東京の 30 日 0 時
    }

    @Test(arguments: ["2026-10-30", "2024-02-29", "2026-03-08", "2026-11-01"])  // 3/8・11/1 はロサンゼルスの夏時間の切り替え日
    func roundTrip(_ s: String) throws {
        let day = try #require(LocalDate(string: s))
        for zone in ["Asia/Tokyo", "America/Los_Angeles", "Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            let tz = try #require(TimeZone(identifier: zone))
            #expect(LocalDate(day.date(in: tz), in: tz) == day, "\(zone)")
        }
    }
}

/// 書式付きのテキストを貼り付けたときに混ざる文字（data_model_spec §3.3）
@Suite struct PlainTextTests {
    @Test(arguments: [
        ("1\r\n2", "1\n2"),                 // Windows・Excel・Word: 2 重にしない
        ("1\r\n\r\n2", "1\n\n2"),           // 元から空行が 1 つなら、空行 1 つ
        ("1\r2", "1\n2"),                   // CR だけ
        ("1\r\r\n2", "1\n\n2"),             // CR のあとに CR LF: 改行 2 つ
        ("1\u{2028}2\u{2029}3", "1\n2\n3"), // メモ・Pages・Web の <br>
        ("1\u{0B}2\u{0C}3\u{85}4", "1\n2\n3\n4"), // Word の手動の改行・改ページ、NEL
        ("画像\u{FFFC}の後", "画像の後"),     // 添付の位置
        ("\u{FEFF}先頭", "先頭"),             // BOM
        ("a\u{00}b\u{07}c\u{7F}d\u{9B}e", "abcde"), // 制御文字
    ])
    func normalizes(_ input: String, _ expected: String) {
        #expect(PlainText.normalized(input) == expected)
    }

    /// 意図して入れた文字は変えない
    @Test(arguments: [
        "1\n\n\n2",          // 空行
        "a\tb",              // タブ
        "a\u{00A0}b",        // ノーブレークスペース
        "👨‍👩‍👧 家族",          // ゼロ幅接合子
        "が", "が",           // 合成済みと結合文字（どちらもそのまま）
        "",
    ])
    func keeps(_ input: String) {
        #expect(PlainText.normalized(input).unicodeScalars.elementsEqual(input.unicodeScalars))
    }

    @Test func operationsStoreNormalizedText() throws {
        var ws = Workspace(id: Fixed.id(1), name: "仕事", createdAt: Fixed.time(0), updatedAt: Fixed.time(0))
        try ws.addCategory(id: Fixed.id(10), name: "\u{FEFF}企画", now: Fixed.time(1))
        try ws.addTask(id: Fixed.id(20), content: "1\r\n2\u{2028}3", to: Fixed.id(10), now: Fixed.time(1))
        #expect(ws.categories[0].name == "企画")
        #expect(ws.categories[0].tasks[0].content == "1\n2\n3")
        // 名前は、そろえた後に改行が残れば誤り
        #expect(throws: EditError(rule: .categoryName, violation: .containsNewline)) {
            try ws.renameCategory(Fixed.id(10), to: "a\r\nb", now: Fixed.time(2))
        }
        // そろえると空になるものは誤り
        #expect(throws: EditError(rule: .taskContent, violation: .empty)) {
            try ws.setContent(Fixed.id(20), "\u{FFFC}\r\n", now: Fixed.time(2))
        }
    }
}
