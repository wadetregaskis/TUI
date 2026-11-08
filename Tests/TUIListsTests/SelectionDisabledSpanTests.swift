//  🖥️ TUI — A Terminal UI framework for Swift
//  SelectionDisabledSpanTests.swift
//
//  A `.selectionDisabled()` row refused Return, Space and a click, and the
//  cursor passed over it — but the two gestures that select many rows at once
//  took it anyway. Select-all took every content row, and a range (Shift+arrow,
//  Shift-click, Shift+Home/End, the extend mode) took every row between its
//  ends, though the span's own comment said it skipped the rows that cannot be
//  selected. SwiftUI's `selectionDisabled` keeps a row out of both.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUILists
@testable import TUITestSupport

@MainActor
@Suite("selectionDisabled rows stay out of spans and select-all")
struct SelectionDisabledSpanTests {

    @MainActor
    private final class Fixture {
        let tui = TUIContext()
        var env = EnvironmentValues()
        var selection = Set<Int>()

        init() {
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        var handler: ItemListHandler<Int>? {
            env.focusManager?.currentFocused as? ItemListHandler<Int>
        }

        /// Five rows, the middle one locked.
        func render() {
            let view = List(selection: Binding(get: { self.selection }, set: { self.selection = $0 })) {
                ForEach(0..<5, id: \.self) { row in
                    Text("row \(row)").selectionDisabled(row == 2)
                }
            }
            .frame(height: 8)
            tui.stateStorage.beginRenderPass()
            env.focusManager?.beginRenderPass()
            _ = renderToBuffer(
                view, context: RenderContext(availableWidth: 24, availableHeight: 10, environment: env, tuiContext: tui))
            env.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
    }

    @Test("Select-all leaves the locked row out")
    func selectAll() {
        let fixture = Fixture()
        fixture.render()
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.handleKeyEvent(KeyEvent(key: .character("a"), ctrl: true)))
        #expect(fixture.selection == [0, 1, 3, 4], "\(fixture.selection.sorted())")
    }

    @Test("Shift+Down across the locked row leaves it out of the span")
    func shiftArrowSpan() {
        let fixture = Fixture()
        fixture.render()
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        handler.focusedIndex = 0
        for _ in 0..<4 { _ = handler.handleKeyEvent(KeyEvent(key: .down, shift: true)) }
        #expect(handler.focusedIndex == 4)
        #expect(fixture.selection == [0, 1, 3, 4], "\(fixture.selection.sorted())")
    }

    @Test("A Shift-click span leaves the locked row out")
    func shiftClickSpan() {
        let fixture = Fixture()
        fixture.render()
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        handler.handleClickSelection(at: 0, event: MouseEvent(button: .left, phase: .released, x: 0, y: 0))
        handler.handleClickSelection(
            at: 4, event: MouseEvent(button: .left, phase: .released, x: 0, y: 4, shift: true))
        #expect(fixture.selection == [0, 1, 3, 4], "\(fixture.selection.sorted())")
    }
}
