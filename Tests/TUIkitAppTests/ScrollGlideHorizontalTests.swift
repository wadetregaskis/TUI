//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollGlideHorizontalTests.swift
//
//  Animated programmatic scrolling along the horizontal axis (decisions
//  B27-ANIMATING, piece 4): a column `scrollTo` on a purely horizontal
//  `ScrollView`, and a `ScrollPosition`'s `x` or leading or trailing edge,
//  made inside `withAnimation`, glide a whole column at a time. Drawn with
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

/// The column a frame shows first, by its number: `c07` is 7. A column is
/// three cells and one between, so a frame part-way into one starts with
/// its tail.
private func leadingColumn(_ lines: [String]) -> Int? {
    guard let line = lines.first, line.hasPrefix("c") else { return nil }
    return Int(line.dropFirst().prefix(2))
}

@MainActor
@Suite("Animated scrolling: the horizontal axis glides too")
struct ScrollGlideHorizontalTests {

    /// Forty columns, `c00` to `c39`, column `i` starting at cell `4i`.
    private func columns(_ box: GlideProxyBox?, log: GlidePhaseLog? = nil) -> some View {
        ScrollViewReader { proxy in
            let _ = box?.proxy = proxy
            ScrollView(.horizontal) {
                LazyHStack(spacing: 1) {
                    ForEach(0..<40, id: \.self) { Text("c" + ($0 < 10 ? "0" : "") + String($0)) }
                }
            }
            .frame(width: 20, height: 2)
        }
        .onScrollPhaseChange { old, new in log?.changes.append("\(old)→\(new)") }
    }

    @Test("An animated column scrollTo draws its start, then columns that never go back, then its target")
    func columnScrollToGlides() {
        let frames = GlideFrames()
        let (box, log) = (GlideProxyBox(), GlidePhaseLog())
        let view = columns(box, log: log)
        frames.render(view)
        withAnimation(.easeInOut(duration: 0.5)) { box.proxy?.scrollTo(20, anchor: .leading) }
        let start = frames.render(view)
        #expect(leadingColumn(start) == 0, "the request's frame shows where the view stands: \(start)")
        #expect(log.changes == ["idle→idle", "idle→animating"])
        var offsets: [Int] = []
        var landed: [String] = []
        while let wake = frames.nextWake, offsets.count < 200 {
            landed = frames.render(view, atNanos: wake)
            offsets.append(frames.handler?.horizontal.scrollOffset ?? -1)
        }
        #expect(leadingColumn(landed) == 20, "lands with c20 first: \(landed)")
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $0 <= $1 }, "an ease never goes back: \(offsets)")
        #expect(Set(offsets).count > 10, "it passes through the columns between: \(offsets)")
        #expect(frames.handler?.horizontal.glide == nil, "landed")
        #expect(log.changes == ["idle→idle", "idle→animating", "animating→idle"], "\(log.changes)")
    }

    @Test("An unanimated column scrollTo still jumps")
    func unanimatedColumnJumps() {
        let frames = GlideFrames()
        let box = GlideProxyBox()
        let view = columns(box)
        frames.render(view)
        box.proxy?.scrollTo(20, anchor: .leading)
        #expect(leadingColumn(frames.render(view)) == 20)
        #expect(frames.handler?.horizontal.glide == nil)
        #expect(frames.nextWake == nil)
    }

    @Test("Under reduce motion a column scrollTo jumps")
    func reduceMotionJumps() {
        let frames = GlideFrames()
        frames.reduceMotion = true
        let box = GlideProxyBox()
        let view = columns(box)
        frames.render(view)
        withAnimation(.linear(duration: 0.5)) { box.proxy?.scrollTo(20, anchor: .leading) }
        #expect(leadingColumn(frames.render(view)) == 20)
        #expect(frames.handler?.horizontal.glide == nil)
    }

    @Test("A wheel mid-glide stops the columns where they stand")
    func wheelStopsTheColumns() throws {
        let frames = GlideFrames()
        let (box, log) = (GlideProxyBox(), GlidePhaseLog())
        let view = columns(box, log: log)
        frames.render(view)
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(30, anchor: .leading) }
        frames.render(view)
        for _ in 0..<10 {
            guard let wake = frames.nextWake else { break }
            frames.render(view, atNanos: wake)
        }
        let handler = try #require(frames.handler)
        let reached = handler.horizontal.scrollOffset
        #expect(reached > 0 && handler.horizontal.glide != nil, "under way: \(reached)")
        _ = handler.horizontal.userHorizontalStep(1)
        #expect(handler.horizontal.glide == nil, "stopped at the wheel")
        frames.render(view, atNanos: frames.now + 2_000_000_000)
        #expect(handler.horizontal.scrollOffset == reached + 1, "and nothing moves it on")
        #expect(log.changes == ["idle→idle", "idle→animating", "animating→interacting"], "\(log.changes)")
    }

    @Test("A bound position's x and its leading and trailing edges glide")
    func positionXAndEdgesGlide() {
        let frames = GlideFrames()
        var position = ScrollPosition(idType: Int.self)
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = columns(nil).scrollPosition(binding)
        let animated = Transaction(animation: .linear(duration: 0.5))
        frames.render(view)

        position.scrollTo(x: 40)
        #expect(leadingColumn(frames.render(view, transaction: animated)) == 0, "the frame shows the start")
        var steps = frames.follow(view).compactMap { _ in frames.handler?.horizontal.scrollOffset }
        #expect(steps.last == 40 && steps.count > 2, "\(steps)")

        position.scrollTo(edge: .leading)
        frames.render(view, transaction: animated)
        steps = frames.follow(view).compactMap { _ in frames.handler?.horizontal.scrollOffset }
        #expect(steps.last == 0 && steps.count > 2, "\(steps)")

        position.scrollTo(edge: .trailing)
        frames.render(view, transaction: animated)
        let landed = frames.follow(view)
        #expect(landed.count > 2)
        #expect(landed.last?.lines.first?.hasSuffix("c39") == true, "\(landed.last?.lines ?? [])")
    }

    @Test("A bound position is told the column once, on landing")
    func columnReportedOnLanding() {
        let frames = GlideFrames()
        var position = ScrollPosition(idType: Int.self)
        var writes = 0
        let binding = Binding(get: { position }, set: { position = $0; writes += 1 })
        let view = columns(nil).scrollPosition(binding)
        frames.render(view)
        frames.render(view)
        position.scrollTo(x: 80)
        writes = 0
        frames.render(view, transaction: Transaction(animation: .linear(duration: 0.5)))
        let glide = frames.follow(view)
        #expect(glide.count > 2)
        #expect(position.viewID(type: Int.self) == 20, "the column it landed on: \(glide.last?.lines ?? [])")
        #expect(writes <= 1, "not each column it passed: \(writes)")
    }

    @Test("An offset with both coordinates glides both axes, animating until both have landed")
    func bothAxesGlide() {
        let frames = GlideFrames()
        let log = GlidePhaseLog()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<40, id: \.self) { Text("row " + String($0) + String(repeating: "-", count: 60)) }
            }
        }
        .scrollPosition(binding)
        .onScrollPhaseChange { old, new in log.changes.append("\(old)→\(new)") }
        frames.render(view)
        frames.render(view)
        position.scrollTo(x: 30, y: 12)
        frames.render(view, transaction: Transaction(animation: .linear(duration: 0.5)))
        let handler = frames.handler
        #expect(handler?.glide != nil && handler?.horizontal.glide != nil, "both under way")
        frames.follow(view)
        #expect(handler?.scrollOffset == 12)
        #expect(handler?.horizontal.scrollOffset == 30)
        #expect(log.changes == ["idle→idle", "idle→animating", "animating→idle"], "\(log.changes)")
    }
}

// swiftlint:enable redundant_discardable_let
