//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuKeyTests.swift
//
//  The PC keyboard's Menu key (`Key.menu`, reported only under the kitty
//  keyboard protocol) is Shift+F10's twin: it opens a focused view's
//  `.contextMenu` and closes it again. The row menus and the tab menus it
//  opens are pinned beside their Shift+F10 tests.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

private struct MenuKeyApp: App {
    var body: some Scene {
        WindowGroup {
            Text(verbatim: "Target").contextMenu {
                Button("Cut") {}
            }
        }
    }
}

@MainActor
@Suite("The Menu key")
struct MenuKeyTests {
    @Test("The Menu key opens a focused view's context menu, and closes it, as Shift+F10 does")
    func menuKeyTogglesAContextMenu() {
        let app = HeadlessApp(MenuKeyApp(), width: 30, height: 10)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        func shows(_ text: String) -> Bool { app.screen.contains { $0.stripped.contains(text) } }
        frame()
        frame()
        app.send(KeyEvent(key: .menu))
        frame()
        #expect(shows("Cut"), "\(app.screen.map(\.stripped).joined(separator: "\n"))")
        app.send(KeyEvent(key: .menu))
        frame()
        #expect(!shows("Cut"), "\(app.screen.map(\.stripped).joined(separator: "\n"))")
    }
}
