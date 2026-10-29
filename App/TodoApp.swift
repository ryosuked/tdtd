// TodoApp.swift — アプリの入口（App）
//
// ウィンドウを 1 つ作り、Features の RootView を出すだけ。状態と画面はすべて Packages/Features にある。
// #if os() を書いてよいのは、この層と Features のファイル分割だけ（CLAUDE.md §6.1）。

import Features
import SwiftUI

/// 入口だけ。状態と画面は Features に置く
///
/// @main は「アプリはここから始まる」の印。`body` に、出すウィンドウ（WindowGroup）を書く
@main
struct TodoApp: App {
    // #if os(macOS) 〜 #else 〜 #endif: Mac でビルドするときと、それ以外（iPad）とで入るコードを分ける
    #if os(macOS)
    // Ceremony: SwiftUI のアプリに、Mac の古い仕組み（AppKit の AppDelegate）をつなぐ。終了の知らせを受けるため
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: AppModel { delegate.model }
    #else
    @State private var model = AppModel.live()
    #endif

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 720, minHeight: 480)
        }
    }
}

#if os(macOS)
import AppKit

/// 終了の前に、保存を待っている変更を書き切る（data_model_spec §8）
///
/// Ceremony: NSObject・NSApplicationDelegate は AppKit がこの形を求めるので付けている。
/// 下の 2 つの関数も、名前が決まっていて AppKit が呼ぶ（自分では呼ばない）
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.live()

    /// 終了をいったん保留し（.terminateLater）、保存を書き切ってから終了を許す。
    /// 保留しないと、1 秒の待ちの間に終了したとき、最後の変更が書かれない
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.flushAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// 最後のウィンドウを閉じたら、アプリも終了する
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif
