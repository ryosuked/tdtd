// Messages.swift — 利用者に見せる誤りの文言（Features）
//
// 誤りの種類（Persistence の WorkspaceFileError、TodoCore の TextRule.Violation・EditError）を、
// 日本語の文言に変える対応表。文言はここ 1 か所に置く。使う側は AppModel（誤りの表示）と TaskInspector。

import Persistence
import TodoCore

extension WorkspaceFileError {
    /// 利用者に見せる文言
    var message: String {
        let reason = switch kind {
        case .notJSON: "JSON として読めません。"
        case .wrongFormat: "このアプリのワークスペースのファイルではありません。"
        case .unsupportedVersion(let v): "新しい版（\(v)）のファイルです。アプリを更新してください。"
        case .missingOrWrongType: "必要な項目が無いか、型が違います。"
        case .invalidValue: "値の書式が正しくありません。"
        case .invalidText(let v): v.message
        case .duplicateID: "ID が重複しています。"
        case .tooLarge: "ファイルが大きすぎます（上限 \(WorkspaceFormat.maxImportBytes / 1024 / 1024) MB）。"
        }
        return path.isEmpty ? reason : "\(reason)（場所: \(path)）"
    }
}

extension TextRule.Violation {
    var message: String {
        switch self {
        case .empty: "空にはできません。"
        case .tooLong(let max): "\(max.formatted()) 文字までです。"
        case .containsNewline: "改行は入れられません。"
        }
    }
}

extension EditError {
    /// 利用者に見せる文言
    var message: String {
        let target = switch rule {
        case .workspaceName: "ワークスペースの名前"
        case .categoryName: "カテゴリの名前"
        case .taskContent, .legacyTaskTitle: "タスクの中身"
        }
        return "\(target)は\(violation.message)"
    }
}
