//  🖥️ TUI — A Terminal UI framework for Swift
//  RevealAcrossTests.swift
//
//  Reveal-on-focus across: a control the focus moves to past the side of a
//  view that scrolls horizontally is scrolled into view, as one past its top
//  or bottom is. Found by the 2026-10-19 audit of auto-scroll's edge cases:
//  Tab along a row of buttons in a `ScrollView(.horizontal)`, or across a
//  grid of them in a two-axis view, focused the ones past the edge and left
//  them unseen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("Reveal-on-focus across")
struct RevealAcrossTests {
    @discardableResult
    private func frame<V: View>(_ view: V, _ tui: TUIContext, _ focus: FocusManager) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 30, availableHeight: 6, environment: environment, tuiContext: tui)
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

    /// Walks the focus `steps` times forward, then as far back, and returns
    /// the steps whose control was not on screen.
    private func unseen<V: View>(_ view: V, steps: Int, label: (Int) -> String) -> [Int] {
        let (tui, focus) = (TUIContext(), FocusManager())
        frame(view, tui, focus)
        guard let first = focus.registeredFocusIDsInActiveSection().first else { return [-1] }
        focus.focus(id: first)
        frame(view, tui, focus)
        var missed: [Int] = []
        for step in 1...steps {
            focus.focusNext()
            if !frame(view, tui, focus).contains(where: { $0.contains(label(step)) }) { missed.append(step) }
        }
        for step in (0..<steps).reversed() {
            focus.focusPrevious()
            if !frame(view, tui, focus).contains(where: { $0.contains(label(step)) }) { missed.append(-step - 1) }
        }
        return missed
    }

    @Test("Tab along a row of buttons scrolls each one into view, and Shift-Tab back", arguments: [false, true])
    func rowOfButtons(lazy: Bool) {
        let buttons = ForEach(0..<20, id: \.self) { Button("btn\($0)") {} }
        let view =
            lazy
            ? AnyView(ScrollView(.horizontal) { LazyHStack(spacing: 1) { buttons } })
            : AnyView(ScrollView(.horizontal) { HStack(spacing: 1) { buttons } })
        #expect(unseen(view, steps: 15, label: { "btn\($0)" }).isEmpty)
    }

    @Test("Tab across a grid of buttons in a two-axis view keeps each one in view")
    func gridOfButtons() {
        let view = ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<10, id: \.self) { row in
                    HStack(spacing: 1) { ForEach(0..<6, id: \.self) { column in Button("r\(row)c\(column)") {} } }
                }
            }
        }
        #expect(unseen(view, steps: 30, label: { "r\($0 / 6)c\($0 % 6)" }).isEmpty)
    }

    @Test("A control wider than the view is shown from its leading edge")
    func widerThanTheView() {
        let (tui, focus) = (TUIContext(), FocusManager())
        let view = ScrollView(.horizontal) {
            HStack(spacing: 1) {
                Button("first") {}
                Button("wide" + String(repeating: "-", count: 40) + "end") {}
            }
        }
        frame(view, tui, focus)
        let ring = focus.registeredFocusIDsInActiveSection()
        focus.focus(id: ring[0])
        frame(view, tui, focus)
        focus.focusNext()
        let lines = frame(view, tui, focus)
        #expect(lines.first?.contains("wide") == true, "\(lines)")
        #expect(lines.first?.contains("end") == false, "\(lines)")
    }
}
