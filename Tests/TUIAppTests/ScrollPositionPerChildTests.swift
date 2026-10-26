//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollPositionPerChildTests.swift
//
//  `.scrollPosition` read-back per child: the row a scroll view reports is
//  named by its own loop's element or by its `.id(_:)` tag, whatever else is in
//  the stack — a heading above a loop, two loops, tagged views — in eager and
//  lazy stacks alike. Before, only a stack whose content was one `ForEach`
//  reported anything.
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
@Suite("ScrollPosition read-back, per child")
struct ScrollPositionPerChildTests {
    /// Renders one frame six lines tall, driving the render-pass hooks the way
    /// the run loop does: the write-back is a render-time side effect.
    @discardableResult
    private func frame<V: View>(_ view: V, _ tui: TUIContext, _ focus: FocusManager) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 6, environment: environment, tuiContext: tui)
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focus.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// Scrolls the frame's scroll view by `lines`, as the user would.
    private func userScroll(_ lines: Int, _ focus: FocusManager) {
        focus.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first?
            .userScrollFine(by: lines)
    }

    /// `rows` in a lazy or an eager column, in a scroll view bound by id.
    private func column<Rows: View, ID: Hashable>(
        lazy: Bool, id: Binding<ID?>, anchor: UnitPoint? = nil, @ViewBuilder _ rows: () -> Rows
    ) -> AnyView {
        lazy
            ? AnyView(
                ScrollView { LazyVStack(alignment: .leading, spacing: 0) { rows() } }
                    .scrollPosition(id: id, anchor: anchor))
            : AnyView(
                ScrollView { VStack(alignment: .leading, spacing: 0) { rows() } }.scrollPosition(id: id, anchor: anchor))
    }

    @Test("A loop's row under a heading is reported by its element", arguments: [false, true])
    func loopUnderAHeading(lazy: Bool) {
        let (tui, focus) = (TUIContext(), FocusManager())
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0 })
        let view = column(lazy: lazy, id: binding) {
            Text("heading")
            ForEach(0..<40, id: \.self) { Text("row \($0)") }
        }
        frame(view, tui, focus)
        #expect(visible == nil, "the heading has no id to report")
        userScroll(5, focus)
        let screen = frame(view, tui, focus)
        #expect(screen.first?.hasPrefix("row 4") == true, "precondition: \(screen)")
        #expect(visible == 4, "\(screen)")
    }

    @Test("Two loops over the same ids: each row is reported by its own loop", arguments: [false, true])
    func twoLoops(lazy: Bool) {
        let (tui, focus) = (TUIContext(), FocusManager())
        var visible: String?
        let binding = Binding<String?>(get: { visible }, set: { visible = $0 })
        let view = column(lazy: lazy, id: binding) {
            ForEach(["a", "b", "c"], id: \.self) { Text("first \($0)") }
            ForEach(["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"], id: \.self) { Text("second \($0)") }
        }
        frame(view, tui, focus)
        #expect(visible == "a")
        userScroll(4, focus)
        let screen = frame(view, tui, focus)
        #expect(screen.first?.hasPrefix("second b") == true, "precondition: \(screen)")
        #expect(visible == "b", "\(screen)")
    }

    @Test("A view tagged with .id(_:) is reported by its tag, as its own type", arguments: [false, true])
    func taggedViews(lazy: Bool) {
        let (tui, focus) = (TUIContext(), FocusManager())
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0 })
        let view = column(lazy: lazy, id: binding) {
            Text("ten").id(10)
            Text("twenty").id(20)
            Text("untagged")
            Text("forty").id(40)
            Text("fifty").padding(.leading, 1).id(50)
            Text("sixty").id(60)
            Text("seventy").id(70)
            Text("eighty").id(80)
            Text("ninety").id(90)
            Text("hundred").id(100)
        }
        frame(view, tui, focus)
        #expect(visible == 10)
        userScroll(1, focus)
        frame(view, tui, focus)
        #expect(visible == 20)
        userScroll(1, focus)
        frame(view, tui, focus)
        #expect(visible == 20, "an untagged view reports nothing, and the binding keeps the last")
        userScroll(2, focus)
        let screen = frame(view, tui, focus)
        #expect(screen.first?.hasPrefix("fifty") == true, "precondition: \(screen)")
        #expect(visible == 50, "\(screen)")
    }

    /// The frame a request lands on reports the row it shows. An eager stack
    /// sampled its row at the offset the view was leaving, which the seek's
    /// offset replaces only after the stack has drawn: a request for row 20
    /// wrote back row 0, and a frame later row 20.
    @Test("The frame a request lands on writes back nothing new", arguments: [false, true])
    func requestFrameReportsItsRow(lazy: Bool) {
        let (tui, focus) = (TUIContext(), FocusManager())
        var visible: Int?
        var writes: [Int?] = []
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0; writes.append($0) })
        let view = column(lazy: lazy, id: binding, anchor: .top) { ForEach(0..<40, id: \.self) { Text("row \($0)") } }
        frame(view, tui, focus)
        #expect(writes == [0])
        visible = 20
        writes = []
        for index in 0..<2 {
            let screen = frame(view, tui, focus)
            #expect(screen.first?.hasPrefix("row 20") == true, "frame \(index): \(screen)")
        }
        #expect(writes.isEmpty, "\(writes)")
        #expect(visible == 20)
    }
}
