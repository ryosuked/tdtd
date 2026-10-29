// PlainText.swift — 書式なしの文字列の正規化（TodoCore）
//
// 書式付きのテキストを貼り付けたときに混ざる改行のつもりの文字（CR LF、U+2028 など）を LF にそろえ、
// 見えない文字（U+FFFC、BOM、制御文字）を取り除く。表は data_model_spec §3.3。
// TextRule.accept の中で呼ばれるので、操作と読み込みの両方を通る。
//
// レビューの観点:
// - Swift の Character では "\r\n" が 1 文字になるので、Unicode スカラー単位で見ている
// - タブ・空行・ゼロ幅接合子（絵文字）など、意図して入れた文字を消していないか

/// 書式なしの文字列の正規化（data_model_spec §3.3）。
/// 書式付きのテキストを貼り付けたときに混ざる、改行のつもりの文字や見えない文字をそろえる。
/// 入力（操作）と読み込みの両方で通す
///
/// Ceremony: 選択肢（case）の無い enum は、作ることのできない「関数の入れ物（名前空間）」として使う。
/// 呼ぶときは `PlainText.normalized(s)` と書く
public enum PlainText {
    public static func normalized(_ s: String) -> String {
        // "\r\n" は 1 つの Character なので、Unicode スカラー単位で見る
        var out = String.UnicodeScalarView()
        out.reserveCapacity(s.unicodeScalars.count)
        var afterCR = false
        for scalar in s.unicodeScalars {
            let v = scalar.value
            // defer: このループの 1 回分を抜けるときに必ず実行する。「直前の文字が CR だったか」を覚えておく
            defer { afterCR = (v == 0x0D) }
            switch v {
            case 0x0A:
                // CR LF は LF 1 つ（2 重にしない）。CR で LF を出し済み
                if !afterCR { out.append("\n") }
            case 0x0D, 0x0B, 0x0C, 0x85, 0x2028, 0x2029:
                out.append("\n")
            case 0x09:
                out.append(scalar)
            case 0x00...0x1F, 0x7F...0x9F, 0xFFFC, 0xFEFF:
                break  // 取り除く
            default:
                out.append(scalar)
            }
        }
        return String(out)
    }
}
