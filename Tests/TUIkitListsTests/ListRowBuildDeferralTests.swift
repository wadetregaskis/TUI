//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowBuildDeferralTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
import TUIkitLists
@testable import TUIkitTestSupport

/// Pins the List row pipeline's steady-state cost model: once a row's buffer
/// is in the render cache, a later frame must serve it WITHOUT invoking the
/// `ForEach` content closure at all. The closure is the app's row builder —
/// views, string interpolation, localization lookups — and running it per
/// visible row per frame just to discard the result against a cache hit was
/// measured at a fifth of a `List` frame. The badge peek is the subtlety: it
/// needs a BUILT view, so only a row whose static type can carry a badge
/// (`.badge(_:)` outermost) may still build for it.
@MainActor
@Suite("List row build deferral")
struct ListRowBuildDeferralTests {

    private func context(width: Int = 40, height: Int = 12) -> RenderContext {
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        return RenderContext(
            availableWidth: width,
            availableHeight: height,
            environment: environment,
            tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    @Test("A steady-state frame builds no row views")
    func steadyStateBuildsNothing() {
        // A class box, not @State: the builder must observe mutation across
        // renders without invalidating the rows (which would defeat the memo
        // this test measures).
        final class Counter { var builds = 0 }
        let counter = Counter()
        func makeRow(_ i: Int) -> Text {
            counter.builds += 1
            return Text("row \(i)")
        }

        let view = List {
            ForEach(0..<50, id: \.self) { makeRow($0) }
        }
        let renderContext = context()
        _ = renderToBuffer(view, context: renderContext)
        #expect(counter.builds > 0, "frame 1 must build the visible rows")
        // Frame 2 lays the rows out again, a cell narrower: frame 1 cannot know
        // the list overflows — and so draws a bar, which its rows keep a cell
        // clear of (`View.scrollbarSpacing(_:)`) — before its rows are laid out.
        _ = renderToBuffer(view, context: renderContext)
        let firstFrameBuilds = counter.builds

        let warm = renderToBuffer(view, context: renderContext)
        let secondFrameBuilds = counter.builds - firstFrameBuilds
        // The rows that DREW are the ones that could hit, and under the memo
        // verifier each hit costs one build (see `verifierRenders(hits:)`).
        // Counted off the frame rather than written down, because the visible
        // window is a function of the List's chrome and is not what this pins.
        let servedRows = warm.lines.filter { $0.stripped.contains("row ") }.count
        #expect(
            secondFrameBuilds == verifierRenders(hits: servedRows),
            "a warm frame built \(secondFrameBuilds) row views for \(servedRows) visible rows, then discarded them against its cache hits")
    }

    /// A `ForEach` beside a hand-written row reaches the list's child walk
    /// inside its value memo, and the type-select text a looped row states
    /// sits behind that memo. Reading it means building the row, which the
    /// list did for every such row on every frame, as the walk attached each
    /// row's probe; it is built when the probe is asked — when the user types.
    @Test("A spliced looped row's type-select text builds nothing on a steady-state frame")
    func splicedTypeSelectEquivalentBuildsNothing() {
        final class Counter { var builds = 0 }
        let counter = Counter()
        func makeRow(_ i: Int) -> some View {
            counter.builds += 1
            return Text("• \(i)").typeSelectEquivalent("row \(i)")
        }

        let view = List {
            Text("Top")
            ForEach(0..<8, id: \.self) { makeRow($0) }
        }
        let renderContext = context()
        _ = renderToBuffer(view, context: renderContext)
        _ = renderToBuffer(view, context: renderContext)
        let settledBuilds = counter.builds

        let warm = renderToBuffer(view, context: renderContext)
        let warmBuilds = counter.builds - settledBuilds
        let servedRows = warm.lines.filter { $0.stripped.contains("• ") }.count
        #expect(servedRows == 8, "every looped row drawn: \(warm.lines.map(\.stripped))")
        #expect(
            warmBuilds == verifierRenders(hits: servedRows),
            "a warm frame built \(warmBuilds) looped rows for \(servedRows) served ones, to read their type-select text")
    }

    @Test("A badged row still renders its badge through the deferral")
    func badgedRowsKeepTheirBadges() {
        let view = List {
            ForEach(0..<20, id: \.self) { i in
                Text("row \(i)").badge(777)
            }
        }
        let renderContext = context()
        _ = renderToBuffer(view, context: renderContext)
        let second = renderToBuffer(view, context: renderContext)
        let joined = second.lines.map(\.stripped).joined(separator: "\n")
        #expect(joined.contains("777"), "badge value renders on a warm frame: \(joined)")
    }
}
