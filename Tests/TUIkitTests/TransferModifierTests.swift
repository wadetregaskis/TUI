//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransferModifierTests.swift
//
//  `copyable`, `cuttable`, `pasteDestination` and `PasteButton`: a value
//  copied in the app pastes back as itself, and text copied elsewhere pastes
//  as a string or as a value read from it. Everywhere, Linux included.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

private struct Card: CustomStringConvertible, Equatable {
    let name: String
    var description: String { name }
}

private final class Received: @unchecked Sendable {
    var cards: [Card] = []
    var numbers: [Int] = []
    var strings: [String] = []
    var cut = 0
}

private func control(_ letter: Character) -> KeyEvent {
    KeyEvent(key: .character(letter), ctrl: true)
}

@MainActor
@Suite("copyable, cuttable, pasteDestination and PasteButton")
struct TransferModifierTests {

    private func harness(_ board: FakeClipboard) -> InputChainHarness {
        let typed = TypedClipboard()
        return InputChainHarness {
            $0.clipboardAccess = board.access
            $0.typedClipboard = typed
        }
    }

    @Test("A value copied in the app pastes back as itself")
    func typedRoundTrip() {
        let board = FakeClipboard()
        let received = Received()
        let harness = harness(board)
        let consumed = harness.play([control("c"), control("v")]) {
            Text("card").focusable()
                .copyable([Card(name: "ace")])
                .pasteDestination(for: Card.self) { received.cards += $0 }
        }
        #expect(consumed == [true, true])
        #expect(board.writes == ["ace"], "the clipboard gets the text")
        #expect(received.cards == [Card(name: "ace")], "the paste gets the value")
    }

    @Test("Text copied elsewhere pastes as a string or a value read from it, and not as anything else")
    func textFallback() {
        let board = FakeClipboard(contents: "42")
        let received = Received()
        let consumed = harness(board).play([control("v")]) {
            VStack {
                Text("numbers").focusable()
                    .pasteDestination(for: Card.self) { received.cards += $0 }
            }
            .pasteDestination(for: Int.self) { received.numbers += $0 }
        }
        #expect(consumed == [true])
        #expect(received.cards.isEmpty, "a Card cannot be read from text, so the inner destination lets it pass")
        #expect(received.numbers == [42])
    }

    @Test("A bracketed paste reaches a String destination; a validator can refuse it")
    func bracketedPasteAndValidator() {
        let board = FakeClipboard()
        let received = Received()
        let consumed = harness(board).play([KeyEvent(key: .paste("hello")), KeyEvent(key: .paste("no"))]) {
            Text("text").focusable()
                .pasteDestination(
                    for: String.self, action: { received.strings += $0 },
                    validator: { items in items.filter { $0 != "no" } })
        }
        #expect(consumed == [true, false])
        #expect(received.strings == ["hello"])
    }

    @Test("Cut runs its action and copies what it removed")
    func cut() {
        let board = FakeClipboard()
        let received = Received()
        let consumed = harness(board).play([control("x")]) {
            Text("card").focusable()
                .cuttable(for: Card.self) {
                    received.cut += 1
                    return [Card(name: "king"), Card(name: "queen")]
                }
        }
        #expect(consumed == [true])
        #expect(received.cut == 1)
        #expect(board.writes == ["king\nqueen"])
    }

    @Test("PasteButton delivers the clipboard as its payload type")
    func pasteButton() {
        let board = FakeClipboard(contents: "7")
        let received = Received()
        _ = harness(board).play([KeyEvent(key: .enter)]) {
            PasteButton(payloadType: Int.self) { received.numbers += $0 }
        }
        #expect(received.numbers == [7])
    }
}
