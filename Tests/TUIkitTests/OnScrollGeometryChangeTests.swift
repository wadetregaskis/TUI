//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnScrollGeometryChangeTests.swift
//
//  `ScrollGeometry` and `onScrollGeometryChange`, against the readings SwiftUI
//  gives (measured on macOS 15; see the W10 decisions document).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitView

@MainActor
@Suite("onScrollGeometryChange")
struct OnScrollGeometryChangeTests {

    @MainActor
    private struct Frames {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        @discardableResult
        func render<V: View>(_ view: V, width: Int = 20, height: Int = 6) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: width, availableHeight: height,
                environment: environment, tuiContext: tuiContext)
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer.lines.map(\.stripped)
        }

        var handler: ScrollViewHandler? {
            focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        }
    }

    /// Records every call an observer makes.
    @MainActor
    private final class Log<T> {
        var calls: [(old: T, new: T)] = []
    }

    private func rows(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { Text("row \($0)") }
        }
    }

    @Test("The first frame reports, with the same value as old and new, as SwiftUI does")
    func firstFrameReports() {
        let frames = Frames()
        let log = Log<ScrollGeometry>()
        let view = ScrollView { rows(20) }
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }, action: { log.calls.append(($0, $1)) })
        frames.render(view)
        #expect(log.calls.count == 1)
        let first = log.calls.first
        #expect(first?.old == first?.new)
        #expect(first?.new.contentOffset == CellPoint(x: 0, y: 0))
        #expect(first?.new.contentSize == CellSize(width: 20, height: 20))
        #expect(first?.new.containerSize == CellSize(width: 20, height: 6))
        #expect(first?.new.contentInsets == EdgeInsets())

        // Nothing moved, nothing is reported.
        frames.render(view)
        #expect(log.calls.count == 1)
    }

    @Test("A scroll reports the old and the new geometry")
    func scrollReports() {
        let frames = Frames()
        let log = Log<Int>()
        let view = ScrollView { rows(20) }
            .onScrollGeometryChange(for: Int.self, of: { $0.contentOffset.y }, action: { log.calls.append(($0, $1)) })
        frames.render(view)
        frames.handler?.userScrollFine(by: 3)
        frames.render(view)
        #expect(log.calls.count == 2)
        #expect(log.calls.last?.old == 0 && log.calls.last?.new == 3)
    }

    @Test("Only a change in the derived value acts")
    func derivedValueGatesTheAction() {
        let frames = Frames()
        let log = Log<Bool>()
        let view = ScrollView { rows(20) }
            .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 4 }, action: { log.calls.append(($0, $1)) })
        frames.render(view)
        frames.handler?.userScrollFine(by: 2)
        frames.render(view)
        #expect(log.calls.count == 1, "2 is still not past 4")
        frames.handler?.userScrollFine(by: 3)
        frames.render(view)
        #expect(log.calls.count == 2)
        #expect(log.calls.last.map { !$0.old && $0.new } == true)
    }

    @Test("Content margins are insets before the content's origin, as SwiftUI reports them")
    func marginsAreInsets() {
        let frames = Frames()
        let log = Log<ScrollGeometry>()
        let view = ScrollView { rows(20) }
            .contentMargins(.vertical, 2)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }, action: { log.calls.append(($0, $1)) })
        frames.render(view)
        let top = log.calls.last?.new
        #expect(top?.contentOffset == CellPoint(x: 0, y: -2))
        #expect(top?.contentInsets == EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        #expect(top?.contentSize.height == 20)
        #expect(top?.containerSize == CellSize(width: 20, height: 2))
        #expect(top?.bounds == CellRect(x: 0, y: -2, width: 20, height: 2))
        #expect(top?.visibleRect == CellRect(x: 0, y: -2, width: 20, height: 6))

        frames.handler?.userScrollToBottom()
        frames.render(view)
        if let bottom = log.calls.last?.new {
            // At the bottom the visible area reaches the end of the bottom margin,
            // and the bounds — the container's size from the offset — stop both
            // margins short of it.
            #expect(bottom.visibleRect.maxY == bottom.contentSize.height + bottom.contentInsets.bottom)
            #expect(bottom.bounds.maxY == bottom.visibleRect.maxY - 4, "\(bottom)")
        } else {
            Issue.record("no report")
        }
    }

    @Test("A horizontal scroll is the x offset")
    func horizontalOffset() {
        let frames = Frames()
        let log = Log<Int>()
        let view = ScrollView(.horizontal) { Text(String(repeating: "x", count: 50)) }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Int.self, of: { $0.contentOffset.x }, action: { log.calls.append(($0, $1)) })
        frames.render(view, height: 3)
        frames.handler?.horizontal.scroll(by: 7)
        frames.render(view, height: 3)
        #expect(log.calls.last?.new == 7)
    }

    @Test("Only the first scroll view reports: not one in its content, nor one beside it")
    func onlyTheFirstScrollViewReports() {
        let frames = Frames()
        let log = Log<CellSize>()
        let view = VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ScrollView { rows(3) }.frame(height: 2)
                    rows(10)
                }
            }
            .frame(height: 3)
            ScrollView { rows(40) }.frame(height: 3)
        }
        .onScrollGeometryChange(for: CellSize.self, of: { $0.contentSize }, action: { log.calls.append(($0, $1)) })
        frames.render(view)
        #expect(log.calls.count == 1, "\(log.calls)")
        // The first scroll view's content: its inner view's two lines and ten rows.
        #expect(log.calls.first?.new.height == 12, "\(log.calls)")
    }
}
