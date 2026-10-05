//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabContentInteractionsTests.swift
//
//  A tab's own context menu, popovers, drag and drops — on a strip's chips,
//  in both looks, and on a `.sidebarAdaptable` sidebar's rows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// What the tab view and its tabs did, outside the views.
private final class Log: @unchecked Sendable {
    var selected = 1
    var entries: [String] = []
    var showsPopover = false
    var selection: Binding<Int> { Binding(get: { self.selected }, set: { self.selected = $0 }) }
    var popover: Binding<Bool> { Binding(get: { self.showsPopover }, set: { self.showsPopover = $0 }) }
}

/// The three ways a tab view draws its tabs.
enum TabInteractionsLook: CaseIterable, Sendable {
    case compact, bordered, sidebar
}

/// What watches the pointer over a whole tab view, around it.
enum TabHoverWatcher: CaseIterable, Sendable {
    case none, help, onHover, onHoverOnAnAncestor
}

@MainActor
@Suite("A tab's context menu, popovers, drag and drops")
struct TabContentInteractionsTests {
    /// Two tabs: the second carries a context menu, a popover, a drag and a
    /// drop; the first's content is a draggable chip and a drop target.
    private func tabs(_ log: Log, _ look: TabInteractionsLook) -> some View {
        let view = TabView(selection: log.selection) {
            Tab("One", systemImage: "star", value: 1) {
                VStack {
                    Text("CHIP").draggable("apple")
                    Text("BIN").dropDestination(for: String.self) { items, _ in
                        log.entries.append("bin \(items)")
                        return true
                    }
                }
            }
            Tab("Two", systemImage: "star", value: 2) { Text("second") }
                .contextMenu {
                    Button("Pin") { log.entries.append("pin") }
                    Button("Share") { log.entries.append("share") }
                }
                .popover(isPresented: log.popover) { Text("Hello") }
                .draggable("two")
                .dropDestination(for: String.self) { log.entries.append("tab \($0)") }
        }
        return Group {
            switch look {
            case .compact: view
            case .bordered: view.tabViewStyle(.bordered)
            case .sidebar: view.tabViewStyle(.sidebarAdaptable)
            }
        }
    }

    /// Where `text` starts on screen, in cells.
    private func cell(of text: String, in buffer: FrameBuffer) -> (x: Int, y: Int)? {
        for (y, line) in buffer.lines.map(\.stripped).enumerated() {
            if let range = line.range(of: text) {
                return (String(line[..<range.lowerBound]).strippedLength, y)
            }
        }
        return nil
    }

    /// Everything the overlays over `buffer` draw, stripped.
    private func overlayText(_ buffer: FrameBuffer) -> String {
        buffer.overlays.flatMap { $0.content.lines.map(\.stripped) }.joined(separator: "\n")
    }

    private func click(_ harness: InputChainHarness, _ at: (x: Int, y: Int), button: MouseButton = .left) {
        harness.mouse(MouseEvent(button: button, phase: .pressed, x: at.x, y: at.y))
        harness.mouse(MouseEvent(button: button, phase: .released, x: at.x, y: at.y))
    }

    @Test("A right-click on a tab opens its context menu, and a left-click still selects it", arguments: TabInteractionsLook.allCases)
    func rightClickOpensTheMenu(look: TabInteractionsLook) {
        let log = Log()
        let harness = InputChainHarness(width: 50, height: 14)
        let drawn = harness.frame(tabs(log, look))
        guard let two = cell(of: "Two", in: drawn) else {
            Issue.record("no second tab in \(drawn.lines.map(\.stripped))")
            return
        }
        #expect(!overlayText(drawn).contains("Pin"), "the menu starts closed")
        harness.mouse(MouseEvent(button: .right, phase: .pressed, x: two.x + 1, y: two.y))
        let opened = harness.frame(tabs(log, look))
        harness.mouse(MouseEvent(button: .right, phase: .released, x: two.x + 1, y: two.y))
        #expect(overlayText(opened).contains("Pin") && overlayText(opened).contains("Share"), "\(overlayText(opened))")
        #expect(log.selected == 1, "the right-click selected the tab")
        harness.press(KeyEvent(key: .escape))
        let closed = harness.frame(tabs(log, look))
        #expect(!overlayText(closed).contains("Pin"))

        click(harness, (two.x + 1, two.y))
        harness.frame(tabs(log, look))
        #expect(log.selected == 2, "a left-click on a tab with a menu no longer selects it")
    }

    /// The drag handle forwards a click released unmoved to what the tab's
    /// content has under it, and the menu's trigger is not the content's: it
    /// was, for one draft, and every click on a tab with both a menu and a
    /// drag went to the trigger, which declined it, and selected nothing.
    @Test("A click on a tab carrying every interaction selects it", arguments: TabInteractionsLook.allCases)
    func plainClickSelects(look: TabInteractionsLook) {
        let log = Log()
        let harness = InputChainHarness(width: 50, height: 14)
        let drawn = harness.frame(tabs(log, look))
        guard let two = cell(of: "Two", in: drawn) else {
            Issue.record("no second tab in \(drawn.lines.map(\.stripped))")
            return
        }
        click(harness, (two.x + 1, two.y))
        harness.frame(tabs(log, look))
        #expect(log.selected == 2)
    }

    /// `tabs(log, look)`, with `watcher` watching the pointer over all of it.
    @ViewBuilder
    private func tabs(_ log: Log, _ look: TabInteractionsLook, watchedBy watcher: TabHoverWatcher) -> some View {
        switch watcher {
        case .none: tabs(log, look)
        case .help: tabs(log, look).help("Tabs")
        case .onHover: tabs(log, look).onHover { _ in }
        case .onHoverOnAnAncestor: VStack { tabs(log, look) }.onHover { _ in }
        }
    }

    /// A chip's interactions put regions in front of its own, and hover goes
    /// to the front-most region only: none of them — the menu's trigger, the
    /// drag handle, the drop zone — answers it, so a tab with any of them
    /// never lifted under the pointer while a plain tab beside it did. (A
    /// sidebar's rows do not lift under the pointer at all.)
    ///
    /// Nor may what watches the pointer over the whole tab view take that
    /// lift away: one observer is heard per point, the outermost, so a chip
    /// that lifted through a hover observer of its own did not lift under
    /// `.help` or `.onHover` on the tab view or any view around it.
    @Test(
        "A strip's chip carrying interactions lifts under the pointer as a plain one does",
        arguments: [TabInteractionsLook.compact, .bordered], TabHoverWatcher.allCases)
    func hoverLiftsTheTab(look: TabInteractionsLook, watcher: TabHoverWatcher) {
        let log = Log()
        let harness = InputChainHarness(width: 50, height: 14)
        let drawn = harness.frame(tabs(log, look, watchedBy: watcher))
        guard let one = cell(of: "One", in: drawn), let two = cell(of: "Two", in: drawn) else {
            Issue.record("no tabs in \(drawn.lines.map(\.stripped))")
            return
        }
        /// Row `y` as drawn with the pointer resting at `point`.
        func row(_ y: Int, pointerAt point: (x: Int, y: Int)) -> String {
            harness.mouse(MouseEvent(button: .none, phase: .moved, x: point.x, y: point.y))
            return harness.frame(tabs(log, look, watchedBy: watcher)).lines[y]
        }
        // A cell no tab is on.
        let away = (x: 49, y: 13)
        // The selected tab is drawn as such, hovered or not.
        log.selected = 2
        #expect(
            row(one.y, pointerAt: (one.x + 1, one.y)) != row(one.y, pointerAt: away),
            "precondition, \(watcher): a plain tab lifts")
        log.selected = 1
        #expect(
            row(two.y, pointerAt: (two.x + 1, two.y)) != row(two.y, pointerAt: away),
            "\(watcher): the tab carrying a menu, a drag and a drop did not lift")
    }

    @Test("Shift+F10 opens the selected tab's menu, on its first item", arguments: TabInteractionsLook.allCases)
    func shiftF10OpensTheSelectedTabsMenu(look: TabInteractionsLook) {
        let log = Log()
        log.selected = 2
        let harness = InputChainHarness(width: 50, height: 14)
        harness.play([KeyEvent(key: .f10, shift: true)]) { tabs(log, look) }
        #expect(overlayText(harness.frame(tabs(log, look))).contains("Pin"), "Shift+F10 opened nothing")
        harness.play([KeyEvent(key: .enter)]) { tabs(log, look) }
        #expect(log.entries == ["pin"])
        #expect(!overlayText(harness.frame(tabs(log, look))).contains("Pin"), "choosing did not close the menu")
    }

    @Test("Shift+F10 on a tab with no menu opens nothing", arguments: [TabInteractionsLook.compact, .sidebar])
    func shiftF10WithoutAMenu(look: TabInteractionsLook) {
        let log = Log()
        let harness = InputChainHarness(width: 50, height: 14)
        harness.play([KeyEvent(key: .f10, shift: true)]) { tabs(log, look) }
        #expect(!overlayText(harness.frame(tabs(log, look))).contains("Pin"))
    }

    /// The strip and the sidebar keep each tab's menu opener by its value.
    /// One whose menu went away kept it, and Shift+F10 on that tab ran it on a
    /// box nothing draws: the key was taken and nothing opened.
    @Test("Shift+F10 on a tab whose menu went away is not taken", arguments: [TabInteractionsLook.compact, .sidebar])
    func shiftF10AfterTheMenuWentAway(look: TabInteractionsLook) {
        let log = Log()
        log.selected = 2
        var hasMenu = true
        func view() -> some View {
            let tabs = TabView(selection: log.selection) {
                Tab("One", value: 1) { Text("first") }
                if hasMenu {
                    Tab("Two", value: 2) { Text("second") }
                        .contextMenu { Button("Pin") { log.entries.append("pin") } }
                } else {
                    Tab("Two", value: 2) { Text("second") }
                }
            }
            return Group {
                if look == .sidebar { tabs.tabViewStyle(.sidebarAdaptable) } else { tabs }
            }
        }
        let harness = InputChainHarness(width: 50, height: 14)
        harness.play([]) { view() }
        hasMenu = false
        let taken = harness.play([KeyEvent(key: .f10, shift: true)]) { view() }
        #expect(taken == [false], "Shift+F10 was taken for a menu the tab no longer has")
        #expect(!overlayText(harness.frame(view())).contains("Pin"))
    }

    /// The test above, with a third tab that keeps its menu throughout. There
    /// the sidebar loses its only menu, so it has no Shift+F10 at all and
    /// cannot take the key whatever its openers hold; here it keeps the key
    /// for the third tab's menu, and only starting its openers afresh on
    /// every render (`_TabSidebarMenuKeys`) stops the selected tab's stale
    /// one opening a menu nothing draws.
    @Test(
        "Shift+F10 on a tab whose menu went away is not taken while another tab keeps its own",
        arguments: [TabInteractionsLook.compact, .sidebar])
    func shiftF10AfterTheMenuWentAwayBesideAnother(look: TabInteractionsLook) {
        let log = Log()
        log.selected = 2
        var hasMenu = true
        func view() -> some View {
            let tabs = TabView(selection: log.selection) {
                Tab("One", value: 1) { Text("first") }
                if hasMenu {
                    Tab("Two", value: 2) { Text("second") }
                        .contextMenu { Button("Pin") { log.entries.append("pin") } }
                } else {
                    Tab("Two", value: 2) { Text("second") }
                }
                Tab("Three", value: 3) { Text("third") }
                    .contextMenu { Button("Keep") { log.entries.append("keep") } }
            }
            return Group {
                if look == .sidebar { tabs.tabViewStyle(.sidebarAdaptable) } else { tabs }
            }
        }
        let harness = InputChainHarness(width: 50, height: 14)
        harness.play([]) { view() }
        hasMenu = false
        let taken = harness.play([KeyEvent(key: .f10, shift: true)]) { view() }
        #expect(taken == [false], "Shift+F10 was taken for a menu the tab no longer has")
        let shown = overlayText(harness.frame(view()))
        #expect(!shown.contains("Pin") && !shown.contains("Keep"), "\(shown)")
        // The third tab's menu still opens from the keyboard.
        log.selected = 3
        harness.play([KeyEvent(key: .f10, shift: true)]) { view() }
        #expect(overlayText(harness.frame(view())).contains("Keep"), "precondition: the key still opens a menu")
    }

    /// The sidebar's Shift+F10 is a focus-path handler over its list, and a
    /// sidebar whose tabs carry no menu has nothing for it to open: it costs
    /// such a sidebar nothing, neither the handler nor the openers it asks.
    @Test("A sidebar whose tabs carry no context menu registers no Shift+F10 handler")
    func sidebarWithoutMenusHasNoMenuKey() {
        func handlers(withMenu: Bool) -> Int {
            let log = Log()
            let harness = InputChainHarness(width: 50, height: 14)
            harness.frame(
                TabView(selection: log.selection) {
                    Tab("One", value: 1) { Text("first") }
                    if withMenu {
                        Tab("Two", value: 2) { Text("second") }.contextMenu { Button("Pin") {} }
                    } else {
                        Tab("Two", value: 2) { Text("second") }
                    }
                }
                .tabViewStyle(.sidebarAdaptable))
            return harness.tui.keyEventDispatcher.focusPathHandlerCount
        }
        #expect(handlers(withMenu: false) == handlers(withMenu: true) - 1)
    }

    @Test("A tab's popover hangs from its chip or row", arguments: TabInteractionsLook.allCases)
    func popoverHangsFromTheTab(look: TabInteractionsLook) {
        let log = Log()
        let harness = InputChainHarness(width: 50, height: 14)
        let drawn = harness.frame(tabs(log, look))
        #expect(!overlayText(drawn).contains("Hello"))
        log.showsPopover = true
        let shown = harness.frame(tabs(log, look))
        guard let two = cell(of: "Two", in: drawn),
            let layer = shown.overlays.first(where: { $0.content.lines.contains { $0.stripped.contains("Hello") } })
        else {
            Issue.record("no popover: \(overlayText(shown))")
            return
        }
        #expect(layer.offsetY > two.y, "the popover is not below the tab: \(layer.offsetY) vs \(two.y)")
        #expect(abs(layer.offsetX - two.x) <= 12, "the popover is not under the tab: \(layer.offsetX) vs \(two.x)")
        harness.press(KeyEvent(key: .escape))
        harness.frame(tabs(log, look))
        #expect(!log.showsPopover, "Escape did not close the popover")
    }

    @Test("A draggable tab carries its payload; a click released unmoved selects it", arguments: TabInteractionsLook.allCases)
    func draggingATab(look: TabInteractionsLook) {
        let log = Log()
        let harness = InputChainHarness(width: 50, height: 14)
        let drawn = harness.frame(tabs(log, look))
        guard let two = cell(of: "Two", in: drawn), let bin = cell(of: "BIN", in: drawn) else {
            Issue.record("no tab or bin in \(drawn.lines.map(\.stripped))")
            return
        }
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: two.x + 1, y: two.y))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: two.x + 2, y: two.y))
        harness.frame(tabs(log, look))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: bin.x + 1, y: bin.y))
        harness.frame(tabs(log, look))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: bin.x + 1, y: bin.y))
        harness.frame(tabs(log, look))
        #expect(log.entries == ["bin [\"two\"]"], "\(log.entries)")
        #expect(log.selected == 1, "the drag selected the tab")
    }

    @Test("A tab takes the drops its destination accepts", arguments: TabInteractionsLook.allCases)
    func droppingOnATab(look: TabInteractionsLook) {
        let log = Log()
        let harness = InputChainHarness(width: 50, height: 14)
        let drawn = harness.frame(tabs(log, look))
        guard let chip = cell(of: "CHIP", in: drawn), let two = cell(of: "Two", in: drawn) else {
            Issue.record("no chip or tab in \(drawn.lines.map(\.stripped))")
            return
        }
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: chip.x, y: chip.y))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: chip.x + 1, y: chip.y))
        harness.frame(tabs(log, look))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: two.x + 1, y: two.y))
        harness.frame(tabs(log, look))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: two.x + 1, y: two.y))
        harness.frame(tabs(log, look))
        #expect(log.entries == ["tab [\"apple\"]"], "\(log.entries)")
    }
}
