// Copy.swift — ワークスペースの複製（TodoCore）
//
// インポートで「複製として追加」を選んだときに使う（Features の AppModel.resolvePendingImport）。
// ID を振り直さないと、元のワークスペースと ID がぶつかる。

import Foundation

extension Workspace {
    /// ワークスペース・カテゴリ・タスクの ID をすべて振り直した複製。日時と名前はそのまま（data_model_spec §9）
    public func withNewIDs(_ newID: () -> UUID) -> Workspace {
        var copy = self
        copy.id = newID()
        for ci in copy.categories.indices {
            copy.categories[ci].id = newID()
            for ti in copy.categories[ci].tasks.indices {
                copy.categories[ci].tasks[ti].id = newID()
            }
        }
        return copy
    }
}
