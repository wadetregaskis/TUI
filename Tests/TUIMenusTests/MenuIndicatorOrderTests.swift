//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuIndicatorOrderTests.swift
//
//  `.menuIndicator(_:)` hides a menu's caret; `.menuOrder(_:)` states an order
//  TUI's menus already keep.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUIMenus
@testable import TUITestSupport

@MainActor
@Suite("Menu indicator and order")
struct MenuIndicatorOrderTests {

    private func line<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 30, height: 2))
            .lines.first?.stripped.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression) ?? ""
    }

    private var menu: some View {
        Menu("Actions") {
            Button("Rename") {}
        }
    }

    @Test("The caret shows by default and when visible, and goes when hidden")
    func indicator() {
        let shown = line(menu)
        #expect(shown.contains(DropdownMenu.closedCaret))
        #expect(line(menu.menuIndicator(.visible)) == shown)
        let hidden = line(menu.menuIndicator(.hidden))
        #expect(hidden.contains("Actions") && !hidden.contains(DropdownMenu.closedCaret))
    }

    @Test("Menu order is recorded, and changes nothing drawn")
    func order() {
        #expect(EnvironmentValues().menuOrder == .automatic)
        #expect(line(menu.menuOrder(.fixed)) == line(menu))
    }
}
