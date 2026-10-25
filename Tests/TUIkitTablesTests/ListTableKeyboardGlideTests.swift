//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListTableKeyboardGlideTests.swift
//
//  A `List`'s and a `Table`'s page keys under `scrollKeyboardAnimation(_:)`
//  (decisions B27-ANIMATING, piece 7): Page Up/Down, Home and End move the
//  cursor at once and glide the viewport to where the cursor's reveal puts
//  it; keys pressed during the glide count from its target. Without the
//  modifier they jump as before. Drawn with `GlideFrames`; the keys are sent
//  to the handler as the dispatcher sends them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitLists
import TUIkitTables
@testable import TUIkitTestSupport
@testable import TUIkitView

/// A row of the table below.
private struct Numbered: Identifiable, Sendable {
    let id: Int
}

@MainActor
@Suite("Animated scrolling: a List's and a Table's page keys glide under scrollKeyboardAnimation")
struct ListTableKeyboardGlideTests {

    @ViewBuilder
    private func rows(table: Bool, animation: Animation?) -> some View {
        if table {
            Table((0..<200).map(Numbered.init)) {
                TableColumn("N") { (row: Numbered) in Text("item " + String(row.id)) }
            }
            .scrollKeyboardAnimation(animation)
        } else {
            List { ForEach(0..<200, id: \.self) { Text("row " + String($0)) } }
                .scrollKeyboardAnimation(animation)
        }
    }

    private func listHandler(_ frames: GlideFrames) -> ItemListHandler<Int>? {
        frames.focusManager.activeSection?.focusables.compactMap { $0 as? ItemListHandler<Int> }.first
    }

    private func press(_ key: Key, _ frames: GlideFrames) {
        _ = listHandler(frames)?.handleKeyEvent(KeyEvent(key: key))
    }

    /// Where the same keys put the viewport and the cursor when they jump.
    private func jumped(_ keys: [Key], table: Bool) -> (offset: Int, cursor: Int)? {
        let frames = GlideFrames()
        let view = rows(table: table, animation: nil)
        frames.render(view)
        for key in keys {
            press(key, frames)
            frames.render(view)
        }
        return listHandler(frames).map { ($0.scrollOffset, $0.focusedIndex) }
    }

    @Test("Without the modifier the page keys jump, as they always have", arguments: [false, true])
    func jumpByDefault(table: Bool) throws {
        let frames = GlideFrames()
        let view = rows(table: table, animation: nil)
        frames.render(view)
        press(.pageDown, frames)
        let handler = try #require(listHandler(frames))
        #expect(handler.glide == nil)
        frames.render(view)
        #expect(handler.glide == nil)
        #expect(handler.scrollOffset > 0, "it moved")
    }

    @Test("Page Down moves the cursor at once and glides the viewport to where the jump puts it", arguments: [false, true])
    func pageDownGlides(table: Bool) throws {
        let frames = GlideFrames()
        let view = rows(table: table, animation: .linear(duration: 0.25))
        frames.render(view)
        let handler = try #require(listHandler(frames))
        // The first press takes the cursor to the foot of the viewport, which
        // moves it a row; the second pages it.
        press(.pageDown, frames)
        frames.render(view)
        frames.follow(view)
        let before = handler.scrollOffset
        let target = try #require(jumped([.pageDown, .pageDown], table: table))
        press(.pageDown, frames)
        #expect(handler.focusedIndex == target.cursor, "the cursor moves at once")
        #expect(handler.scrollOffset == before, "the viewport is put back where it is drawn")
        frames.render(view, atNanos: frames.now + 1)
        var offsets: [Int] = []
        while let wake = frames.nextWake, offsets.count < 100 {
            frames.render(view, atNanos: wake)
            offsets.append(handler.scrollOffset)
        }
        #expect(offsets.last == target.offset, "lands where the jump does: \(offsets)")
        #expect(Set(offsets).count > 1 && zip(offsets, offsets.dropFirst()).allSatisfy { $0 <= $1 }, "\(offsets)")
        #expect(handler.focusedIndex == target.cursor)
    }

    @Test("Three presses during the glide land exactly where three jumps do", arguments: [false, true])
    func threePresses(table: Bool) throws {
        let frames = GlideFrames()
        let view = rows(table: table, animation: .linear(duration: 0.5))
        frames.render(view)
        let handler = try #require(listHandler(frames))
        press(.pageDown, frames)
        frames.render(view)
        for _ in 0..<2 { if let wake = frames.nextWake { frames.render(view, atNanos: wake) } }
        press(.pageDown, frames)
        frames.render(view, atNanos: frames.now + 1)
        press(.pageDown, frames)
        frames.follow(view)
        let target = try #require(jumped([.pageDown, .pageDown, .pageDown], table: table))
        #expect(handler.scrollOffset == target.offset, "\(handler.scrollOffset) vs \(target)")
        #expect(handler.focusedIndex == target.cursor)
    }

    @Test("Down during the glide lands the page first, then moves the cursor")
    func arrowLandsFirst() throws {
        let frames = GlideFrames()
        let view = rows(table: false, animation: .linear(duration: 0.5))
        frames.render(view)
        let handler = try #require(listHandler(frames))
        press(.pageDown, frames)
        frames.render(view)
        if let wake = frames.nextWake { frames.render(view, atNanos: wake) }
        #expect(handler.glide != nil, "under way")
        press(.down, frames)
        #expect(handler.glide == nil)
        let target = try #require(jumped([.pageDown, .down], table: false))
        #expect((handler.scrollOffset, handler.focusedIndex) == target, "as the jumps go")
    }

    @Test("End glides a Table to its last row; Home glides it back")
    func endAndHome() throws {
        let frames = GlideFrames()
        let view = rows(table: true, animation: .linear(duration: 0.5))
        frames.render(view)
        let handler = try #require(listHandler(frames))
        press(.end, frames)
        frames.render(view)
        let down = frames.follow(view)
        #expect(down.count > 2)
        #expect(down.last?.lines.contains { $0.contains("item 199") } == true, "\(down.last?.lines ?? [])")
        press(.home, frames)
        frames.render(view)
        let up = frames.follow(view)
        #expect(up.count > 2)
        #expect(handler.scrollOffset == 0 && handler.focusedIndex == 0)
    }

    @Test("Under reduce motion the page keys jump")
    func reduceMotionJumps() throws {
        let frames = GlideFrames()
        frames.reduceMotion = true
        let view = rows(table: false, animation: .linear(duration: 0.5))
        frames.render(view)
        press(.pageDown, frames)
        let handler = try #require(listHandler(frames))
        #expect(handler.glide == nil)
        #expect(handler.scrollOffset > 0)
    }
}
