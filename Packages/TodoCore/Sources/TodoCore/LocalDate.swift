// LocalDate.swift — 日付だけの値（TodoCore）
//
// タスクの期限（due）に使う。Date（時刻つき）にすると、タイムゾーンによって日付がずれるため。
// 文字列との変換は "YYYY-MM-DD" だけを受け付ける。
// 画面の DatePicker との変換（Date ⇔ LocalDate）もここに置く（ファイル末尾）。
//
// レビューの観点:
// - うるう年と月末の判定（daysInMonth）
// - Date との変換で、利用者の暦（和暦など）に左右されないか（グレゴリオ暦に固定している）

import Foundation

/// 日付だけの値（`YYYY-MM-DD`）。タイムゾーンで日付がずれないように `Date` を使わない
public struct LocalDate: Comparable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    /// 実在する日付（グレゴリオ暦）でなければ nil
    ///
    /// `init?` は「作れないことがある」初期化。作れなければ値の代わりに nil が返る
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...LocalDate.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// `YYYY-MM-DD` だけを受け付ける
    public init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// `YYYY-MM-DD`。`%04d` は「4 桁に満たなければ前を 0 で埋める」の意味
    public var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    // Ceremony: Comparable の約束。< を 1 つ書けば、>・<=・並べ替えなどが使えるようになる
    public static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

// 画面の日付の部品（DatePicker）は Date（時刻つき）を使うので、LocalDate（日付だけ）と変換する。
// 暦はグレゴリオ暦に固定する。Calendar.current を使うと、利用者が和暦を選んでいるとき
// 年が「令和 8 年 → 8 年」のように取れて、日付が 2000 年ほどずれるため。タイムゾーンだけは利用者のものを渡す
extension LocalDate {
    /// その瞬間が、指定したタイムゾーンで何日か
    public init?(_ date: Date, in timeZone: TimeZone) {
        let c = Self.calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// 指定したタイムゾーンでの、その日の始まり
    public func date(in timeZone: TimeZone) -> Date {
        // 実在する日付しか作れない（init?）ので、変換は失敗しない
        Self.calendar(timeZone).date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
