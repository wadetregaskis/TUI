//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabInteractionsMemoTests.swift
//
//  A sidebar row whose tab carries a context menu is served from the row
//  memo like any other row, and its menu still opens from the keyboard. The
//  tab's host declared a render side effect on every frame — for the filing
//  of its menu's opener and the section a closed menu may leave to tear
//  down — so no row holding one was ever stored, as `.contextMenu`'s rows
//  were not until 740df15af.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@Observable
@MainActor
private final class Tabs {
    var selected = 0
    var withMenus = true
    var ran: [String] = []
}

private struct TabsApp: App {
    let tabs: Tabs?

    init() { tabs = nil }

    init(_ tabs: Tabs) { self.tabs = tabs }

    var body: some Scene {
        WindowGroup {
            if let tabs { TabsPage(tabs: tabs) }
        }
    }
}

private struct TabsPage: View {
    let tabs: Tabs

    var body: some View {
        let tabs = self.tabs
        return TabView(selection: Binding(get: { tabs.selected }, set: { tabs.selected = $0 })) {
            ForEach(0..<6, id: \.self) { index in
                if tabs.withMenus {
                    Tab("Tab \(index)", value: index) { Text(verbatim: "content \(index)") }
                        .contextMenu { Button("Rename \(index)") { tabs.ran.append("rename \(index)") } }
                } else {
                    Tab("Tab \(index)", value: index) { Text(verbatim: "content \(index)") }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

@MainActor
private final class Harness {
    let tabs = Tabs()
    let app: HeadlessApp<TabsApp>
    private var now: Int64 = 0

    init(withMenus: Bool) {
        tabs.withMenus = withMenus
        app = HeadlessApp(TabsApp(tabs), width: 50, height: 14)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    func shows(_ text: String) -> Bool { app.screen.contains { $0.stripped.contains(text) } }

    /// The rows served from the row memo on one quiet frame.
    func servedOnAQuietFrame() -> Int {
        let before = app.renderCache.rowWork.served
        frame()
        return app.renderCache.rowWork.served - before
    }
}

@MainActor
@Suite("Sidebar rows whose tabs carry a context menu, served from the row memo")
struct TabInteractionsMemoTests {
    @Test("A row whose tab has a context menu is served as a plain row is")
    func rowsAreServed() {
        let plain = Harness(withMenus: false).servedOnAQuietFrame()
        let withMenus = Harness(withMenus: true).servedOnAQuietFrame()
        #expect(plain >= 5, "precondition: plain rows are served (\(plain))")
        #expect(withMenus >= plain, "served \(withMenus) rows with menus against \(plain) plain")
    }

    @Test("Shift+F10 opens the selected tab's menu from a served row, and choosing runs it")
    func keyboardOnServedRows() {
        let harness = Harness(withMenus: true)
        harness.tabs.selected = 3
        harness.frame()
        harness.frame()
        harness.frame()
        harness.app.send(KeyEvent(key: .f10, shift: true))
        harness.frame()
        #expect(harness.shows("Rename 3"), "Shift+F10 did not open the selected tab's menu")
        harness.app.send(KeyEvent(key: .enter))
        harness.frame()
        #expect(harness.tabs.ran == ["rename 3"], "ran \(harness.tabs.ran)")
        harness.frame()
        #expect(!harness.shows("Rename 3"), "the menu is still up")
    }
}
