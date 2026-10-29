// TextRule.swift — 文字列の決まり（TodoCore）
//
// 名前と中身の「長さ・改行・空白だけは不可」の決まりを、ここ 1 か所に置く。
// 使う側は 2 つ: 操作（Operations.swift）と、読み込みの検証（Persistence の WorkspaceCodec.swift）。
// 両方が同じ決まりを使うので、「アプリが書いたのに読めないファイル」が生まれない。
//
// レビューの観点:
// - 上限の値と根拠が data_model_spec §7 と合っているか
// - accept は「正規化（PlainText）→ 決まり」の順。逆にすると、見えない文字だけの中身が通る

/// 文字列の決まり（data_model_spec §3・§7）。読み込みの検証と操作の両方がこれを使う
///
/// 読み方: enum の選択肢ごとに値を返すプロパティ（maxLength など）を持たせ、`switch self` で選択肢ごとに分けている
public enum TextRule: Sendable, Equatable {
    case workspaceName
    case categoryName
    case taskContent
    /// 版 1 のタイトル。読み込みでの移行（data_model_spec §10.1）にだけ使う
    case legacyTaskTitle

    /// 上限の文字数（`String.count`。見た目の 1 文字を 1 と数える）
    public var maxLength: Int {
        switch self {
        case .workspaceName, .categoryName: 100
        // 保存はファイル全体の書き直しなので、1 件の大きさが保存の重さになる。日本語で約 300 KB
        case .taskContent: 100_000
        case .legacyTaskTitle: 500
        }
    }

    public var allowsNewlines: Bool {
        switch self {
        case .workspaceName, .categoryName: false
        // 版 1 のアプリは改行を止めずに書いていたので、読むときは許す
        case .taskContent, .legacyTaskTitle: true
        }
    }

    /// 決まりに合わなかった理由。`Error` の約束を守る型は throw で投げられる
    public enum Violation: Error, Sendable, Equatable {
        case empty
        case tooLong(max: Int)
        case containsNewline
    }

    /// 決まりに合わなければ理由を返す。正規化した後の文字列にかける（正規化もするなら `accept`）
    public func violation(in s: String) -> Violation? {
        if s.allSatisfy({ $0.isWhitespace || $0.isNewline }) { return .empty }
        if s.count > maxLength { return .tooLong(max: maxLength) }
        if !allowsNewlines, s.contains(where: \.isNewline) { return .containsNewline }
        return nil
    }
}

/// 操作の誤り。決まりに合わない操作はデータを変えずにこれを投げる
public struct EditError: Error, Sendable, Equatable {
    public var rule: TextRule
    public var violation: TextRule.Violation
}

extension TextRule {
    /// 正規化（PlainText）してから決まりをかける。合えば正規化した文字列を返す
    public func accept(_ s: String) throws(Violation) -> String {
        let normalized = PlainText.normalized(s)
        if let v = violation(in: normalized) { throw v }
        return normalized
    }

    /// Wiring: accept を呼び、誤りを「どの決まりで」の情報付き（EditError）に包み直すだけ。操作から使う
    func acceptForEdit(_ s: String) throws(EditError) -> String {
        do {
            return try accept(s)
        } catch {
            throw EditError(rule: self, violation: error)
        }
    }
}
