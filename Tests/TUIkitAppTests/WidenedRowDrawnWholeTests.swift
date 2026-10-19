//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WidenedRowDrawnWholeTests.swift
//
//  A row of a two-axis lazy stack widened while it was off screen is drawn
//  whole on the frame it scrolls in (the owner's ruling of 2026-09-23: a
//  horizontal extent may be an estimate, a drawn row must never be cut). The
//  case the width record's challenge cannot see: the row reads an
//  `@Observable` it was never drawn reading, so the write clears nothing, and
//  the record keeps its old widest row. The stack measures the rows entering
//  its band against the record, and a row wider than it sends the scroll view
//  to measure and draw once more, that frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

@Observable
private final class RowTexts {
    var texts: [String]

    init(count: Int, variable: Bool) {
        texts = (0..<count).map { index in
            if index == 0 { return "row 0 " + String(repeating: "y", count: 64) + "Z" }
            return variable && index % 2 == 1 ? "row \(index)\n  of \(index)" : "row \(index)"
        }
    }
}

@MainActor
@Suite("A row widened off screen is drawn whole when it scrolls in")
struct WidenedRowDrawnWholeTests {
    /// 300 one-line rows take the uniform window, 300 of one and two lines
    /// the anchored one, 40 the full walk (which measures every row's slot
    /// each frame, and drew it whole already).
    @Test(arguments: [(300, false), (300, true), (40, false)])
    func widenedRowIsDrawnWhole(count: Int, variable: Bool) {
        let model = RowTexts(count: count, variable: variable)
        let last = count - 1
        let view = ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { index in Text(model.texts[index]) }
            }
        }
        .scrollIndicators(.never)
        let (tui, focus) = (TUIContext(), FocusManager())
        func frame() -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focus
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
            tui.preferences.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focus.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focus.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            return buffer.lines.map(\.stripped)
        }
        _ = frame()
        _ = frame()
        let handler = focus.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        // Scrolled to the right edge of the widest row, 71 columns.
        handler?.horizontal.scrollToOffset(1_000)
        _ = frame()
        #expect(handler?.horizontal.scrollOffset == 31, "precondition")
        // Off screen, the last row grows past it: no row drawn reads it.
        let widened = "row \(last) " + String(repeating: "x", count: 110) + "END"
        model.texts[last] = widened
        _ = frame()
        _ = handler?.handleKeyEvent(KeyEvent(key: .end))
        let arrived = frame()
        let line = arrived.last { $0.contains("x") } ?? ""
        #expect(!line.contains("…") && line.hasSuffix("x"), "drawn whole on the frame it comes in: \(arrived)")
        #expect(handler?.horizontal.extent == widened.count, "the extent is the row's")
        handler?.horizontal.scrollToOffset(1_000)
        let right = frame()
        #expect(right.contains { $0.hasSuffix("END") }, "its end is reachable: \(right)")
    }
}
