//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollVisibilityTests.swift
//
//  `onScrollVisibilityChange(threshold:_:)`, against what SwiftUI reports
//  (measured on macOS 15: a first report for every observed view, then each
//  crossing of the threshold, a fraction AT the threshold counting as shown;
//  a view in no scroll view reported shown; a removed view not reported).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
import TUIkitLists
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("onScrollVisibilityChange")
struct ScrollVisibilityTests {

    @MainActor
    private final class Log {
        var reports: [(row: Int, visible: Bool)] = []

        func take() -> [String] {
            defer { reports.removeAll() }
            return reports.map { "\($0.row)\($0.visible ? "+" : "-")" }
        }
    }

    @MainActor
    private struct Frames {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        @discardableResult
        func render<V: View>(_ view: V, width: Int = 20, height: Int = 5) -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.applyRuntimeServices(from: tuiContext)
            environment.installVolatileReadTracker(VolatileReadTracker())
            let context = RenderContext(
                availableWidth: width, availableHeight: height,
                environment: environment, tuiContext: tuiContext)
            tuiContext.mouseEventDispatcher.beginRenderPass()
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.mouseEventDispatcher.geometry.endFrame(frame: buffer, retainedBy: tuiContext.stateStorage)
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer
        }
    }

    /// `count` rows, each `lines` tall, every one observed.
    private func rows(
        _ count: Int, lines: Int = 1, threshold: Double = 0.5, lazy: Bool = false, log: Log
    ) -> some View {
        let row = { (index: Int) in
            Text((0..<lines).map { "row \(index).\($0)" }.joined(separator: "\n"))
                .onScrollVisibilityChange(threshold: threshold) { log.reports.append((index, $0)) }
        }
        return Group {
            if lazy {
                LazyVStack(alignment: .leading, spacing: 0) { ForEach(0..<count, id: \.self, content: row) }
            } else {
                VStack(alignment: .leading, spacing: 0) { ForEach(0..<count, id: \.self, content: row) }
            }
        }
    }

    private func scrolled<Content: View>(
        _ content: Content, _ position: Binding<ScrollPosition>
    ) -> some View {
        ScrollView { content }.scrollPosition(position)
    }

    @Test("Every observed view reports once when it first appears, shown or not")
    func firstReport() {
        let frames = Frames()
        let log = Log()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        frames.render(scrolled(rows(8, log: log), binding))
        #expect(log.take() == ["0+", "1+", "2+", "3+", "4+", "5-", "6-", "7-"])
        // Nothing moved, nothing is reported.
        frames.render(scrolled(rows(8, log: log), binding))
        #expect(log.take().isEmpty)
    }

    @Test("A view reports at each crossing of the threshold, and half shown counts as shown")
    func crossingsAtHalf() {
        let frames = Frames()
        let log = Log()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = scrolled(rows(6, lines: 2, log: log), binding)
        frames.render(view)
        // A 5-line viewport over 2-line rows: row 2 shows one line of two.
        #expect(log.take() == ["0+", "1+", "2+", "3-", "4-", "5-"])

        position.scrollTo(y: 1)
        frames.render(view)
        // Row 0 is half shown, still shown; row 2 is now whole.
        #expect(log.take().isEmpty)

        position.scrollTo(y: 2)
        frames.render(view)
        // Row 0 is gone; row 3 shows one line of two.
        #expect(log.take() == ["0-", "3+"])
    }

    @Test("A threshold of its own: a whole view at 1.0, any view at 0")
    func customThresholds() {
        let frames = Frames()
        let whole = Log()
        let any = Log()
        frames.render(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<4, id: \.self) { index in
                        Text("a\nb")
                            .onScrollVisibilityChange(threshold: 1.0) { whole.reports.append((index, $0)) }
                            .onScrollVisibilityChange(threshold: 0) { any.reports.append((index, $0)) }
                    }
                }
            })
        #expect(whole.take() == ["0+", "1+", "2-", "3-"])
        // Exactly SwiftUI's rule: a fraction of 0 is not below a threshold of 0.
        #expect(any.take() == ["0+", "1+", "2+", "3+"])
    }

    @Test("A row a lazy stack stops drawing is reported hidden; one that comes back, shown")
    func windowedOutRowsReportHidden() {
        let frames = Frames()
        let log = Log()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = scrolled(rows(100, lazy: true, log: log), binding)
        frames.render(view)
        let first = log.take()
        #expect(first.prefix(5) == ["0+", "1+", "2+", "3+", "4+"])

        position.scrollTo(y: 60)
        frames.render(view)
        let after = log.take()
        // Row 0 was not drawn at all this frame, and is not on screen.
        #expect(after.contains("0-"))
        #expect(after.contains("60+"))
        #expect(!after.contains("0+"))

        position.scrollTo(y: 0)
        frames.render(view)
        #expect(log.take().contains("0+"))
    }

    @Test("A view removed from the tree is not reported, as SwiftUI reports nothing")
    func removedViewIsNotReported() {
        let frames = Frames()
        let log = Log()
        frames.render(ScrollView { rows(3, log: log) })
        #expect(log.take() == ["0+", "1+", "2+"])
        frames.render(ScrollView { rows(2, log: log) })
        #expect(log.take().isEmpty)
    }

    @Test("A view in no scroll view is reported shown, wherever it is")
    func outsideAnyScrollView() {
        let frames = Frames()
        let log = Log()
        frames.render(
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<8, id: \.self) { index in
                    Text("row \(index)").onScrollVisibilityChange { log.reports.append((index, $0)) }
                }
            })
        // A 5-line frame, eight rows: every one is reported shown.
        #expect(log.take() == ["0+", "1+", "2+", "3+", "4+", "5+", "6+", "7+"])
    }

    @Test("The nearest scroll view measures: a row of an inner one against its own viewport")
    func nestedScrollViews() {
        let frames = Frames()
        let log = Log()
        frames.render(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 1) {
                            ForEach(0..<6, id: \.self) { index in
                                Text("cell\(index)").onScrollVisibilityChange { log.reports.append((index, $0)) }
                            }
                        }
                    }
                    .frame(width: 12, height: 1)
                    Text("below")
                }
            }, width: 30)
        // Twelve columns show cell0 (0-4) whole, and cell1 (6-10) whole; cell2
        // starts at column 12, past the inner viewport, though the outer one
        // is thirty wide.
        #expect(log.take() == ["0+", "1+", "2-", "3-", "4-", "5-"])
    }

    @Test("A List is a scroll view to its rows' observers")
    func listRows() {
        let frames = Frames()
        let log = Log()
        frames.render(
            List {
                ForEach(0..<12, id: \.self) { index in
                    Text("row \(index)").onScrollVisibilityChange { log.reports.append((index, $0)) }
                }
            }, height: 6)
        let reports = log.take()
        #expect(reports.first == "0+")
        #expect(reports.contains("11-") || !reports.contains { $0.hasPrefix("11") })
        #expect(!reports.contains("11+"))
    }

    @Test("A frame that draws a view twice reports once, from the drawing it shows")
    func drawnTwiceReportsOnce() {
        let frames = Frames()
        let log = Log()
        frames.render(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<8, id: \.self) { index in
                        Text("row \(index)").onScrollVisibilityChange { log.reports.append((index, $0)) }
                    }
                }
                .drawnTwice()
            })
        #expect(log.take() == ["0+", "1+", "2+", "3+", "4+", "5-", "6-", "7-"])
    }

    @Test("A row served from a memo keeps reporting: its registration is replayed")
    func servedRowsKeepReporting() {
        let frames = Frames()
        let log = Log()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = scrolled(rows(40, lazy: true, log: log), binding)
        frames.render(view)
        _ = log.take()
        // The same frame again: the rows are served, and must still register,
        // or every one of them would vanish and be reported hidden.
        frames.render(view)
        #expect(log.take().isEmpty)
        position.scrollTo(y: 1)
        frames.render(view)
        // Row 6 joins the stack's band, a row past the viewport, and reports
        // for the first time — hidden.
        #expect(log.take() == ["0-", "5+", "6-"])
    }

    @Test("A scroll view served from a memo keeps what it measured: a row off screen is not reported shown")
    func servedScrollViewKeepsItsMeasures() {
        let frames = Frames()
        let log = Log()
        let page = { (tick: Int) in
            VStack(alignment: .leading, spacing: 0) {
                // Focused first, so the scroll view's registration is one a
                // memo replays (a focused control's is not).
                Button("tick \(tick)") {}
                // A row the `ForEach` memo serves whole, scroll view and all,
                // while the line above it changes.
                ForEach(0..<1, id: \.self) { _ in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<10, id: \.self) { index in
                                Text("row \(index)").onScrollVisibilityChange { log.reports.append((index, $0)) }
                            }
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
        frames.render(page(0), height: 8)
        #expect(log.take() == ["0+", "1+", "2+", "3-", "4-", "5-", "6-", "7-", "8-", "9-"])
        // The scroll view is served: its observers register again, and what
        // it measured of them is made again with them — rows 3 to 9 are still
        // below its viewport, not reported shown for having a marker in the
        // frame.
        frames.render(page(1), height: 8)
        #expect(log.take().isEmpty)
        frames.render(page(2), height: 8)
        #expect(log.take().isEmpty)
    }

    @Test("A row a glued scroll view draws twice in one frame keeps its marker: no false report for a row on screen")
    func redrawnBandKeepsMarkers() {
        let frames = Frames()
        var playing: [Int: Bool] = [:]
        let page = { (count: Int) in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        // An `onChange` keeps the row out of the memos, so every
                        // drawing of it is a fresh one, claiming its marker anew.
                        Text("row \(index)")
                            .onScrollVisibilityChange { playing[index] = $0 }
                            .onChange(of: count) {}
                    }
                }
            }
            .defaultScrollAnchor(.bottom)
        }
        frames.render(page(30), height: 20)
        frames.render(page(30), height: 20)
        #expect((10..<30).allSatisfy { playing[$0] == true })
        // Three rows arrive at once: the tail moves past the band's margin,
        // and the scroll view draws its content again at the new tail.
        frames.render(page(33), height: 20)
        #expect((13..<33).allSatisfy { playing[$0] == true })
        #expect((10..<13).allSatisfy { playing[$0] == false })
        frames.render(page(33), height: 20)
        #expect((13..<33).allSatisfy { playing[$0] == true })
    }
}

/// Renders its content twice into one walk, as a container correcting itself
/// does, and returns the second drawing — the first one narrower, so a report
/// taken from it would differ.
private struct DrawnTwice<Content: View>: View, Renderable, Layoutable {
    let content: Content

    var body: Never { fatalError("DrawnTwice renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var narrow = context
        narrow.availableWidth = 3
        _ = TUIkitView.renderToBuffer(content, context: narrow)
        return TUIkitView.renderToBuffer(content, context: context)
    }
}

extension View {
    fileprivate func drawnTwice() -> some View { DrawnTwice(content: self) }
}
