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

/// The sidebar's parts as `_TabSidebarList` composes them — its Shift+F10
/// over a list whose rows are the tabs' hosts — but over rows whose values are
/// the same from frame to frame: each tab's menu is built once, where a tab
/// view builds its tabs' menus afresh with every evaluation of the body that
/// makes it, so its rows are never equal to the last frame's.
private struct StableSidebarPage: View {
    let tabs: Tabs
    let traits: [_TabInteractionTraits]

    var body: some View {
        let tabs = self.tabs
        let traits = self.traits
        let selection = Binding<AnyHashable>(
            get: { AnyHashable(tabs.selected) },
            set: { value in if let index = value.base as? Int { tabs.selected = index } })
        let rowSelection = Binding<Int?>(
            get: { tabs.selected }, set: { index in if let index { tabs.selected = index } })
        return _TabSidebarMenuKeys(
            content: List(selection: rowSelection) {
                ForEach(0..<traits.count, id: \.self) { index in
                    _TabInteractionsHost(
                        content: Text(verbatim: "Tab \(index)"), traits: traits[index], value: AnyHashable(index),
                        title: "Tab \(index)")
                }
            },
            selection: selection, hasMenus: true)
    }
}

private struct StableSidebarApp: App {
    let page: StableSidebarPage?

    init() { page = nil }

    init(_ page: StableSidebarPage) { self.page = page }

    var body: some Scene {
        WindowGroup {
            if let page { page }
        }
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

    /// The selected tab's row served from the memo files its menu's opener
    /// only through the entry the memo replays (`tabMenu.opener`): the
    /// sidebar starts its openers afresh on every render. A tab view's own
    /// sidebar rows are not served across frames today (decisions D2C, found
    /// on the way), so in the test above the selected row files its opener as
    /// it is drawn; this composes the sidebar's parts over rows that are the
    /// same every frame, which are.
    @Test("Shift+F10 opens the selected tab's menu from its row served from the memo")
    func keyboardOnAServedRow() {
        let tabs = Tabs()
        tabs.selected = 3
        let traits = (0..<6).map { index in
            var traits = _TabInteractionTraits()
            traits.contextMenu = AnyView(Button("Rename \(index)") { tabs.ran.append("rename \(index)") })
            return traits
        }
        let app = HeadlessApp(StableSidebarApp(StableSidebarPage(tabs: tabs, traits: traits)), width: 50, height: 14)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        func shows(_ text: String) -> Bool { app.screen.contains { $0.stripped.contains(text) } }
        for _ in 0..<4 { frame() }
        // Up and Down move the list's cursor and nothing else: it leaves the
        // selected row, as when the selection is set from outside.
        app.send(KeyEvent(key: .down))
        frame()
        app.send(KeyEvent(key: .down))
        frame()
        frame()
        #expect(tabs.selected == 3, "precondition: the arrows moved the selection")
        // Served while drawing, not while measuring: only a drawing serve
        // replays the row's registrations, which is what this test is about.
        let before = app.renderCache.rowWork.servedDrawing
        frame()
        let served = app.renderCache.rowWork.servedDrawing - before
        #expect(served >= 6, "precondition: every row is served as the quiet frame draws it (\(served))")
        app.send(KeyEvent(key: .f10, shift: true))
        frame()
        #expect(shows("Rename 3"), "Shift+F10 did not open the selected tab's menu: \(app.screen.map(\.stripped))")
        app.send(KeyEvent(key: .enter))
        frame()
        #expect(tabs.ran == ["rename 3"], "ran \(tabs.ran)")
    }
}
