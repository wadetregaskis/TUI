//  🖥️ TUI — A Terminal UI framework for Swift
//  CarryModeTests.swift
//
//  A drag carried from the keyboard (owner ruling A53-KEYBOARD-DRAG): Ctrl-R
//  on a focused `.draggable` picks it up, Tab moves only among the stops that
//  can take it, Return drops it, and Escape puts it back.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

private struct Card: Equatable {
    let name: String
}

private final class Log: @unchecked Sendable {
    var dropped: [Card] = []
    var strings: [String] = []
    var pressed: [String] = []
    /// Whether the bin is out of sight, and a trap for cards drawn in its
    /// place.
    var binGone = false
    var trapped: [Card] = []
}

private let pickUp = KeyEvent(key: .character("r"), ctrl: true)

@MainActor
@Suite("A drag carried from the keyboard")
struct CarryModeTests {
    /// A card, a button, a destination for text and one for cards, in that
    /// order down the page.
    private func board(_ log: Log) -> some View {
        VStack(alignment: .leading) {
            Text("card").draggable(Card(name: "ace"))
            Button("other") { log.pressed.append("other") }
            Text("strings").dropDestination(for: String.self) { items, _ in
                log.strings += items
                return true
            }
            // The bin, which moves out of sight — still a focus stop, but
            // drawn nowhere — where `binGone`, and a trap for cards that
            // takes its place on the screen.
            ZStack {
                if log.binGone {
                    Text("trap").dropDestination(for: Card.self) { cards, _ in
                        log.trapped += cards
                        return true
                    }
                }
                Text("bin").dropDestination(for: Card.self) { cards, _ in
                    log.dropped += cards
                    return true
                }
                .offset(y: log.binGone ? 5 : 0)
            }
            .frame(height: 1)
            .clipped()
        }
    }

    @Test("Ctrl-R picks the card up, Tab goes straight to the bin that takes it, and Return drops it there")
    func carryAndDrop() {
        let log = Log()
        let harness = InputChainHarness()
        let consumed = harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .enter)]) { board(log) }
        #expect(consumed == [true, true, true])
        #expect(log.dropped == [Card(name: "ace")])
        #expect(log.pressed.isEmpty, "the button between them was passed over")
        #expect(log.strings.isEmpty, "the destination for text was passed over")
        #expect(harness.tui.dragAndDropSession.active == nil)
    }

    @Test("While carried, the bin is targeted and the drag wears a copy's badge")
    func targetedWhileCarried() {
        let log = Log()
        let harness = InputChainHarness()
        harness.play([pickUp, KeyEvent(key: .tab)]) { board(log) }
        let session = harness.tui.dragAndDropSession
        #expect(session.active != nil)
        #expect(session.proposedOperation == .copy)
    }

    @Test("Escape puts it back, and the keys go to the page again")
    func escapePutsItBack() {
        let log = Log()
        let harness = InputChainHarness()
        harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .escape)]) { board(log) }
        #expect(log.dropped.isEmpty)
        harness.play([KeyEvent(key: .tab), KeyEvent(key: .enter)]) { board(log) }
        #expect(log.pressed == ["other"], "Tab from the card, where the focus went back, reaches the button")
    }

    @Test("The bin is marked as reachable, and the status bar says what Return and Escape do")
    func cuesAndLabels() {
        let log = Log()
        let harness = InputChainHarness()
        harness.play([pickUp]) { board(log) }
        let session = harness.tui.dragAndDropSession
        #expect(session.carryCues.count == 1, "the bin, and not the button or the text destination")
        #expect(session.carryLabels?.returnKey == "cancel move", "at its origin, Return puts it back")
        harness.play([KeyEvent(key: .tab)]) { board(log) }
        #expect(session.carryCues.count == 1, "the origin, now the carry is at the bin")
        #expect(session.carryLabels?.returnKey == "drop")
        #expect(session.carryLabels?.escape == "cancel move")
    }

    @Test("Once the stop the carry is at is drawn nowhere, Return drops nothing where it was: it puts the card back")
    func undrawnStopPutsBack() {
        let log = Log()
        let harness = InputChainHarness()
        harness.play([pickUp, KeyEvent(key: .tab)]) { board(log) }
        // The bin moves out of sight, the focus still on it, and a trap for
        // cards is drawn where it was.
        log.binGone = true
        let bin = harness.focusManager.currentFocusedID
        harness.play([KeyEvent(key: .enter)]) { board(log) }
        #expect(bin != nil && harness.focusManager.currentFocusedID != bin, "the focus went back to the card")
        #expect(log.dropped.isEmpty && log.trapped.isEmpty, "\(log.dropped) \(log.trapped)")
        #expect(harness.tui.dragAndDropSession.active == nil)
    }

    @Test("A plain key while carrying is swallowed, not typed")
    func plainKeysSwallowed() {
        let log = Log()
        let harness = InputChainHarness()
        let consumed = harness.play([pickUp, KeyEvent(key: .character("x"))]) { board(log) }
        #expect(consumed == [true, true])
        #expect(harness.tui.dragAndDropSession.active != nil, "still carried")
    }
}
