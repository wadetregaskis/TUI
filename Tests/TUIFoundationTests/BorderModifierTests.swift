//  🖥️ TUI — A Terminal UI framework for Swift
//  BorderModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

// MARK: - Test Helpers

/// Creates a default render context for testing.
private func testContext(width: Int = 40, height: Int = 24) -> RenderContext {
    makeBareRenderContext(width: width, height: height)
}

// MARK: - BorderModifier Tests

@MainActor
@Suite("BorderModifier Tests")
struct BorderModifierTests {

    @Test(".border() renders with top and bottom borders")
    func borderModifierRenders() {
        let view = Text("Test").border(style: .line)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        // Top border + content + bottom border
        #expect(buffer.height == 3)
        #expect(buffer.lines[0].contains("┌"))
        #expect(buffer.lines[1].contains("Test"))
        #expect(buffer.lines[2].contains("└"))
    }

    @Test(".border() with empty content returns empty")
    func borderModifierEmptyContent() {
        let view = EmptyView().border(style: .line)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        #expect(buffer.isEmpty)
    }

    @Test(".border() with line style uses correct corner characters")
    func borderModifierLineStyle() {
        let view = Text("X").border(style: .line)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        let topLine = buffer.lines[0].stripped
        let bottomLine = buffer.lines[buffer.height - 1].stripped

        #expect(topLine.hasPrefix("┌"))
        #expect(topLine.hasSuffix("┐"))
        #expect(bottomLine.hasPrefix("└"))
        #expect(bottomLine.hasSuffix("┘"))
    }

    @Test(".border() with doubleLine style uses correct characters")
    func borderModifierDoubleLineStyle() {
        let view = Text("X").border(style: .doubleLine)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        let topLine = buffer.lines[0].stripped
        let bottomLine = buffer.lines[buffer.height - 1].stripped

        #expect(topLine.hasPrefix("╔"))
        #expect(topLine.hasSuffix("╗"))
        #expect(bottomLine.hasPrefix("╚"))
        #expect(bottomLine.hasSuffix("╝"))
    }

    @Test(".border() with rounded style uses correct characters")
    func borderModifierRoundedStyle() {
        let view = Text("X").border(style: .rounded)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        let topLine = buffer.lines[0].stripped
        let bottomLine = buffer.lines[buffer.height - 1].stripped

        #expect(topLine.hasPrefix("╭"))
        #expect(topLine.hasSuffix("╮"))
        #expect(bottomLine.hasPrefix("╰"))
        #expect(bottomLine.hasSuffix("╯"))
    }

    @Test(".border() with heavy style uses correct characters")
    func borderModifierHeavyStyle() {
        let view = Text("X").border(style: .heavy)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        let topLine = buffer.lines[0].stripped
        let bottomLine = buffer.lines[buffer.height - 1].stripped

        #expect(topLine.hasPrefix("┏"))
        #expect(topLine.hasSuffix("┓"))
        #expect(bottomLine.hasPrefix("┗"))
        #expect(bottomLine.hasSuffix("┛"))
    }

    @Test(".border() adds 2 to content width: the two lines, and no padding (2026-11-17)")
    func borderModifierWidthOverhead() {
        let view = Text("ABCDE").border(style: .line)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        // Content "ABCDE" = 5, + 2 for borders = 7
        let topLine = buffer.lines[0].stripped
        #expect(topLine.count == 7)
    }

    @Test(".border() puts no blank cell inside its line; padding before it does")
    func borderModifierContentPadding() {
        let context = testContext()
        let bare = renderToBuffer(Text("Hi").border(style: .line), context: context)
        #expect(bare.lines[1].stripped == "│Hi│")

        // `.padding(.horizontal, 1)` is the look `.border()` had until 2026-11-17.
        let padded = renderToBuffer(Text("Hi").padding(.horizontal, 1).border(style: .line), context: context)
        #expect(padded.lines[1].stripped == "│ Hi │")
    }
}
