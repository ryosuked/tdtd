// LocalDate.swift — 日付だけの値（TodoCore）
//
// タスクの期限（due）に使う。Date（時刻つき）にすると、タイムゾーンによって日付がずれるため。
// 文字列との変換は "YYYY-MM-DD" だけを受け付ける。
// 画面の DatePicker との変換（Date ⇔ LocalDate）は Features の TaskInspector.swift にある。
//
// レビューの観点:
// - うるう年と月末の判定（daysInMonth）

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

    public var string: String {
        func pad(_ n: Int, _ width: Int) -> String {
            let s = String(n)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
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
