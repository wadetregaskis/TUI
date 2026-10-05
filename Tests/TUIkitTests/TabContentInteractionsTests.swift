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
