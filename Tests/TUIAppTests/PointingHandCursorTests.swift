//  🖥️ TUI — A Terminal UI framework for Swift
//  PointingHandCursorTests.swift
//
//  Which of TUI's own controls give the pointer a hand: links only, the Mac's
//  convention, by default; every clickable control under
//  `.pointingHandCursor(over: .everythingClickable)` (decisions A-O12-1, the owner's answer of
//  2026-10-27).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITerminalHost
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("Which controls give the pointer a hand")
struct PointingHandCursorTests {
    /// The shape over `text` in a frame of `view`, where the terminal takes
    /// shapes and TUI's controls set theirs.
    private func shape(over text: String, in view: some View) -> PointerShape?? {
        let harness = PointerShapeHarness(controlShapes: true)
        let buffer = harness.frame(view)
        guard let cell = harness.cell(of: text, in: buffer) else {
            Issue.record("\(text) was not drawn: \(buffer.lines.map(\.stripped))")
            return .none
        }
        return .some(harness.shape(atX: cell.x, y: cell.y))
    }

    @Test("By default a button keeps the arrow, as a Mac's does")
    func buttonKeepsTheArrowByDefault() {
        #expect(shape(over: "Save", in: Button("Save") {}) == .some(nil))
    }

    @Test("By default a link, and a button styled as one, get the hand")
    func linksGetTheHand() throws {
        let url = try #require(URL(string: "https://example.com"))
        #expect(shape(over: "Docs", in: Link("Docs", destination: url)) == .some(.link))
        #expect(shape(over: "More", in: Button("More") {}.buttonStyle(.link)) == .some(.link))
    }

    /// The scope's own documentation names a link inside a `Text`, which
    /// had none (the cursor survey, 2026-10-28).
    @Test("By default a link inside a Text gets the hand, and the text around it the arrow")
    func inlineLinkGetsTheHand() {
        let text = Text("Read the [manual](https://example.com) first")
        #expect(shape(over: "manual", in: text) == .some(.link))
        #expect(shape(over: "Read", in: text) == .some(nil))
    }

    @Test(".pointingHandCursor(over: .everythingClickable) gives a button the hand")
    func buttonGetsTheHandWhenAsked() {
        #expect(shape(over: "Save", in: Button("Save") {}.pointingHandCursor(over: .everythingClickable)) == .some(.link))
    }

    @Test(".pointingHandCursor(over: .everythingClickable) gives every clickable control the hand, set once above them")
    func everyClickableControlGetsTheHand() {
        let view = VStack(alignment: .leading) {
            Toggle("Wi-Fi", isOn: .constant(true))
            Toggle("Bluetooth", isOn: .constant(false))
        }
        .pointingHandCursor(over: .everythingClickable)
        #expect(shape(over: "Wi-Fi", in: view) == .some(.link))
        #expect(shape(over: "Bluetooth", in: view) == .some(.link))
        // And not without it.
        let plain = Toggle("Wi-Fi", isOn: .constant(true))
        #expect(shape(over: "Wi-Fi", in: plain) == .some(nil))
    }

    @Test("A view's own pointerStyle still wins over the setting")
    func ownStyleWins() {
        let view = Text("Pan").pointerStyle(.grabIdle).pointingHandCursor(over: .everythingClickable)
        #expect(shape(over: "Pan", in: view) == .some(.grab))
    }
}
