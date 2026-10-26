//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollGlideTests.swift
//
//  Animated programmatic scrolling (decisions B27-ANIMATING): a `scrollTo` or
//  a `ScrollPosition` request made inside `withAnimation` glides to its
//  target a whole line at a time, drawn only on the 1/60 s ticks where the
//  line changes. Frames are drawn as the run loop draws them: the change's
//  transaction and completions for the one pass that shows it, the frame
//  clock set by hand, and the next frame taken from the scheduler's wakes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

// `let _ = box.proxy = proxy` captures the proxy inside a `@ViewBuilder`
// closure, where `_ =` is not a statement the builder accepts.
// swiftlint:disable redundant_discardable_let

@MainActor
@Suite("Animated scrolling: a request made inside an animation glides")
struct ScrollGlideTests {

    private func rows(_ box: GlideProxyBox, count: Int = 40) -> some View {
        ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView {
                LazyVStack(spacing: 0) { ForEach(0..<count, id: \.self) { Text("row \($0)") } }
            }
        }
    }

    @Test("An animated scrollTo draws its start, then whole lines that never go back, then its target")
    func glidesLineByLine() throws {
        let frames = GlideFrames()
        let box = GlideProxyBox()
        let view = rows(box)
        frames.render(view)
        withAnimation(.easeInOut(duration: 0.5)) { box.proxy?.scrollTo(20, anchor: .top) }
        let start = frames.render(view)
        #expect(topRow(start) == 0, "the request's frame shows where the view stands: \(start)")
        let glide = frames.follow(view)
        let tops = glide.compactMap { topRow($0.lines) }
        #expect(tops.count == glide.count)
        #expect(tops.last == 20, "lands on its target: \(tops)")
        #expect(zip(tops, tops.dropFirst()).allSatisfy { $0 <= $1 }, "an ease never goes back: \(tops)")
        #expect(Set(tops).count > 5, "it passes through the lines between: \(tops)")
        #expect(frames.handler?.glide == nil, "landed")
        #expect(frames.nextWake == nil, "and asks for nothing more")
    }

    @Test("Frames are asked for only on 1/60 s ticks where the line changes, and the landing")
    func wakesOnLineChangingTicks() {
        let frames = GlideFrames()
        let box = GlideProxyBox()
        let view = rows(box)
        frames.render(view)
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(5, anchor: .top) }
        frames.render(view)
        let glide = frames.follow(view)
        for frame in glide {
            let tick = AnimationClock.tick(atNanoseconds: frame.nanos)
            #expect(AnimationClock.nanoseconds(atTick: tick) == frame.nanos, "on a tick: \(frame.nanos)")
        }
        // Five lines over a second: a frame for each line, and one to land.
        #expect(glide.count <= 6, "\(glide.map(\.nanos))")
        #expect(glide.compactMap { topRow($0.lines) } == [1, 2, 3, 4, 5, 5])
    }

    @Test("An unanimated scrollTo jumps, as it always has")
    func unanimatedJumps() {
        let frames = GlideFrames()
        let box = GlideProxyBox()
        let view = rows(box)
        frames.render(view)
        box.proxy?.scrollTo(20, anchor: .top)
        #expect(topRow(frames.render(view)) == 20)
        #expect(frames.handler?.glide == nil)
        #expect(frames.nextWake == nil)
    }

    @Test("Under reduce motion, or with no scheduler to draw the frames, it jumps", arguments: [true, false])
    func jumpsWithoutMotion(reduceMotion: Bool) {
        let frames = GlideFrames()
        frames.reduceMotion = reduceMotion
        frames.canAnimate = reduceMotion
        let box = GlideProxyBox()
        let view = rows(box)
        frames.render(view)
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(20, anchor: .top) }
        #expect(topRow(frames.render(view)) == 20)
        #expect(frames.handler?.glide == nil)
    }

    @Test("Its phases are idle, animating from the request's frame, and idle on the landing's, at (0, 0)")
    func reportsAnimating() {
        let frames = GlideFrames()
        let box = GlideProxyBox()
        let log = GlidePhaseLog()
        let view = rows(box).onScrollPhaseChange { old, new, context in
            log.changes.append("\(old)→\(new)")
            log.velocities.append(context.velocity)
        }
        frames.render(view)
        withAnimation(.linear(duration: 0.5)) { box.proxy?.scrollTo(20, anchor: .top) }
        frames.render(view)
        #expect(log.changes == ["idle→idle", "idle→animating"])
        let glide = frames.follow(view)
        #expect(log.changes == ["idle→idle", "idle→animating", "animating→idle"], "\(log.changes)")
        #expect(log.velocities.allSatisfy { $0 == .zero }, "as SwiftUI's, measured (B27)")
        #expect(topRow(glide.last?.lines ?? []) == 20, "idle once it has landed")
    }

    @Test("A jump — unanimated, under reduce motion, or with no scheduler — reports no phase", arguments: [0, 1, 2])
    func jumpReportsNoPhase(kind: Int) {
        let frames = GlideFrames()
        frames.reduceMotion = kind == 1
        frames.canAnimate = kind != 2
        let box = GlideProxyBox()
        let log = GlidePhaseLog()
        let view = rows(box).onScrollPhaseChange { old, new in log.changes.append("\(old)→\(new)") }
        frames.render(view)
        withAnimation(kind == 0 ? nil : .linear(duration: 0.5)) { box.proxy?.scrollTo(20, anchor: .top) }
        #expect(topRow(frames.render(view)) == 20)
        frames.follow(view)
        #expect(log.changes == ["idle→idle"], "only the first frame's report: \(log.changes)")
    }

    @Test("withAnimation's completion fires once, when the animation ends")
    func completionFiresAtTheEnd() {
        let frames = GlideFrames()
        let box = GlideProxyBox()
        let view = rows(box)
        frames.render(view)
        var fired: [Int64] = []
        withAnimation(.linear(duration: 0.5), completionCriteria: .removed) {
            box.proxy?.scrollTo(20, anchor: .top)
        } completion: {
            fired.append(frames.now)
        }
        let started = frames.now
        frames.render(view)
        #expect(fired.isEmpty, "not on the request's frame")
        frames.follow(view)
        #expect(fired.count == 1, "\(fired)")
        #expect(fired.first.map { $0 - started >= 500_000_000 } == true, "at the end: \(fired)")
    }

    @Test("A ScrollPosition row request made inside an animation glides too")
    func positionRequestGlides() {
        let frames = GlideFrames()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = ScrollView {
            LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row \($0)") } }
        }
        .scrollPosition(binding)
        frames.render(view)
        position.scrollTo(id: 20, anchor: .top)
        let start = frames.render(view, transaction: Transaction(animation: .linear(duration: 0.5)))
        #expect(topRow(start) == 0, "\(start)")
        let tops = frames.follow(view).compactMap { topRow($0.lines) }
        #expect(tops.last == 20, "\(tops)")
        #expect(tops.count > 2, "\(tops)")
    }

    @Test("A bound scrollPosition(id:) is told the row once, not at each row the glide passes")
    func idBindingWrittenOnce() {
        let frames = GlideFrames()
        var writes: [Int?] = []
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0; writes.append($0) })
        let view = ScrollView {
            LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row \($0)") } }
        }
        .scrollPosition(id: binding, anchor: .top)
        frames.render(view)
        writes.removeAll()
        visible = 20
        frames.render(view, transaction: Transaction(animation: .linear(duration: 0.5)))
        let tops = frames.follow(view).compactMap { topRow($0.lines) }
        #expect(tops.last == 20)
        #expect(writes.allSatisfy { $0 == 20 }, "only the row it lands on: \(writes)")
        #expect(writes.count <= 1, "\(writes)")
    }

    @Test("A settled view asks for no frame and declares nothing; a gliding one declares its frame volatile")
    func idleCostsNothing() {
        let frames = GlideFrames()
        let box = GlideProxyBox()
        let view = rows(box)
        frames.render(view)
        frames.render(view)
        #expect(frames.nextWake == nil)
        let settled = frames.tracker.sideEffects
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(20, anchor: .top) }
        frames.render(view)
        #expect(frames.tracker.sideEffects > settled, "the glide's frame is time-varying")
        frames.follow(view)
        frames.render(view, atNanos: frames.now + 1_000_000_000)
        #expect(frames.tracker.sideEffects == settled, "landed, it is settled again")
    }

    @Test("A lazy stack of a million rows glides with a window's rows built per frame")
    func millionRowsGlide() {
        let frames = GlideFrames()
        let box = GlideProxyBox()
        let built = GlideBuiltRows()
        let view = ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<1_000_000, id: \.self) { index in
                        let _ = built.count += 1
                        // Concatenated, not interpolated: an interpolated
                        // number is written in the locale, grouped.
                        Text("row " + String(index))
                    }
                }
            }
        }
        frames.render(view)
        withAnimation(.linear(duration: 0.5)) { box.proxy?.scrollTo(900_000, anchor: .top) }
        frames.render(view)
        var most = 0
        var tops: [Int?] = []
        while let wake = frames.nextWake, tops.count < 200 {
            built.count = 0
            let lines = frames.render(view, atNanos: wake)
            tops.append(topRow(lines))
            most = max(most, built.count)
        }
        let last = frames.render(view)
        #expect(topRow(last) == 900_000, "\(last) \(tops)")
        #expect(tops.count > 10, "it glides: \(tops)")
        #expect(most < 200, "a window's rows, not the ones passed between frames: \(most)")
    }
}

// swiftlint:enable redundant_discardable_let
