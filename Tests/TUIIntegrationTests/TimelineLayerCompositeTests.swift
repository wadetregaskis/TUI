//  🖥️ TUI — A Terminal UI framework for Swift
//  TimelineLayerCompositeTests.swift
//
//  An `.overlay` or a `.background` that holds a running `TimelineView` does
//  not composite its two layers again at the timeline's entries when neither
//  changed: the composite is served from the last frame's
//  (`LayerCompositeKeep`). Nor does a `ZStack` of a picture and a timeline
//  beside it, as a launcher's preview is drawn. And when a layer changes, the
//  new composite is drawn: a layer whose content moves, a base whose model does.
//
//  Counted, not compared: a picture served and one composited again look the
//  same. `composited` is the composites made while a timeline was live.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Observation
import Testing
import TUI
import TUITesting
import TUIView

/// What the canvas below counts. A global, not a capture, so no view holds
/// anything that would make it compare unequal.
@MainActor private var boardRenders = 0

/// A 60 Hz timeline whose content reads its date and draws nothing, as a
/// game loop's does.
private struct Loop: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Color.clear.onChange(of: timeline.date) { _, _ in }
        }
    }
}

/// A canvas that reads nothing and never changes: dear to composite, since
/// every cell names a colour.
private struct Board: View, Equatable {
    var body: some View {
        Canvas { context, size in
            MainActor.assumeIsolated { boardRenders += 1 }
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)), with: .color(.red))
            context.fill(
                Path(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height)), with: .color(.blue))
        }
    }
}

/// Which page a test draws.
private enum Shape {
    case background
    case overlay
    /// The timeline the base, the board in its background.
    case timelineAsBase
    /// The board and the timeline as a `ZStack`'s two layers.
    case zstack
}

private struct Host: View {
    let shape: Shape

    var body: some View {
        switch shape {
        case .background: Board().equatable().frame(width: 10, height: 3).background { Loop() }
        case .overlay: Board().equatable().frame(width: 10, height: 3).overlay { Loop() }
        case .timelineAsBase: Loop().frame(width: 10, height: 3).background { Board().equatable() }
        case .zstack:
            ZStack(alignment: .topLeading) {
                Board().equatable().frame(width: 10, height: 3)
                Loop().frame(width: 0, height: 0)
            }
        }
    }
}

/// A layer that moves at every entry: red, then blue, then red.
private struct Blinking: View {
    var body: some View {
        Text(verbatim: "ab").frame(width: 4, height: 1)
            .background {
                TimelineView(.animation) { timeline in
                    Int(timeline.date.timeIntervalSinceReferenceDate * 60).isMultiple(of: 2) ? Color.red : Color.blue
                }
            }
    }
}

@MainActor
@Observable
private final class Label {
    var text = "one"
}

/// A `ZStack` whose top layer moves at every entry, over a text.
private struct BlinkingStack: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(verbatim: "ab").frame(width: 4, height: 1)
            TimelineView(.animation) { timeline in
                Text(verbatim: Int(timeline.date.timeIntervalSinceReferenceDate * 60).isMultiple(of: 2) ? "x" : "y")
            }
        }
    }
}

/// A `ZStack` of a text drawn from a model, with the timeline beside it.
private struct LabelledStack: View {
    let label: Label

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(verbatim: label.text).frame(width: 6, height: 1)
            Loop().frame(width: 0, height: 0)
        }
    }
}

/// A base drawn from a model, with the timeline behind it.
private struct Labelled: View {
    let label: Label

    var body: some View {
        Text(verbatim: label.text).frame(width: 6, height: 1).background { Loop() }
    }
}

@MainActor
@Suite("A layer modifier around a running timeline composites only what changed", .serialized)
struct TimelineLayerCompositeTests {
    /// A settled page: its first frames drawn, and those in which the walk
    /// learns where the live timelines are.
    private func page(_ shape: Shape) -> TestApp {
        let app = TestApp(width: 20, height: 3) { Host(shape: shape) }
        _ = app.screen
        app.advance(by: .milliseconds(100))
        return app
    }

    @Test("The view a timeline is drawn behind is not composited over it again at each entry")
    func backgroundCompositeServed() {
        let app = page(.background)
        let counts = app.headless.renderCache.plainMemo.layerComposites.counts
        let screen = app.headless.screen
        app.advance(by: .seconds(1))
        let after = app.headless.renderCache.plainMemo.layerComposites.counts
        #expect(after.composited == counts.composited, "60 entries; nothing either layer draws moved")
        #expect(after.served - counts.served >= 55)
        #expect(app.headless.screen == screen)
    }

    @Test("The timeline a view is drawn over is not composited under it again at each entry")
    func overlayCompositeServed() {
        let app = page(.overlay)
        let counts = app.headless.renderCache.plainMemo.layerComposites.counts
        app.advance(by: .seconds(1))
        let after = app.headless.renderCache.plainMemo.layerComposites.counts
        #expect(after.composited == counts.composited)
        #expect(after.served - counts.served >= 55)
    }

    @Test("A timeline as the base of a background draws its background once, and composites it once")
    func timelineAsBase() {
        boardRenders = 0
        let app = page(.timelineAsBase)
        let renders = boardRenders
        #expect(renders >= 1)
        let counts = app.headless.renderCache.plainMemo.layerComposites.counts
        app.advance(by: .seconds(1))
        #expect(boardRenders == renders, "the board in the background reads nothing that moved")
        #expect(app.headless.renderCache.plainMemo.layerComposites.counts.composited == counts.composited)
    }

    @Test("A ZStack of a picture and a timeline is not composited again at each entry")
    func zstackCompositeServed() {
        boardRenders = 0
        let app = page(.zstack)
        let renders = boardRenders
        let counts = app.headless.renderCache.plainMemo.layerComposites.counts
        let screen = app.headless.screen
        app.advance(by: .seconds(1))
        let after = app.headless.renderCache.plainMemo.layerComposites.counts
        #expect(after.composited == counts.composited, "60 entries; no layer moved")
        #expect(after.served - counts.served >= 55)
        #expect(boardRenders == renders)
        #expect(app.headless.screen == screen)
    }

    @Test("A ZStack layer that moves at every entry is composited at every entry")
    func movingStackLayerComposited() {
        let app = TestApp(width: 8, height: 1) { BlinkingStack() }
        _ = app.screen
        app.advance(by: .milliseconds(100))
        var seen: Set<String> = []
        for _ in 0..<6 {
            app.advance(by: .microseconds(16_667))
            seen.insert(app.screen.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        #expect(seen == ["xb", "yb"], "the top layer in turn over the text: \(seen)")
    }

    @Test("A ZStack layer that changes beside a running timeline is drawn changed")
    func changedStackLayerComposited() {
        let label = Label()
        let app = TestApp(width: 8, height: 1) { LabelledStack(label: label) }
        _ = app.screen
        app.advance(by: .milliseconds(200))
        #expect(app.headless.screen.joined().contains("one"))
        label.text = "two"
        app.advance(by: .milliseconds(50))
        #expect(app.headless.screen.joined().contains("two"))
        label.text = "one"
        app.advance(by: .milliseconds(50))
        #expect(app.headless.screen.joined().contains("one"), "the first composite is kept no longer than its layer")
    }

    @Test("A layer that moves at every entry is composited at every entry")
    func movingLayerComposited() {
        let app = TestApp(width: 8, height: 1) { Blinking() }
        _ = app.screen
        app.advance(by: .milliseconds(100))
        var seen: Set<String> = []
        for _ in 0..<6 {
            app.advance(by: .microseconds(16_667))
            seen.insert(app.headless.screen.joined(separator: "\n"))
        }
        #expect(seen.count == 2, "red and blue in turn: \(seen.count) pictures")
        #expect(seen.allSatisfy { $0.contains("ab") })
    }

    @Test("A base that changes under a running timeline is drawn changed")
    func changedBaseComposited() {
        let label = Label()
        let app = TestApp(width: 8, height: 1) { Labelled(label: label) }
        _ = app.screen
        app.advance(by: .milliseconds(200))
        #expect(app.headless.screen.joined().contains("one"))
        label.text = "two"
        app.advance(by: .milliseconds(50))
        #expect(app.headless.screen.joined().contains("two"))
        label.text = "one"
        app.advance(by: .milliseconds(50))
        #expect(app.headless.screen.joined().contains("one"), "the first composite is kept no longer than its base")
    }
}
