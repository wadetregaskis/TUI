//  🖥️ TUI — A Terminal UI framework for Swift
//  PaddingScrollWindowTests.swift
//
//  `.padding` around a lazy stack that is a scroll view's content relays the
//  scroll window below its top lines (`ScrollWindowRelay`), as a `Section`'s
//  header and the content margins do: unrelayed, the stack took the window as
//  if it were all the content, the scroll view took its height for the
//  content's, and End stopped short of the last row and the padding below it.
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

@MainActor
@Suite("Padding relays the scroll window to a lazy stack")
struct PaddingScrollWindowTests {
    /// One-line rows (the uniform window), rows of one to three lines past the
    /// anchored threshold, or forty of them (the exact walk).
    private func rows(_ count: Int, variable: Bool) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { sectionRow($0, variable: variable) }
        }
    }

    private func handler(_ focus: FocusManager) -> ScrollViewHandler? {
        focus.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
    }

    @Test(
        "End reaches the last row and the padding below it, as in the same lines drawn eagerly",
        arguments: [(300, false), (300, true), (40, true)])
    func endReachesTheEnd(count: Int, variable: Bool) {
        let padded = ScrollView { rows(count, variable: variable).padding(.vertical, 2) }
        let eager = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { sectionRow($0, variable: variable) }
            }
            .padding(.vertical, 2)
        }
        let (tui, focus) = (TUIContext(), FocusManager())
        let (eagerTUI, eagerFocus) = (TUIContext(), FocusManager())
        _ = scrollFrame(padded, tui: tui, focusManager: focus)
        _ = scrollFrame(eager, tui: eagerTUI, focusManager: eagerFocus)
        for frames in 0..<2 {
            _ = handler(focus)?.handleKeyEvent(KeyEvent(key: .end))
            _ = handler(eagerFocus)?.handleKeyEvent(KeyEvent(key: .end))
            let screen = scrollFrame(padded, tui: tui, focusManager: focus)
            let expected = scrollFrame(eager, tui: eagerTUI, focusManager: eagerFocus)
            #expect(screen == expected, "frame \(frames): \(screen) vs \(expected)")
            #expect(screen.suffix(2) == ["", ""], "the bottom padding is on screen: \(screen)")
        }
        // The anchored window's height is an estimate by design (§5e).
        if !(variable && count > 256) {
            #expect(handler(focus)?.contentHeight == handler(eagerFocus)?.contentHeight)
        }
    }

    @Test("A padded lazy stack still draws its band: onAppear fires for the rows on screen")
    func onlyTheBandAppears() {
        var appeared = 0
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<2_000, id: \.self) { index in Text("row \(index)").onAppear { appeared += 1 } }
            }
            .padding(.vertical, 1)
        }
        let (tui, focus) = (TUIContext(), FocusManager())
        _ = scrollFrame(view, tui: tui, focusManager: focus, height: 10)
        let screen = scrollFrame(view, tui: tui, focusManager: focus, height: 10)
        #expect(screen.first?.isEmpty == true, "the top padding: \(screen)")
        #expect(screen.contains("row 7"), "\(screen)")
        #expect(appeared < 40, "appeared \(appeared) times")
    }

    @Test("A seek lands its row below the top padding, as in the eager column")
    func seekUnderPadding() {
        let box = SectionProxyBox()
        let view = ScrollViewReader { proxy in
            // swiftlint:disable:next redundant_discardable_let
            let _ = box.proxy = proxy
            ScrollView { rows(300, variable: false).padding(.top, 3) }
        }
        let (tui, focus) = (TUIContext(), FocusManager())
        _ = scrollFrame(view, tui: tui, focusManager: focus)
        box.proxy?.scrollTo(150, anchor: .top)
        let screen = scrollFrame(view, tui: tui, focusManager: focus)
        #expect(screen.first == "row 150", "\(screen)")
        // Row 0's top at the viewport's top, the padding above it scrolled
        // off, as a `.top` seek places any row; scrolled to the top, it shows.
        box.proxy?.scrollTo(0, anchor: .top)
        let top = scrollFrame(view, tui: tui, focusManager: focus)
        #expect(top.first == "row 0", "\(top)")
        #expect(handler(focus)?.scrollOffset == 3)
        box.position.scrollTo(edge: .top)
        _ = handler(focus)?.handleKeyEvent(KeyEvent(key: .home))
        let home = scrollFrame(view, tui: tui, focusManager: focus)
        #expect(home.prefix(4) == ["", "", "", "row 0"], "\(home)")
    }
}
