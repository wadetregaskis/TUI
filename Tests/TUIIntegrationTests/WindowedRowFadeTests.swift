//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowedRowFadeTests.swift
//
//  The default transition in the containers that window their rows or lay out
//  a lattice: a lazy stack, a `Grid`, a lazy grid, a `List`, a `Table`. A row
//  an animated change puts in fades in where it lands, as it does in an eager
//  stack (`BranchAndRowFadeTests`) and as SwiftUI's does with no `.transition`
//  written; one with a transition of its own plays its removal where it was.
//  A row that is only scrolled into view is not an arrival.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import Testing

import TUIEffects
@testable import TUIFoundation
import TUIGrid
import TUILists
import TUITables
@testable import TUITestSupport

/// A row of a table, by its number.
private struct Item: Identifiable {
    let id: Int
    var name: String { String(repeating: "\(id)", count: 4) }
}

/// How many times the ids of ``CountedItem``s have been read.
private final class IDReads: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func note() { count.withLock { $0 += 1 } }
    func reset() { count.withLock { $0 = 0 } }
}

/// A row whose id counts its reads: what a container's search of its rows by
/// key costs, in keys.
private struct CountedItem: Identifiable {
    let number: Int
    let reads: IDReads
    var id: Int {
        reads.note()
        return number
    }
    /// The number alone: four digits fit the narrowest of the containers.
    var name: String { "\(number)" }
}

/// Where a reader's proxy is kept, for a test to scroll with between frames.
@MainActor
private final class ProxyBox {
    var proxy: ScrollViewProxy?
}

/// `items` as rows of `shape` (a scrolling one), in a reader whose proxy
/// `box` keeps.
private struct ScrolledRows: View {
    let items: [CountedItem]
    let shape: WindowedShape
    let box: ProxyBox

    var body: some View {
        ScrollViewReader { proxy in
            let _ = box.proxy = proxy  // swiftlint:disable:this redundant_discardable_let
            switch shape {
            case .list:
                List(items) { Text($0.name) }
            case .table:
                Table(items) { TableColumn("N", value: \CountedItem.name) }
            default:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { Text($0.name) }
                    }
                }
            }
        }
    }
}

/// The containers under test, each holding a loop's rows.
enum WindowedShape: String, CaseIterable, Sendable {
    case lazyStack, scrolledLazyStack, grid, lazyGrid, list, table
}

/// `ids` as rows of `shape`.
private struct Rows: View {
    let ids: [Int]
    let shape: WindowedShape

    var body: some View {
        switch shape {
        case .lazyStack:
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(ids, id: \.self) { id in Text(Item(id: id).name) }
            }
        case .scrolledLazyStack:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(ids, id: \.self) { id in Text(Item(id: id).name) }
                }
            }
        case .grid:
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(ids, id: \.self) { id in GridRow { Text(Item(id: id).name) } }
            }
        case .lazyGrid:
            LazyVGrid(columns: [GridItem(.flexible())], alignment: .leading, spacing: 0) {
                ForEach(ids, id: \.self) { id in Text(Item(id: id).name) }
            }
        case .list:
            List(ids, id: \.self) { id in Text(Item(id: id).name) }
        case .table:
            Table(ids.map(Item.init)) { TableColumn("N", value: \Item.name) }
        }
    }
}

/// `ids` as a lazy stack's rows, each with a transition of its own.
private struct SlidingRows: View {
    let ids: [Int]
    let scrolled: Bool

    var body: some View {
        if scrolled {
            ScrollView { stack }
        } else {
            stack
        }
    }

    private var stack: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(ids, id: \.self) { id in
                Text(Item(id: id).name).transition(.move(edge: .trailing))
            }
        }
    }
}

/// A view drawn frame by frame as the run loop draws it: the change's
/// transaction in force for the one pass that shows the change.
@MainActor
private final class Frames {
    var context = makeRenderContext(width: 12, height: 8)
    var storage: StateStorage { context.environment.stateStorage! }

    init() {
        context.environment.canAnimate = true
    }

    /// `view` at `millis`, under a one-second linear change when `changed`.
    func buffer<V: View>(_ view: V, atMillis millis: Int, changed: Bool = false) -> FrameBuffer {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        context.environment.transaction = Transaction(animation: changed ? .linear(duration: 1) : nil)
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(view, context: context)
    }

    /// The rows drawn, layers included, styling and trailing blanks stripped.
    func draw<V: View>(_ view: V, atMillis millis: Int, changed: Bool = false) -> [String] {
        buffer(view, atMillis: millis, changed: changed).withLayersDrawn().lines.map(\.stripped).map {
            String($0.reversed().drop { $0 == " " }.reversed())
        }
    }
}

/// The strengths of the fades a frame still carries, its layers' included.
private func fades(_ buffer: FrameBuffer) -> [Double] {
    var found = buffer.opacityRegions.map { ($0.opacity * 100).rounded() / 100 }
    for layer in buffer.overlays { found += fades(layer.content) }
    return found
}

@MainActor
@Suite("A row fades in, and plays its own removal, where the container windows its rows")
struct WindowedRowFadeTests {
    @Test("A row inserted under an animation fades in where it lands", arguments: WindowedShape.allCases)
    func rowInsertedFades(shape: WindowedShape) {
        let frames = Frames()
        _ = frames.draw(Rows(ids: [1, 3], shape: shape), atMillis: 0)
        _ = frames.draw(Rows(ids: [1, 2, 3], shape: shape), atMillis: 1000, changed: true)
        let late = frames.buffer(Rows(ids: [1, 2, 3], shape: shape), atMillis: 1600)
        #expect(fades(late) == [0.6], "fading in: \(fades(late))")
        let drawn = late.withLayersDrawn().lines.map(\.stripped).joined(separator: "/")
        #expect(drawn.contains("2222"), "past half-way, drawn: \(drawn)")
        #expect(fades(frames.buffer(Rows(ids: [1, 2, 3], shape: shape), atMillis: 2100)).isEmpty)
    }

    @Test("Without an animation a row comes at once", arguments: WindowedShape.allCases)
    func unanimatedRowIsInstant(shape: WindowedShape) {
        let frames = Frames()
        _ = frames.draw(Rows(ids: [1, 3], shape: shape), atMillis: 0)
        #expect(fades(frames.buffer(Rows(ids: [1, 2, 3], shape: shape), atMillis: 1000)).isEmpty)
    }

    @Test("A container seen for the first time is not an arrival", arguments: WindowedShape.allCases)
    func firstAppearanceIsNotAnArrival(shape: WindowedShape) {
        let frames = Frames()
        #expect(fades(frames.buffer(Rows(ids: [1, 2], shape: shape), atMillis: 0, changed: true)).isEmpty)
    }

    /// A row the window reaches only because the rows above it went is not
    /// one the change put in: it was among the rows already.
    @Test("A row brought into the window by a removal above it does not fade", arguments: WindowedShape.allCases)
    func rowBroughtIntoTheWindowDoesNotFade(shape: WindowedShape) {
        let frames = Frames()
        let all = Array(1...20)
        _ = frames.draw(Rows(ids: all, shape: shape), atMillis: 0)
        _ = frames.buffer(Rows(ids: Array(all.dropFirst(2)), shape: shape), atMillis: 1000, changed: true)
        #expect(fades(frames.buffer(Rows(ids: Array(all.dropFirst(2)), shape: shape), atMillis: 1500)).isEmpty)
    }

    /// Whether a row the window reaches was a row already is asked of the
    /// row's own place first, which a scroll does not change: asked by a scan
    /// from the first row, a glide deep in the rows read every key above the
    /// window on each frame that brought a row in (Stress's `glide` took
    /// 3.5 ms a frame three thousand frames in, against 0.36 ms at first).
    @Test(
        "A glide deep in the rows reads the keys of the rows it draws, not of every row above them",
        arguments: [WindowedShape.scrolledLazyStack, .list, .table])
    func glideDeepInTheRowsReadsFewKeys(shape: WindowedShape) {
        let frames = Frames()
        let reads = IDReads()
        let box = ProxyBox()
        let rows = ScrolledRows(
            items: (0..<2_000).map { CountedItem(number: $0, reads: reads) }, shape: shape, box: box)
        _ = frames.draw(rows, atMillis: 0)
        box.proxy?.scrollTo(1_500, anchor: .top)
        _ = frames.draw(rows, atMillis: 100)
        let deep = frames.draw(rows, atMillis: 200)
        #expect(deep.contains { $0.contains("1500") }, "scrolled to row 1500: \(deep)")
        // Five rows on under an animation stated on every frame, as a
        // `.transaction` over the rows states it: five rows come into the
        // window, one a frame or so, each of them a row already. The request
        // itself may look for its row by a scan, once (a list's and a
        // table's do), on the frame that takes it; what is counted is the
        // glide's frames after it.
        box.proxy?.scrollTo(1_505, anchor: .top)
        _ = frames.draw(rows, atMillis: 300, changed: true)
        reads.reset()
        var drawn: [String] = []
        for millis in stride(from: 400, through: 1_500, by: 100) {
            drawn = frames.draw(rows, atMillis: millis, changed: true)
        }
        #expect(drawn.contains { $0.contains("1505") }, "glided to row 1505: \(drawn)")
        #expect(reads.value < 1_000, "\(reads.value) id reads over the glide, with 1,500 rows above it")
    }

    @Test("A lazy stack's row with a transition of its own plays it as it leaves", arguments: [false, true])
    func rowWithTransitionPlaysItsRemoval(scrolled: Bool) {
        let frames = Frames()
        _ = frames.draw(SlidingRows(ids: [1, 2, 3], scrolled: scrolled), atMillis: 0)
        _ = frames.draw(SlidingRows(ids: [1, 3], scrolled: scrolled), atMillis: 1000, changed: true)
        let half = frames.draw(SlidingRows(ids: [1, 3], scrolled: scrolled), atMillis: 1500)
        #expect(half.contains { $0.hasSuffix("22") && !$0.hasPrefix("2") }, "sliding out: \(half)")
        let end = frames.draw(SlidingRows(ids: [1, 3], scrolled: scrolled), atMillis: 2100)
        #expect(!end.contains { $0.contains("2") }, "gone: \(end)")
    }
}
