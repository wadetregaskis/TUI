//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuConfigurationTests.swift
//
//  `Menu(configuration)`: inside a custom menu style's body it draws the menu
//  as the style outside the custom one would, rather than recursing into it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUIMenus
@testable import TUITestSupport

/// Draws the menu as it would otherwise look, in square brackets.
private struct BracketedMenuStyle: MenuStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            Text("[")
            Menu(configuration)
            Text("]")
        }
    }
}

@MainActor
@Suite("Menu(configuration)")
struct MenuConfigurationTests {
    private func line<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 30, height: 3)).lines.first?.stripped ?? ""
    }

    @Test("A custom style decorates the menu the style outside it draws")
    func decoratesTheOuterStyle() {
        let menu = Menu("File") { Button("Open") {} }
        let plain = line(menu)
        let bracketed = line(menu.menuStyle(BracketedMenuStyle()))
        #expect(bracketed == "[" + plain + "]", "\(bracketed) around \(plain)")
    }

    @Test("Inside an inline style, the configuration draws inline")
    func decoratesInline() {
        let menu = Menu("File") { Button("Open") {} }
        let inline = renderToBuffer(menu.menuStyle(.inline), context: makeRenderContext(width: 30, height: 4))
        let wrapped = renderToBuffer(
            menu.menuStyle(BracketedMenuStyle()).menuStyle(.inline), context: makeRenderContext(width: 30, height: 4))
        // The inline style's box, inside the brackets, with no drop-down caret.
        #expect(inline.lines.first?.stripped.contains("╭") == true)
        #expect(wrapped.lines.map(\.stripped).joined().contains("[│"), "\(wrapped.lines.map(\.stripped))")
        #expect(!wrapped.lines.map(\.stripped).joined().contains(DropdownMenu.closedCaret))
    }
}

@MainActor
@Suite("ButtonMenuStyle")
struct ButtonMenuStyleTests {
    @Test("The button style draws the menu as the default does, honouring the button style")
    func drawsAsTheDefault() {
        func line<V: View>(_ view: V) -> String {
            renderToBuffer(view, context: makeRenderContext(width: 30, height: 2)).lines.first ?? ""
        }
        let menu = Menu("File") { Button("Open") {} }
        #expect(line(menu.menuStyle(.button)) == line(menu))
        #expect(line(menu.menuStyle(.button).buttonStyle(.borderless))
            == line(menu.buttonStyle(.borderless)))
    }
}
