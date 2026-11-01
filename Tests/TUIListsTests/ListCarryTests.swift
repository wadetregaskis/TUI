//  🖥️ TUI — A Terminal UI framework for Swift
//  ListCarryTests.swift
//
//  A drag carried from the keyboard at a `List` (A53-KEYBOARD-DRAG): the
//  list is one stop, and Up and Down move its landing slot between the rows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUILists
import TUITesting
@testable import TUITestSupport

private let pickUp = KeyEvent(key: .character("r"), ctrl: true)

@MainActor
@Suite("A drag carried from the keyboard, at a list")
struct ListCarryTests {
    /// Drops a "zzz" carried from the card on a list of four rows, after
    /// `downs` presses of Down at the list, and reports the index it landed at.
    private func dropOnList(downs: Int) -> Int? {
        final class Landed: @unchecked Sendable { var index: Int? }
        let landed = Landed()
        let view = {
            VStack(alignment: .leading) {
                Text("card").draggable("zzz")
                List {
                    ForEach(["a", "b", "c", "d"], id: \.self) { Text($0) }
                        .dropDestination(for: String.self) { _, index in landed.index = index }
                }
                .frame(height: 6)
            }
        }
        let downs = Array(repeating: KeyEvent(key: .down), count: downs)
        let app = TestApp(width: 40, height: 12, content: view)
        for event in [pickUp, KeyEvent(key: .tab)] + downs + [KeyEvent(key: .enter)] { app.press(event) }
        return landed.index
    }

    @Test("At a list, Up and Down move the landing slot between its rows, and Return drops there")
    func listIsOneStopWithRows() {
        let top = dropOnList(downs: 0)
        let lower = dropOnList(downs: 2)
        #expect(top != nil)
        #expect(lower != nil)
        if let top, let lower { #expect(lower > top, "two rows down lands later in the list: \(top) → \(lower)") }
    }
}
