//  🖥️ TUI — A Terminal UI framework for Swift
//  MetaStringIntroducerTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

/// A meta-sending terminal sends Option-_ as `ESC _` — byte for byte the
/// introducer of an APC reply, which the parser swallows until its
/// terminator. Redo is bound to Option-_ for the terminals with no better
/// redo key, so an `ESC _` that nothing ever follows has to be the chord.
@MainActor
@Suite("Option chords on a string introducer")
struct MetaStringIntroducerTests {

    /// A terminal reading whatever is staged, one read per stage.
    private func makeTerminal() -> (Terminal, ([UInt8]) -> Void) {
        let terminal = Terminal()
        let box = Box()
        terminal.readSource = { buffer in
            guard !box.bytes.isEmpty else { return 0 }
            let count = min(box.bytes.count, buffer.count)
            for index in 0..<count { buffer[index] = box.bytes[index] }
            box.bytes.removeFirst(count)
            return count
        }
        return (terminal, { box.bytes.append(contentsOf: $0) })
    }

    private final class Box { var bytes: [UInt8] = [] }

    /// Every event `pumps` reads produce, nils dropped.
    private func events(_ terminal: Terminal, pumps: Int = 12) -> [TerminalInput] {
        (0..<pumps).compactMap { _ in terminal.readEvent() }
    }

    @Test("ESC _ with nothing behind it is Option-_, after the dead-sequence wait")
    func lonelyIntroducerIsTheChord() {
        let (terminal, stage) = makeTerminal()
        stage([0x1B, 0x5F])
        #expect(events(terminal) == [.key(KeyEvent(key: .character("_"), alt: true))])
    }

    @Test("Each string introducer alone is its Option chord", arguments: Array("]P^X_".utf8))
    func everyIntroducer(byte: UInt8) {
        let (terminal, stage) = makeTerminal()
        stage([0x1B, byte])
        let character = Character(Unicode.Scalar(byte))
        #expect(events(terminal) == [.key(KeyEvent(key: .character(character), alt: true, shift: character.isUppercase))])
    }

    @Test("A reply that arrives whole is still swallowed")
    func wholeReplySwallowed() {
        let (terminal, stage) = makeTerminal()
        stage(Array("\u{1B}_Gi=1;OK\u{1B}\\x".utf8))
        #expect(events(terminal) == [.key(KeyEvent(character: "x"))])
    }

    @Test("A reply whose tail comes on a later read is still swallowed")
    func splitReplySwallowed() {
        let (terminal, stage) = makeTerminal()
        stage([0x1B, 0x5F])
        _ = terminal.readEvent()
        stage(Array("Gi=1;OK\u{1B}\\x".utf8))
        #expect(events(terminal) == [.key(KeyEvent(character: "x"))])
    }
}
