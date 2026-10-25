//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollKeyboardGlideTests.swift
//
//  `scrollKeyboardAnimation(_:)` (decisions B27-ANIMATING, piece 5): under
//  it a `ScrollView`'s Page Up/Down and Home/End glide to where they land,
//  the scroll target behaviour picking the landing first; keys pressed during
//  a glide count from its target; without it every key jumps. Drawn with
//  `ScrollGlideTests`' frames; the keys are sent to the handler as the
//  dispatcher sends them.
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

/// Rows the tests append to while a glide runs.
@MainActor
private final class KeyGlideRows {
    var count: Int
    init(count: Int) { self.count = count }
}

@MainActor
@Suite("Animated scrolling: keys glide under scrollKeyboardAnimation")
struct ScrollKeyboardGlideTests {

    /// Forty rows in a six-line viewport, paged when `paging`, the keys
    /// gliding along `animation` when it is set.
    @ViewBuilder
    private func rows(
        _ data: KeyGlideRows = KeyGlideRows(count: 40), paging: Bool = false, animation: Animation? = nil,
        log: GlidePhaseLog? = nil
    ) -> some View {
        let view = ScrollView {
            LazyVStack(spacing: 0) {
                // Concatenated, not interpolated: an interpolated number is
                // written in the locale, grouped.
                ForEach(0..<data.count, id: \.self) { Text("row " + String($0)) }
            }
        }
        if paging {
            view.scrollTargetBehavior(.paging).scrollKeyboardAnimation(animation)
                .onScrollPhaseChange { old, new in log?.changes.append("\(old)→\(new)") }
        } else {
            view.scrollKeyboardAnimation(animation)
                .onScrollPhaseChange { old, new in log?.changes.append("\(old)→\(new)") }
        }
    }

    /// Sends `key` to the drawn scroll view's handler.
    private func press(_ key: Key, _ frames: GlideFrames) {
        _ = frames.handler?.handleKeyEvent(KeyEvent(key: key))
    }

    /// Where the same keys put the same view when they jump.
    private func jumpedOffset(_ keys: [Key], from start: [Key] = [], paging: Bool) -> Int? {
        let frames = GlideFrames()
        let view = rows(paging: paging)
        frames.render(view)
        for key in start + keys {
            press(key, frames)
            frames.render(view)
        }
        return frames.handler?.scrollOffset
    }

    @Test("Without the modifier, Page Down, End and Home jump as they always have")
    func keysJumpByDefault() {
        let frames = GlideFrames()
        let view = rows()
        frames.render(view)
        for key in [Key.pageDown, .end, .home] {
            press(key, frames)
            #expect(frames.handler?.glide == nil, "\(key) jumps")
            frames.render(view)
            #expect(frames.handler?.glide == nil, "and starts no glide after \(key)")
        }
        #expect(frames.handler?.scrollOffset == 0)
    }

    @Test("A .paging view's Page Down glides a line at a time to the page boundary the jump lands on")
    func pageDownGlidesToTheBoundary() throws {
        let frames = GlideFrames()
        let view = rows(paging: true, animation: .linear(duration: 0.25))
        frames.render(view)
        // Off a boundary first: an arrow, which jumps.
        press(.down, frames)
        press(.down, frames)
        frames.render(view)
        let before = try #require(frames.handler?.scrollOffset)
        press(.pageDown, frames)
        #expect(frames.handler?.scrollOffset == before, "the key puts the offset back where it is drawn")
        #expect(topRow(frames.render(view)) == before, "the frame after the key draws the start")
        let tops = frames.follow(view).compactMap { topRow($0.lines) }
        let target = try #require(jumpedOffset([.pageDown], from: [.down, .down], paging: true))
        #expect(tops.last == target, "lands where the jump does: \(tops)")
        #expect(target.isMultiple(of: 6) || target == 34, "on a page boundary: \(target)")
        #expect(tops.count > 2 && zip(tops, tops.dropFirst()).allSatisfy { $0 <= $1 }, "through the lines between: \(tops)")
    }

    @Test("Three presses during the glide land exactly three pages down")
    func threePressesThreePages() throws {
        let frames = GlideFrames()
        let view = rows(paging: true, animation: .linear(duration: 0.5))
        frames.render(view)
        press(.pageDown, frames)
        frames.render(view)
        for _ in 0..<3 { if let wake = frames.nextWake { frames.render(view, atNanos: wake) } }
        press(.pageDown, frames)
        frames.render(view, atNanos: frames.now + 1)
        if let wake = frames.nextWake { frames.render(view, atNanos: wake) }
        press(.pageDown, frames)
        let tops = frames.follow(view).compactMap { topRow($0.lines) }
        let target = try #require(jumpedOffset([.pageDown, .pageDown, .pageDown], paging: true))
        #expect(target == 18, "precondition: three pages of six: \(target)")
        #expect(tops.last == target, "\(tops)")
        #expect(zip(tops, tops.dropFirst()).allSatisfy { $0 <= $1 }, "never back: \(tops)")
    }

    @Test("Down during the glide lands the page, then steps a line")
    func arrowLandsThenSteps() throws {
        let frames = GlideFrames()
        let view = rows(paging: true, animation: .linear(duration: 0.5))
        frames.render(view)
        press(.pageDown, frames)
        frames.render(view)
        if let wake = frames.nextWake { frames.render(view, atNanos: wake) }
        #expect(frames.handler?.glide != nil, "under way")
        press(.down, frames)
        #expect(frames.handler?.glide == nil, "landed by the arrow")
        let stepped = try #require(jumpedOffset([.pageDown, .down], paging: true))
        #expect(frames.handler?.scrollOffset == stepped, "a page and a line, as the jumps go")
        frames.render(view, atNanos: frames.now + 1_000_000_000)
        #expect(frames.handler?.scrollOffset == stepped, "and nothing glides on")
    }

    @Test("End glides to the tail, through the tail seek: rows that arrive while it glides are followed")
    func endGlidesToTheTail() {
        let frames = GlideFrames()
        let data = KeyGlideRows(count: 40)
        frames.render(rows(data, animation: .linear(duration: 0.5)))
        press(.end, frames)
        #expect(topRow(frames.render(rows(data, animation: .linear(duration: 0.5)))) == 0, "draws the start")
        data.count = 45
        let landed = frames.follow(rows(data, animation: .linear(duration: 0.5)))
        #expect(landed.count > 2)
        #expect(landed.last?.lines.last == "row 44", "\(landed.last?.lines ?? [])")
        press(.home, frames)
        frames.render(rows(data, animation: .linear(duration: 0.5)))
        let home = frames.follow(rows(data, animation: .linear(duration: 0.5))).compactMap { topRow($0.lines) }
        #expect(home.last == 0 && home.count > 2, "Home glides back up: \(home)")
    }

    @Test("A key's glide is interacting throughout, and idle a quarter of a second after it lands")
    func phaseStaysInteracting() throws {
        let frames = GlideFrames()
        let log = GlidePhaseLog()
        let view = rows(animation: .linear(duration: 0.5), log: log)
        frames.render(view)
        let handler = try #require(frames.handler)
        handler.phaseNow = { UInt64(frames.now) }
        press(.pageDown, frames)
        frames.render(view)
        var glided = 0
        while handler.glide != nil, let wake = frames.nextWake, glided < 100 {
            frames.render(view, atNanos: wake)
            glided += 1
        }
        #expect(glided > 2)
        #expect(log.changes == ["idle→idle", "idle→interacting"], "never animating, still interacting: \(log.changes)")
        let landing = frames.now
        frames.render(view, atNanos: landing + Int64(ScrollPhase.quietNanos) - 1)
        #expect(log.changes.last == "idle→interacting", "the quiet is counted from the landing")
        frames.render(view, atNanos: landing + Int64(ScrollPhase.quietNanos))
        #expect(log.changes.last == "interacting→idle", "\(log.changes)")
    }

    @Test("Under reduce motion the keys jump")
    func reduceMotionJumps() {
        let frames = GlideFrames()
        frames.reduceMotion = true
        let view = rows(animation: .linear(duration: 0.5))
        frames.render(view)
        press(.pageDown, frames)
        #expect(frames.handler?.glide == nil)
        #expect(topRow(frames.render(view)) == 6)
        #expect(frames.handler?.glide == nil)
    }

    @Test("The wheel during a key's glide stops it where it stands")
    func wheelStopsAKeyGlide() throws {
        let frames = GlideFrames()
        let view = rows(animation: .linear(duration: 1))
        frames.render(view)
        press(.end, frames)
        frames.render(view)
        for _ in 0..<5 { if let wake = frames.nextWake { frames.render(view, atNanos: wake) } }
        let handler = try #require(frames.handler)
        let reached = handler.scrollOffset
        #expect(reached > 0 && reached < handler.maxOffset, "under way: \(reached)")
        handler.userScrollFine(by: 3)
        #expect(handler.glide == nil)
        frames.render(view, atNanos: frames.now + 2_000_000_000)
        #expect(handler.scrollOffset == reached + 3, "from where it stood, and no further")
    }
}
