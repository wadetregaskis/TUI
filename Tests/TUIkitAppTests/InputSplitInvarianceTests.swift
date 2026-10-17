//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InputSplitInvarianceTests.swift
//
//  Property test over the terminal input parser: every escape sequence,
//  mouse report, paste bracket and multi-byte UTF-8 character must decode
//  to the same events regardless of where a read() boundary lands. This is
//  the class of bug behind the historical stray-'[' page jumps and leaked
//  'M' terminators; the whole corpus is checked at every split point.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Input split-read invariance")
struct InputSplitInvarianceTests {
    private final class ByteBox { var bytes: [UInt8] = [] }

    private func makeTerminal() -> (Terminal, ([UInt8]) -> Void) {
        let terminal = Terminal()
        let box = ByteBox()
        terminal.readSource = { buffer in
            guard !box.bytes.isEmpty else { return 0 }
            let count = min(box.bytes.count, buffer.count)
            for index in 0..<count { buffer[index] = box.bytes[index] }
            box.bytes.removeFirst(count)
            return count
        }
        return (terminal, { box.bytes.append(contentsOf: $0) })
    }

    /// Drains events: pumps readEvent until `quietLimit` consecutive nils.
    private func drain(_ terminal: Terminal, quietLimit: Int = 8) -> [TerminalInput] {
        var events: [TerminalInput] = []
        var quiet = 0
        var calls = 0
        while quiet < quietLimit && calls < 60 {
            calls += 1
            if let event = terminal.readEvent() {
                events.append(event)
                quiet = 0
            } else {
                quiet += 1
            }
        }
        return events
    }

    @Test("Sequences split at every byte boundary decode identically")
    func splitInvariance() {
        let esc: [UInt8] = [0x1B]
        let sequences: [(String, [UInt8])] = [
            ("up", esc + Array("[A".utf8)),
            ("down", esc + Array("[B".utf8)),
            ("shift+right", esc + Array("[1;2C".utf8)),
            ("ctrl+left", esc + Array("[1;5D".utf8)),
            ("home", esc + Array("[H".utf8)),
            ("pgdn", esc + Array("[6~".utf8)),
            ("delete", esc + Array("[3~".utf8)),
            ("F1-SS3", esc + Array("OP".utf8)),
            ("mouse-press", esc + Array("[<0;10;5M".utf8)),
            ("mouse-release", esc + Array("[<0;10;5m".utf8)),
            ("mouse-wheel", esc + Array("[<64;3;4M".utf8)),
            ("focus-in", esc + Array("[I".utf8)),
            ("focus-out", esc + Array("[O".utf8)),
            ("focus-in-then-text", esc + Array("[I".utf8) + Array("a".utf8)),
            // Escape pressed as the window loses focus. The meta-prefix rule
            // would read the pair as one Option+Escape chord.
            ("escape-then-focus-out", esc + esc + Array("[O".utf8)),
            ("paste", esc + Array("[200~hi".utf8) + esc + Array("[201~".utf8)),
            ("ascii", Array("abc".utf8)),
            ("utf8-2byte", Array("é".utf8)),
            ("utf8-3byte", Array("你".utf8)),
            ("utf8-4byte", Array("🎉".utf8)),
            ("text-then-arrow", Array("a".utf8) + esc + Array("[B".utf8)),
            ("arrow-then-text", esc + Array("[B".utf8) + Array("b".utf8)),
            ("two-arrows", esc + Array("[A".utf8) + esc + Array("[B".utf8)),
            // Option-as-meta prefixes a FULL sequence with ESC: Option-Shift-Tab
            // is ESC ESC [ Z. The class of bug: consuming just "ESC ESC" and
            // leaking "[ Z" as literal keystrokes (the '[' page shortcut).
            ("meta-shift-tab", esc + esc + Array("[Z".utf8)),
            ("meta-up", esc + esc + Array("[A".utf8)),
            ("meta-shift-tab-then-text", esc + esc + Array("[Z".utf8) + Array("x".utf8)),
            // Replies the terminal volunteered. They are string-terminated
            // rather than final-byte-terminated, so every place that has to
            // decide "is this ESC an introducer?" has to know about them —
            // including the deferred-ESC re-attach, which once knew only
            // `[` and `O` and spelled a split reply out as typing.
            ("apc-ack", esc + Array("_Gi=1;OK".utf8) + esc + Array("\\".utf8)),
            ("osc-bg", esc + Array("]11;rgb:0000/0000/0000\u{07}".utf8)),
            ("apc-ack-then-text", esc + Array("_Gi=1;OK".utf8) + esc + Array("\\x".utf8)),
            // An OSC 5522 clipboard write's acknowledgement.
            ("osc5522-done-then-text", esc + Array("]5522;type=write:status=DONE".utf8) + esc + Array("\\x".utf8)),
            // A device-attributes answer: a CSI longer than any keystroke,
            // which is the shape that used to be truncated at 32 bytes.
            ("da1", esc + Array("[?63;1;2;4;6;9;15;16;18;21;22;28;29c".utf8)),
            // Escape pressed just before the terminal sent something that is
            // not a key: the ESC is the Escape key, never a meta prefix on it
            // (`tryExtractMetaPrefixed`), wherever the read boundary falls.
            ("escape-then-paste", esc + esc + Array("[200~hi".utf8) + esc + Array("[201~".utf8)),
            ("escape-then-mouse", esc + esc + Array("[<0;10;5M".utf8)),
            ("escape-then-osc-bg", esc + esc + Array("]11;rgb:0000/0000/0000\u{07}".utf8)),
            ("escape-then-apc-ack-then-text", esc + esc + Array("_Gi=1;OK".utf8) + esc + Array("\\x".utf8)),
            // Option-[ on a meta-sending terminal is `ESC [`, the CSI
            // introducer; a sequence straight after it must parse, not be
            // read as the rest of one CSI and typed out.
            ("alt-bracket-then-up", esc + Array("[".utf8) + esc + Array("[A".utf8)),
            ("alt-bracket-then-paste", esc + Array("[".utf8) + esc + Array("[200~hi".utf8) + esc + Array("[201~".utf8)),
            // And Option-[ then `M`, the start of a legacy mouse report.
            ("alt-bracket-m-then-paste", esc + Array("[M".utf8) + esc + Array("[200~hi".utf8) + esc + Array("[201~".utf8)),
            // A sequence cut short straight after an `ESC` leaves it nothing
            // to prefix: Escape, then the sequence that cut in.
            ("escape-then-cut-short-csi-then-up", esc + esc + Array("[1;2".utf8) + esc + Array("[A".utf8)),
        ]

        var reports: [String] = []
        for (name, bytes) in sequences {
            let (wholeTerminal, wholeStage) = makeTerminal()
            wholeStage(bytes)
            let whole = drain(wholeTerminal)

            for splitAt in 1..<bytes.count {
                let (terminal, stage) = makeTerminal()
                stage(Array(bytes[..<splitAt]))
                var events: [TerminalInput] = []
                // One pump between the reads models the mid-sequence boundary.
                if let event = terminal.readEvent() { events.append(event) }
                stage(Array(bytes[splitAt...]))
                events.append(contentsOf: drain(terminal))

                if events != whole {
                    reports.append(
                        "\(name) split@\(splitAt): whole=\(whole) split=\(events)")
                }
            }
        }

        if !reports.isEmpty {
            print("=== SPLIT DIVERGENCES (\(reports.count)) ===")
            for report in reports.prefix(25) { print(report) }
        }
        #expect(reports.isEmpty, "\(reports.count) split divergences — see printed report")
    }

    /// The application-mode keys (`ESC O` and a byte, a modifier between them
    /// where a terminal sends one), whole and split at every byte: each must
    /// arrive as its key, and only its key. K1 in
    /// `Documentation/Terminals/Ghostty VT reference adoption study.md`.
    @Test("Every SS3 key spelling decodes to its key, split at every byte")
    func ss3SplitInvariance() {
        let keypadBytes = Array("pqrstuvwxyjklmnoXMI ".utf8)
        let digitKeys: [Key] = (0...9).map { (digit: Int) -> Key in .character(Character(String(digit))) }
        let symbolKeys: [Key] = ["*", "+", ",", "-", ".", "/", "="].map { (symbol: Character) -> Key in .character(symbol) }
        let keypadKeys: [Key] = digitKeys + symbolKeys + [.enter, .tab, .space]
        var cases: [(String, [UInt8], [TerminalInput])] = zip(keypadBytes, keypadKeys).map { byte, key in
            ("keypad-\(Character(UnicodeScalar(byte)))", [0x1B, 0x4F, byte], [.key(KeyEvent(key: key, numericPad: true))])
        }
        for (byte, key) in zip(Array("ABCDHFPQRS".utf8), [Key.up, .down, .right, .left, .home, .end, .f1, .f2, .f3, .f4]) {
            cases.append(("ss3-\(Character(UnicodeScalar(byte)))", [0x1B, 0x4F, byte], [.key(KeyEvent(key: key))]))
        }
        let esc: [UInt8] = [0x1B]
        cases += [
            ("shift-f1-old", esc + Array("O2P".utf8), [.key(KeyEvent(key: .f1, shift: true))]),
            ("ctrl-up-ss3", esc + Array("O1;5A".utf8), [.key(KeyEvent(key: .up, ctrl: true))]),
            ("begin-then-text", esc + Array("OEx".utf8), [.key(KeyEvent(character: "x"))]),
            ("ss3-then-text", esc + Array("OAb".utf8), [.key(KeyEvent(key: .up)), .key(KeyEvent(character: "b"))]),
            ("two-ss3", esc + Array("OB".utf8) + esc + Array("OC".utf8),
             [.key(KeyEvent(key: .down)), .key(KeyEvent(key: .right))]),
            // Alt-Shift-O, which a meta-sending terminal also spells `ESC O`,
            // typed before an arrow: the arrow's ESC is not the SS3 key's byte.
            ("alt-shift-o-then-arrow", esc + Array("O".utf8) + esc + Array("[A".utf8),
             [.key(KeyEvent(key: .character("O"), alt: true, shift: true)), .key(KeyEvent(key: .up))]),
            ("shift-f3-csi", esc + Array("[1;2R".utf8), [.key(KeyEvent(key: .f3, shift: true))]),
            ("f1-highest-modifier", esc + Array("O16P".utf8),
             [.key(KeyEvent(key: .f1, ctrl: true, alt: true, shift: true))]),
        ]
        // Alt-Shift-O and then typing that no modifier spells: the chord, and
        // then every byte typed, at once — not held, and not dropped.
        let altShiftO = TerminalInput.key(KeyEvent(key: .character("O"), alt: true, shift: true))
        for typed in ["123", "17x", "1;x", "2;5A", "0p", ";A", "z", "2a", "1;5z"] {
            cases.append((
                "alt-shift-o-then-\(typed)", esc + Array("O\(typed)".utf8),
                [altShiftO] + typed.map { .key(KeyEvent(character: $0)) }))
        }

        var reports: [String] = []
        for (name, bytes, expected) in cases {
            let (wholeTerminal, wholeStage) = makeTerminal()
            wholeStage(bytes)
            let whole = drain(wholeTerminal)
            if whole != expected { reports.append("\(name) whole: \(whole), expected \(expected)") }

            for splitAt in 1..<bytes.count {
                let (terminal, stage) = makeTerminal()
                stage(Array(bytes[..<splitAt]))
                var events: [TerminalInput] = []
                if let event = terminal.readEvent() { events.append(event) }
                stage(Array(bytes[splitAt...]))
                events.append(contentsOf: drain(terminal))
                if events != expected { reports.append("\(name) split@\(splitAt): \(events)") }
            }
        }
        #expect(reports.isEmpty, "\(reports.count) divergences: \(reports.prefix(10))")
    }
}
