// WorkspaceStore.swift — ワークスペース 1 つ分の状態と保存（Features）
//
// 画面からの操作の入口。各メソッドは TodoCore の操作（Operations.swift）を呼んで workspace を差し替えるだけ。
// 変わったら 1 秒待ってから WorkspaceRepository に保存する（待つ間に次の変更があれば待ち直す）。
//
// 操作の流れ:  画面 → WorkspaceStore.xxx → apply → Workspace.xxx（TodoCore）→ scheduleSave → save → WorkspaceRepository.save
//
// レビューの観点:
// - 誤りの操作でデータが変わらないか（apply は複製に当ててから差し替える）
// - 保存の待ち合わせ（scheduleSave・flush）で、変更を取りこぼさないか

import Foundation
import Observation
import Persistence
import TodoCore

/// 開いているワークスペース 1 つの状態。更新は TodoCore の操作を呼ぶだけ（配線だけ）
///
/// @Observable・@MainActor の意味は AppModel.swift の冒頭を参照
@Observable @MainActor
public final class WorkspaceStore: Identifiable {
    // Ceremony: Identifiable の約束で id が要る（画面の一覧で使う）。
    // nonisolated は「画面のスレッド以外からも読める」印。作ったあと変わらない値（let）なので安全
    public nonisolated let id: UUID
    public private(set) var workspace: Workspace

    @ObservationIgnored private let repository: WorkspaceRepository
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let newID: () -> UUID
    @ObservationIgnored private let onError: (String) -> Void
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// 保存の待ち時間。入力のたびにファイルを書かないため（data_model_spec §8）
    static let saveDelay: Duration = .seconds(1)

    // Ceremony: 受け取った値をそのまま入れるだけ。作るのは AppModel.makeStore
    init(
        workspace: Workspace, repository: WorkspaceRepository,
        now: @escaping () -> Date, newID: @escaping () -> UUID, onError: @escaping (String) -> Void
    ) {
        self.id = workspace.id
        self.workspace = workspace
        self.repository = repository
        self.now = now
        self.newID = newID
        self.onError = onError
    }

    // MARK: 操作
    // Wiring: ここから下の各メソッドは、TodoCore の同じ名前の操作を apply に渡すだけ。決まりと処理は TodoCore にある。
    // 文字列を受け取る操作は、決まりに合わなければ誤りを 1 か所に出し、false を返す。
    // @discardableResult は「戻り値を使わずに呼んでも警告を出さない」印

    @discardableResult
    public func rename(_ name: String) -> Bool { apply { try $0.rename(name, now: $1) } }

    @discardableResult
    public func addCategory(name: String) -> Bool {
        let id = newID()
        return apply { try $0.addCategory(id: id, name: name, now: $1) }
    }

    @discardableResult
    public func renameCategory(_ categoryID: UUID, to name: String) -> Bool {
        apply { try $0.renameCategory(categoryID, to: name, now: $1) }
    }

    public func setCategoryColor(_ categoryID: UUID, to color: CategoryColor) {
        apply { $0.setCategoryColor(categoryID, to: color, now: $1) }
    }

    public func deleteCategory(_ categoryID: UUID) {
        apply { $0.deleteCategory(categoryID, now: $1) }
    }

    @discardableResult
    public func addTask(content: String, to categoryID: UUID) -> Bool {
        let id = newID()
        return apply { try $0.addTask(id: id, content: content, to: categoryID, now: $1) }
    }

    @discardableResult
    public func setContent(_ taskID: UUID, _ content: String) -> Bool {
        apply { try $0.setContent(taskID, content, now: $1) }
    }

    public func setDue(_ taskID: UUID, _ due: LocalDate?) {
        apply { $0.setDue(taskID, due, now: $1) }
    }

    public func setCompleted(_ taskID: UUID, _ completed: Bool) {
        apply { $0.setCompleted(taskID, completed, now: $1) }
    }

    public func moveTask(_ taskID: UUID, to categoryID: UUID, at index: Int) {
        apply { $0.moveTask(taskID, to: categoryID, at: index, now: $1) }
    }

    public func deleteTask(_ taskID: UUID) {
        apply { $0.deleteTask(taskID, now: $1) }
    }

    /// インポートで置き換える
    func replace(with workspace: Workspace) {
        self.workspace = workspace
        scheduleSave()
    }

    // MARK: 保存

    /// 操作を当てる。誤りなら何も変えずに知らせる
    ///
    /// 複製（next）に当ててから差し替えるので、途中で誤りになっても workspace は元のまま。
    /// 戻り値は「誤りでなかったか」。入力欄はこれを見て、誤りのときは入力を消さずに残す
    @discardableResult
    private func apply(_ change: (inout Workspace, Date) throws -> Void) -> Bool {
        var next = workspace
        do {
            try change(&next, now())
        } catch let error as EditError {
            onError(error.message)
            return false
        } catch {
            onError(error.localizedDescription)
            return false
        }
        guard next != workspace else { return true }
        workspace = next
        scheduleSave()
        return true
    }

    /// 1 秒後に保存する。待つ間に次の変更が来たら、前の待ちを取り消して待ち直す（間引き）。
    /// 保存するのは「その時点の最新の workspace」なので、取り消した分の変更も失われない
    private func scheduleSave() {
        saveTask?.cancel()
        // Task.sleep で 1 秒待つ。待つ間に cancel されると、isCancelled が true になって保存しない
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// 待たずにすぐ書く（背面に回る・終了するとき）
    public func flush() async {
        guard let task = saveTask else { return }
        task.cancel()
        saveTask = nil
        await save()
    }

    private func save() async {
        let snapshot = workspace
        do {
            try await repository.save(snapshot)
        } catch {
            // メモリの中のデータは残す。次の変更のときに書き直す
            onError("「\(snapshot.name)」を保存できませんでした。\(error.localizedDescription)")
        }
    }
}
