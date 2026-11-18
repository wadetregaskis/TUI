//  🖥️ TUI — A Terminal UI framework for Swift
//  BorderHugsContentTests.swift
//
//  `.border()` hugs what it borders: padding is the inset, as in SwiftUI (the
//  owner, 2026-11-17; deviations L20). Until then a border put a blank cell
//  either side of its content inside the line, and the framework's own chrome
//  still does (`bordered(…, insetsContent: true)`), so that path is the old
//  `.border()` these compare against, cell for cell.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A border hugs its content; padding is the inset")
struct BorderHugsContentTests {
    private func draw<V: View>(_ view: V, width: Int = 30, height: Int = 12) -> FrameBuffer {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
    }

    /// What `.border(…)` drew before 2026-11-17: the chrome's path, which
    /// keeps the blank cell either side.
    private func oldBorder<V: View>(_ view: V, colour: Color? = nil, width: Int = 1) -> some View {
        view.bordered(style: nil, colour: colour.map(AnimatedColor.init), width: width, insetsContent: true)
    }

    @Test("A bare border is the line round the content and nothing else")
    func bareBorderHugs() {
        let buffer = draw(Text("Hi").border(style: .line))
        #expect(buffer.lines.map(\.stripped) == ["┌──┐", "│Hi│", "└──┘"])
    }

    @Test("A column of lines is hugged too: the widest line touches both sides")
    func columnHugs() {
        let buffer = draw(VStack(alignment: .leading, spacing: 0) { Text("abc"); Text("a") }.border(style: .line))
        #expect(buffer.lines.map(\.stripped) == ["┌───┐", "│abc│", "│a  │", "└───┘"])
    }

    @Test("Horizontal padding of one before the border is the old border, cell for cell")
    func horizontalPaddingIsTheOldBorder() {
        #expect(draw(Text("Hi").padding(.horizontal, 1).border()) == draw(oldBorder(Text("Hi"))))
        #expect(
            draw(Text("Warning").padding(.horizontal, 1).border(.red, style: .rounded))
                == draw(Text("Warning").bordered(
                    style: .rounded, colour: AnimatedColor(.red), width: 1, insetsContent: true)))
        let column = VStack(alignment: .leading, spacing: 0) { Text("first"); Text("second line") }
        #expect(draw(column.padding(.horizontal, 1).border()) == draw(oldBorder(column)))
        // Squeezed narrower than the text, the two still agree.
        #expect(
            draw(Text("a longer line").padding(.horizontal, 1).border(), width: 8)
                == draw(oldBorder(Text("a longer line")), width: 8))
    }

    @Test("Padding of one on every side adds a blank row above and below as well, as SwiftUI's does")
    func allSidePaddingAddsRows() {
        let buffer = draw(Text("Hi").padding(1).border(style: .line))
        #expect(buffer.lines.map(\.stripped) == ["┌────┐", "│    │", "│ Hi │", "│    │", "└────┘"])
    }

    @Test("Each ring of width: is its line alone, and rings still nest")
    func ringsNest() {
        let two = draw(Text("Hi").border(style: .line, width: 2))
        #expect(two.lines.map(\.stripped) == ["┌────┐", "│┌──┐│", "││Hi││", "│└──┘│", "└────┘"])
        #expect(two == draw(Text("Hi").border(style: .line).border(style: .line)))
        // The old two rings: a blank cell inside each line.
        #expect(
            draw(Text("Hi").padding(.horizontal, 1).border().padding(.horizontal, 1).border())
                == draw(oldBorder(Text("Hi"), width: 2)))
    }

    @Test("A background on the bordered view reaches the line with no inset to fill")
    func backgroundReachesTheLine() {
        let lines = draw(Text("ab").background(Color.red).border()).lines
        #expect(lines[1].stripped == "│ab│")
        #expect(lines[1].ansiSGRStateAt(visibleColumn: 1).namesBackground)
        #expect(lines[1].ansiSGRStateAt(visibleColumn: 2).namesBackground)
        #expect(!lines[1].ansiSGRStateAt(visibleColumn: 0).namesBackground, "not the line itself")
    }

    @Test("The order of padding and background says whether the background reaches the line")
    func paddingOrderDecidesTheFill() {
        // Padding first: the background is the padding's too, up to the line.
        let filled = draw(Text("ab").padding(.horizontal, 1).background(Color.red).border()).lines[1]
        #expect(filled.stripped == "│ ab │")
        #expect(filled.ansiSGRStateAt(visibleColumn: 1).namesBackground)
        // Background first: it stops at the text, and the padding is clear.
        let clear = draw(Text("ab").background(Color.red).padding(.horizontal, 1).border()).lines[1]
        #expect(clear.stripped == "│ ab │")
        #expect(!clear.ansiSGRStateAt(visibleColumn: 1).namesBackground)
        #expect(clear.ansiSGRStateAt(visibleColumn: 2).namesBackground, "the text keeps it")
    }
}
