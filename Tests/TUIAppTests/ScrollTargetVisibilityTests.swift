//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollTargetVisibilityTests.swift
//
//  `onScrollTargetVisibilityChange(idType:threshold:_:)`: the ids of the
//  content stack's views a scroll view shows, reported once when it first
//  draws and then whenever the list changes.
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
@Suite("onScrollTargetVisibilityChange")
struct ScrollTargetVisibilityTests {
    /// Every list the action was called with, in order.
    private final class Reports<ID: Hashable> {
        var lists: [[ID]] = []
    }

    /// Renders one frame `height` lines tall, driving the render-pass hooks
    /// the way the run loop does: the report is made as the frame finishes.
    @discardableResult
    private func frame<V: View>(_ view: V, _ tui: TUIContext, _ focus: FocusManager, height: Int = 6) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.verticalScrollIndicatorVisibility = .hidden
        environment.horizontalScrollIndicatorVisibility = .hidden
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 20, availableHeight: height, environment: environment, tuiContext: tui)
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

    private func handler(_ focus: FocusManager) -> ScrollViewHandler? {
        focus.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
    }

    @Test("The rows shown are reported once at first, then whenever they change", arguments: [false, true])
    func reportsTheRowsShown(lazy: Bool) {
        let (tui, focus) = (TUIContext(), FocusManager())
        let reports = Reports<Int>()
        let rows = ForEach(0..<40, id: \.self) { Text("row \($0)") }
        let view = (lazy ? AnyView(ScrollView { LazyVStack(spacing: 0) { rows } })
            : AnyView(ScrollView { VStack(spacing: 0) { rows }.scrollTargetLayout() }))
            .onScrollTargetVisibilityChange(idType: Int.self) { reports.lists.append($0) }
        frame(view, tui, focus)
        #expect(reports.lists == [Array(0..<6)])
        frame(view, tui, focus)
        #expect(reports.lists.count == 1, "nothing changed, nothing reported")
        handler(focus)?.userScrollFine(by: 3)
        frame(view, tui, focus)
        #expect(reports.lists.last == Array(3..<9))
        #expect(reports.lists.count == 2)
    }

    /// Past the full walk's threshold: one-line rows take the uniform window,
    /// rows of two heights the anchored one, which knows only its band.
    @Test("A long stack's rows are reported on its windowed paths", arguments: [false, true])
    func longStacks(varied: Bool) {
        let (tui, focus) = (TUIContext(), FocusManager())
        let reports = Reports<Int>()
        let view = ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<1_000, id: \.self) { Text("row \($0)").frame(height: varied && $0 % 2 == 1 ? 2 : 1) }
            }
        }
        .onScrollTargetVisibilityChange(idType: Int.self) { reports.lists.append($0) }
        frame(view, tui, focus)
        frame(view, tui, focus)
        #expect(reports.lists.first == (varied ? [0, 1, 2, 3] : Array(0..<6)))
        handler(focus)?.userScrollFine(by: 600)
        let screen = frame(view, tui, focus)
        let first = Int(screen.first?.split(separator: " ").last ?? "") ?? -1
        #expect(reports.lists.last?.first == first, "\(screen) \(reports.lists.last ?? [])")
        #expect((reports.lists.last?.count ?? 0) >= (varied ? 3 : 6), "\(reports.lists.last ?? [])")
    }

    @Test("A row counts once the threshold of it is shown")
    func threshold() {
        let (tui, focus) = (TUIContext(), FocusManager())
        let half = Reports<Int>()
        let most = Reports<Int>()
        // Two-line rows; scrolled by one line, row 0 shows its second line
        // and row 3 its first: half of each.
        let view = ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<20, id: \.self) { Text("row \($0)").frame(height: 2) }
            }
        }
        .onScrollTargetVisibilityChange(idType: Int.self) { half.lists.append($0) }
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.6) { most.lists.append($0) }
        frame(view, tui, focus)
        handler(focus)?.userScrollFine(by: 1)
        frame(view, tui, focus)
        #expect(half.lists.last == [0, 1, 2, 3])
        #expect(most.lists.last == [1, 2])
    }

    @Test("A heading above the loop is no view with an id, and a tagged view is reported by its tag")
    func mixedContent() {
        let (tui, focus) = (TUIContext(), FocusManager())
        let reports = Reports<Int>()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("heading")
                ForEach(0..<3, id: \.self) { Text("row \($0)") }
                Text("tagged").id(100)
                ForEach(10..<20, id: \.self) { Text("row \($0)") }
            }
        }
        .onScrollTargetVisibilityChange(idType: Int.self) { reports.lists.append($0) }
        frame(view, tui, focus)
        #expect(reports.lists == [[0, 1, 2, 100, 10]])
    }

    @Test("Ids of another type are left out")
    func otherTypes() {
        let (tui, focus) = (TUIContext(), FocusManager())
        let reports = Reports<String>()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("a").id("a")
                Text("one").id(1)
                ForEach(["b", "c"], id: \.self) { Text($0) }
            }
        }
        .onScrollTargetVisibilityChange(idType: String.self) { reports.lists.append($0) }
        frame(view, tui, focus)
        #expect(reports.lists == [["a", "b", "c"]])
    }

    @Test("A carousel reports the columns it shows", arguments: [false, true])
    func columns(lazy: Bool) {
        let (tui, focus) = (TUIContext(), FocusManager())
        let reports = Reports<Int>()
        let cards = ForEach(0..<10, id: \.self) { Text("card\($0)").frame(width: 8) }
        let view = (lazy ? AnyView(ScrollView(.horizontal) { LazyHStack(spacing: 0) { cards } })
            : AnyView(ScrollView(.horizontal) { HStack(spacing: 0) { cards } }))
            .onScrollTargetVisibilityChange(idType: Int.self) { reports.lists.append($0) }
        frame(view, tui, focus, height: 2)
        // Twenty columns: two cards whole and half of the third.
        #expect(reports.lists == [[0, 1, 2]])
    }

    @Test("Under content margins the rows are measured where they are drawn")
    func underMargins() {
        let (tui, focus) = (TUIContext(), FocusManager())
        let reports = Reports<Int>()
        let view = ScrollView {
            LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row \($0)") } }
        }
        .contentMargins(.top, 2)
        .onScrollTargetVisibilityChange(idType: Int.self) { reports.lists.append($0) }
        frame(view, tui, focus)
        #expect(reports.lists == [Array(0..<4)])
    }
}
