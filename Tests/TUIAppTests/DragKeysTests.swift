//  🖥️ TUI — A Terminal UI framework for Swift
//  DragKeysTests.swift
//
//  A drag's two ends from the keyboard (owner, 2026-10-26, A53's
//  prerequisite): a focused `.draggable` answers Copy with its payload, and a
//  focused drop destination answers Paste by dropping it. Content with focus
//  stops of its own keeps them, and gains no second; content with none gets
//  one stop of the modifier's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

private struct Card: CustomStringConvertible, Equatable {
    let name: String
    var description: String { name }
}

private final class Log: @unchecked Sendable {
    var dropped: [Card] = []
    var pressed: [String] = []
}

private func control(_ letter: Character) -> KeyEvent {
    KeyEvent(key: .character(letter), ctrl: true)
}

@MainActor
@Suite("A drag's two ends from the keyboard")
struct DragKeysTests {

    private func harness(_ board: FakeClipboard) -> InputChainHarness {
        let typed = TypedClipboard()
        return InputChainHarness {
            $0.clipboardAccess = board.access
            $0.typedClipboard = typed
        }
    }

    @Test("Copy on a focused draggable, Tab, and Paste on a destination drops the payload there")
    func copyThenPaste() {
        let board = FakeClipboard()
        let log = Log()
        let consumed = harness(board).play([control("c"), KeyEvent(key: .tab), control("v")]) {
            VStack {
                Text("card").draggable(Card(name: "ace"))
                Text("bin").dropDestination(for: Card.self) { cards, _ in
                    log.dropped += cards
                    return true
                }
            }
        }
        #expect(consumed == [true, true, true])
        #expect(board.writes == ["ace"], "the clipboard gets the text")
        #expect(log.dropped == [Card(name: "ace")], "the drop gets the value")
    }

    @Test("A draggable control keeps its own stop: Tab does not cross it twice")
    func controlKeepsItsStop() {
        let log = Log()
        let consumed = harness(FakeClipboard()).play([control("c"), KeyEvent(key: .tab), KeyEvent(key: .enter)]) {
            VStack {
                Button("first") { log.pressed.append("first") }.draggable(Card(name: "ace"))
                Button("second") { log.pressed.append("second") }
            }
        }
        #expect(consumed.first == true, "Copy on the button copies the draggable's payload")
        #expect(log.pressed == ["second"], "one Tab reached the next button: \(log.pressed)")
    }

    @Test("A disabled draggable and a destination that takes nothing are no stops and answer nothing")
    func disabledAnswersNothing() {
        let board = FakeClipboard(contents: "ace")
        let log = Log()
        let consumed = harness(board).play([control("c"), control("v")]) {
            VStack {
                Text("card").draggable(Card(name: "ace")).disabled(true)
                Text("bin").dropDestination(for: Card.self, isEnabled: false) { cards, _ in log.dropped += cards }
            }
        }
        #expect(consumed == [false, false])
        #expect(board.writes.isEmpty && log.dropped.isEmpty)
    }
}
