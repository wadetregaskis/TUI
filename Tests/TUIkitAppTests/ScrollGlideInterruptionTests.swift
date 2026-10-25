//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollGlideInterruptionTests.swift
//
//  What happens to a programmatic glide (decisions B27-ANIMATING) when
//  something else moves the view while it runs: the user's scroll stops it,
//  a second request retargets or cancels it, rows that arrive move its
//  destination or are corrected by its landing, a resize lands it at once, and
//  a bound position's edges and offsets glide too. Drawn with
//  `ScrollGlideTests`' frames.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

// `let _ = box.proxy = proxy` captures the proxy inside a `@ViewBuilder`
// closure, where `_ =` is not a statement the builder accepts.
// swiftlint:disable redundant_discardable_let

/// Rows the tests insert into while a glide runs, by id.
@MainActor
private final class GlideRows {
    var ids: [Int]
    init(count: Int) { ids = Array(0..<count) }
}

@MainActor
@Suite("Animated scrolling: interruptions, retargets and landings")
struct ScrollGlideInterruptionTests {

    private func rows(_ box: GlideProxyBox, _ data: GlideRows, log: GlidePhaseLog? = nil) -> some View {
        ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Concatenated, not interpolated: an interpolated number
                    // is written in the locale, grouped.
                    ForEach(data.ids, id: \.self) { Text("row " + String($0)) }
                }
            }
        }
        .onScrollPhaseChange { old, new in log?.changes.append("\(old)→\(new)") }
    }

    /// Draws the frames the glide asks for until its top row is past `row`
    /// (or has stopped), and returns that row.
    private func glide<V: View>(_ frames: GlideFrames, _ view: V, until row: Int) -> Int? {
        var top: Int?
        while let wake = frames.nextWake, (top ?? 0) < row {
            top = topRow(frames.render(view, atNanos: wake))
        }
        return top
    }

    @Test("A wheel mid-glide stops it where it stands: animating goes straight to interacting")
    func wheelStopsTheGlide() throws {
        let frames = GlideFrames()
        let (box, data, log) = (GlideProxyBox(), GlideRows(count: 40), GlidePhaseLog())
        let view = rows(box, data, log: log)
        frames.render(view)
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(30, anchor: .top) }
        frames.render(view)
        let reached = try #require(glide(frames, view, until: 5))
        frames.handler?.userScrollFine(by: 3)
        #expect(frames.handler?.glide == nil, "stopped at the wheel")
        let after = frames.render(view, atNanos: frames.now + 16_666_667)
        #expect(topRow(after) == reached + 3, "the wheel acts from where the glide was drawn: \(after)")
        #expect(log.changes == ["idle→idle", "idle→animating", "animating→interacting"], "\(log.changes)")
        let later = frames.render(view, atNanos: frames.now + 2_000_000_000)
        #expect(topRow(later) == reached + 3, "and nothing moves it on")
    }

    @Test("A second animated scrollTo mid-glide glides on from the line the first was drawn on")
    func secondRequestRetargets() throws {
        let frames = GlideFrames()
        let (box, data, log) = (GlideProxyBox(), GlideRows(count: 40), GlidePhaseLog())
        let view = rows(box, data, log: log)
        frames.render(view)
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(30, anchor: .top) }
        frames.render(view)
        let reached = try #require(glide(frames, view, until: 10))
        withAnimation(.linear(duration: 0.5)) { box.proxy?.scrollTo(2, anchor: .top) }
        let start = frames.render(view, atNanos: frames.now + 1)
        #expect(topRow(start).map { abs($0 - reached) <= 1 } == true, "from where it was: \(start) vs \(reached)")
        let tops = frames.follow(view).compactMap { topRow($0.lines) }
        #expect(tops.last == 2, "\(tops)")
        #expect(zip(tops, tops.dropFirst()).allSatisfy { $0 >= $1 }, "straight back up: \(tops)")
        #expect(log.changes == ["idle→idle", "idle→animating", "animating→idle"], "one animation: \(log.changes)")
    }

    @Test("An unanimated scrollTo mid-glide cancels it and jumps")
    func unanimatedRequestCancels() throws {
        let frames = GlideFrames()
        let (box, data, log) = (GlideProxyBox(), GlideRows(count: 40), GlidePhaseLog())
        let view = rows(box, data, log: log)
        frames.render(view)
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(30, anchor: .top) }
        frames.render(view)
        _ = try #require(glide(frames, view, until: 5))
        box.proxy?.scrollTo(12, anchor: .top)
        #expect(topRow(frames.render(view, atNanos: frames.now + 1)) == 12)
        #expect(frames.handler?.glide == nil)
        #expect(log.changes.last == "animating→idle", "\(log.changes)")
        #expect(topRow(frames.render(view, atNanos: frames.now + 2_000_000_000)) == 12, "nothing glides on")
    }

    @Test("Rows inserted above mid-glide move the destination with them")
    func insertionAboveStillLands() throws {
        let frames = GlideFrames()
        let (box, data) = (GlideProxyBox(), GlideRows(count: 40))
        frames.render(rows(box, data))
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(30, anchor: .top) }
        frames.render(rows(box, data))
        _ = try #require(glide(frames, rows(box, data), until: 5))
        data.ids.insert(contentsOf: 1000..<1005, at: 0)
        let tops = frames.follow(rows(box, data)).compactMap { topRow($0.lines) }
        #expect(tops.last == 30, "lands on the row it was sent to: \(tops)")
    }

    @Test("Rows inserted between the viewport and the row mid-glide are corrected by the landing")
    func insertionBetweenIsReSought() throws {
        let frames = GlideFrames()
        let (box, data) = (GlideProxyBox(), GlideRows(count: 40))
        frames.render(rows(box, data))
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(30, anchor: .top) }
        frames.render(rows(box, data))
        _ = try #require(glide(frames, rows(box, data), until: 5))
        data.ids.insert(contentsOf: 1000..<1005, at: 20)
        let tops = frames.follow(rows(box, data)).compactMap { topRow($0.lines) }
        #expect(tops.last == 30, "the re-seek on landing finds the row again: \(tops)")
    }

    @Test("A resize mid-glide lands it at its target at once")
    func resizeLands() throws {
        let frames = GlideFrames()
        let (box, data, log) = (GlideProxyBox(), GlideRows(count: 40), GlidePhaseLog())
        let view = rows(box, data, log: log)
        frames.render(view)
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(30, anchor: .top) }
        frames.render(view)
        _ = try #require(glide(frames, view, until: 5))
        let resized = frames.render(view, atNanos: frames.now + 1, height: 8)
        #expect(topRow(resized) == 30, "\(resized)")
        #expect(frames.handler?.glide == nil)
        #expect(log.changes.last == "animating→idle")
    }

    @Test("A bound position's edge and offset requests made inside an animation glide too")
    func edgesAndOffsetsGlide() {
        let frames = GlideFrames()
        let data = GlideRows(count: 40)
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        func view() -> some View {
            ScrollView {
                LazyVStack(spacing: 0) { ForEach(data.ids, id: \.self) { Text("row " + String($0)) } }
            }
            .scrollPosition(binding)
        }
        let animated = Transaction(animation: .linear(duration: 0.5))
        frames.render(view())

        position.scrollTo(y: 15)
        #expect(topRow(frames.render(view(), transaction: animated)) == 0, "the offset's frame shows the start")
        var tops = frames.follow(view()).compactMap { topRow($0.lines) }
        #expect(tops.last == 15 && tops.count > 2, "\(tops)")

        position.scrollTo(edge: .top)
        #expect(topRow(frames.render(view(), transaction: animated)) == 15)
        tops = frames.follow(view()).compactMap { topRow($0.lines) }
        #expect(tops.last == 0 && tops.count > 2, "\(tops)")

        // The bottom edge lands through the tail seek, so rows that arrive
        // while it glides are at the tail it lands on.
        position.scrollTo(edge: .bottom)
        frames.render(view(), transaction: animated)
        data.ids.append(contentsOf: 40..<50)
        let landed = frames.follow(view())
        #expect(landed.last?.lines.last == "row 49", "\(landed.last?.lines ?? [])")
    }

    @Test("A written anchor edge made inside an animation glides to it")
    func writtenAnchorGlides() {
        let frames = GlideFrames()
        var anchor: ScrollAnchor<AnyHashable>?
        let binding = Binding(get: { anchor }, set: { anchor = $0 })
        let view = ScrollView {
            LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row " + String($0)) } }
        }
        .anchorPosition(binding)
        frames.render(view)
        frames.render(view)
        anchor = .bottom
        #expect(topRow(frames.render(view, transaction: Transaction(animation: .linear(duration: 0.5)))) == 0)
        let landed = frames.follow(view)
        #expect(landed.count > 2)
        #expect(landed.last?.lines.last == "row 39", "\(landed.last?.lines ?? [])")
    }

    @Test("Moving the focus mid-glide stops it where the reveal puts the view")
    func focusMoveStopsTheGlide() throws {
        let frames = GlideFrames()
        let box = GlideProxyBox()
        let view = ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<40, id: \.self) { index in
                        Button("b" + String(index)) {}.focusID("b" + String(index))
                    }
                }
            }
        }
        frames.render(view)
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(30, anchor: .top) }
        frames.render(view)
        for _ in 0..<10 {
            guard let wake = frames.nextWake else { break }
            frames.render(view, atNanos: wake)
        }
        let handler = try #require(frames.handler)
        #expect(handler.glide != nil, "still gliding")
        // The first button has held the focus from the start; this moves it.
        frames.focusManager.focus(id: "b3")
        frames.render(view, atNanos: frames.now + 1)
        #expect(handler.glide == nil, "the reveal stopped it")
        let revealed = handler.scrollOffset
        #expect(revealed <= 3, "where the reveal put it, showing b3: \(revealed)")
        frames.render(view, atNanos: frames.now + 2_000_000_000)
        #expect(handler.scrollOffset == revealed, "and nothing glides on")
    }
}

// swiftlint:enable redundant_discardable_let
