//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuPrimaryActionTests.swift
//
//  `Menu(…primaryAction:)`: the label performs the primary action, and the
//  menu opens from the caret beside it, or by the Down arrow — one focus stop.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
import TUIkitMenus
@testable import TUIkitTestSupport

/// What the menus under test did.
private final class ExportLog: @unchecked Sendable {
    var entries: [String] = []
}

@MainActor
@Suite("Menu primaryAction")
struct MenuPrimaryActionTests {
    private func menu(_ log: ExportLog) -> some View {
        Menu("Export") {
            Button("PDF") { log.entries.append("pdf") }
        } primaryAction: {
            log.entries.append("again")
        }
    }

    /// Whether a frame has the menu's popup in it.
    private func isOpen(_ buffer: FrameBuffer) -> Bool {
        buffer.overlays.contains { $0.content.lines.contains { $0.stripped.contains("PDF") } }
    }

    @Test("Return performs the primary action and leaves the menu closed")
    func returnPerforms() {
        let log = ExportLog()
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .enter)]) { menu(log) }
        #expect(log.entries == ["again"])
        #expect(!isOpen(harness.frame(menu(log))))
    }

    @Test("The Down arrow opens the menu")
    func downOpens() {
        let log = ExportLog()
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .down)]) { menu(log) }
        #expect(isOpen(harness.frame(menu(log))))
        #expect(log.entries.isEmpty)
    }

    @Test("A click on the label performs the action; a click on the caret opens the menu")
    func clicks() {
        let log = ExportLog()
        let harness = InputChainHarness()
        let drawn = harness.frame(menu(log))
        let line = drawn.lines.first?.stripped ?? ""
        let caretColumn = line.firstIndex(of: Character(DropdownMenu.closedCaret)).map { line.distance(from: line.startIndex, to: $0) }
        let labelColumn = line.range(of: "Export").map { line.distance(from: line.startIndex, to: $0.lowerBound) }
        #expect(caretColumn != nil && labelColumn != nil, "\(line)")
        guard let caretColumn, let labelColumn else { return }

        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: labelColumn, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: labelColumn, y: 0))
        #expect(log.entries == ["again"])
        #expect(!isOpen(harness.frame(menu(log))))

        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: caretColumn, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: caretColumn, y: 0))
        #expect(isOpen(harness.frame(menu(log))), "\(line)")
        #expect(log.entries == ["again"])
    }

    @Test("The split menu is one focus stop")
    func oneFocusStop() {
        let log = ExportLog()
        let harness = InputChainHarness()
        // Tab from the menu goes to the button after it, not to the caret.
        harness.play([KeyEvent(key: .tab), KeyEvent(key: .enter)]) {
            VStack {
                menu(log)
                Button("Next") { log.entries.append("next") }
            }
        }
        #expect(log.entries == ["next"])
    }
}
