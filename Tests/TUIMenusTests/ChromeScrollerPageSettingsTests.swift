//  🖥️ TUI — A Terminal UI framework for Swift
//  ChromeScrollerPageSettingsTests.swift
//
//  A framework scroller — a tall inline menu's column — takes none of the
//  settings an app states for its own scroll views (scroll lane review 3, the
//  class of e85278da0): the declared and bound anchors, a `.scrollPosition`,
//  and the scroll observers, which it leaves for the app's scroll views.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUIMenus
@testable import TUITestSupport
@testable import TUIView

/// State a test binds and reads back.
@MainActor
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
    var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
@Suite("A framework scroller leaves the page's scroll settings to the page")
struct ChromeScrollerPageSettingsTests {

    /// A sixty-item inline menu, which scrolls inside its box in 30x14.
    private var tallMenu: some View {
        Menu("Pick") {
            ForEach(0..<60, id: \.self) { index in Button("item \(index)") {} }
        }
        .menuStyle(.inline)
    }

    /// The menu's scroller: the only scroll view on the page.
    private func menuScroller(_ frames: ScrollTargetFrames) -> ScrollViewHandler? {
        frames.scrollView
    }

    @Test("A page's defaultScrollAnchor(.bottom) does not open a menu at its last item")
    func declaredAnchorStaysThePages() {
        let frames = ScrollTargetFrames(width: 30, height: 14)
        frames.render(VStack { tallMenu }.defaultScrollAnchor(.bottom))
        let menu = menuScroller(frames)
        #expect(menu?.maxOffset ?? 0 > 0, "the menu scrolls inside its box")
        #expect(menu?.scrollOffset == 0, "it opened at the bottom")
        #expect(frames.last.lines.contains { $0.stripped.contains("item 0") })
    }

    @Test("A page's bound anchor is neither followed nor written by a menu's scroller")
    func boundAnchorStaysThePages() {
        let frames = ScrollTargetFrames(width: 30, height: 14)
        let anchor = Box<ScrollAnchor<Int>?>(.bottom)
        let view = VStack { tallMenu }.anchorPosition(anchor.binding)
        frames.render(view)
        #expect(menuScroller(frames)?.scrollOffset == 0, "it followed the page's .bottom")
        // A user scroll releases a bound anchor to `.window`, by writing it.
        frames.tui.mouseEventDispatcher.setActiveSupport(.standard)
        _ = frames.tui.mouseEventDispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 4, y: 6))
        frames.render(view)
        #expect(menuScroller(frames)?.scrollOffset ?? 0 > 0, "the wheel scrolled the menu")
        #expect(anchor.value == .bottom, "the menu released the page's anchor")
    }

    @Test("A page's scrollPosition does not move a menu's scroller")
    func scrollPositionStaysThePages() {
        let frames = ScrollTargetFrames(width: 30, height: 14)
        let position = Box(ScrollPosition())
        frames.render(VStack { tallMenu }.scrollPosition(position.binding))
        // A request, as an app makes one.
        position.value.scrollTo(y: 10)
        frames.render(VStack { tallMenu }.scrollPosition(position.binding))
        #expect(menuScroller(frames)?.scrollOffset == 0, "the menu was sought to the page's position")
    }

    @Test("A page's scroll observers hear the app's scroll view, not a menu's drawn before it")
    func observersStayThePages() {
        let frames = ScrollTargetFrames(width: 40, height: 14)
        let heard = Box<[Int]>([])
        let phases = Box<[ScrollPhase]>([])
        // The menu first, so its scroller draws before the app's.
        let view = HStack(alignment: .top) {
            tallMenu
            ScrollView { ForEach(0..<40, id: \.self) { Text("row \($0)") } }.frame(width: 10, height: 5)
        }
        .onScrollGeometryChange(
            for: Int.self, of: { $0.contentSize.height },
            action: { _, height in heard.value.append(height) })
        .onScrollPhaseChange { _, phase in phases.value.append(phase) }
        frames.render(view)
        frames.render(view)
        #expect(heard.value.last == 40, "the menu's scroller claimed the observer: \(heard.value)")
        // The app's view, scrolled by the wheel, is the one the phase is of.
        guard let row = frames.last.lines.firstIndex(where: { $0.stripped.contains("row 0") }) else {
            Issue.record("the app's scroll view is not drawn: \(frames.last.lines.map(\.stripped))")
            return
        }
        frames.tui.mouseEventDispatcher.setActiveSupport(.standard)
        let column = frames.last.lines[row].stripped.range(of: "row 0").map {
            frames.last.lines[row].stripped.distance(from: frames.last.lines[row].stripped.startIndex, to: $0.lowerBound)
        } ?? 0
        _ = frames.tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .scrollDown, phase: .scrolled, x: column, y: row))
        frames.render(view)
        #expect(phases.value.contains(.interacting), "the menu's scroller claimed the phase: \(phases.value)")
    }
}
