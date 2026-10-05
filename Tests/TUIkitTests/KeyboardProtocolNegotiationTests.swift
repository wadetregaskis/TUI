//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyboardProtocolNegotiationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Turning the kitty keyboard protocol on where the terminal speaks it, and
/// off again, against a scripted terminal.
///
/// The replies are the specification's: `CSI ? flags u` to the query, and a
/// DA1 answer to the fence. No real terminal has been captured answering yet;
/// see `Documentation/Terminal-compatibility.md`.
@MainActor
@Suite("Kitty keyboard protocol negotiation")
struct KeyboardProtocolNegotiationTests {

    private final class Script {
        var reads: [[UInt8]] = []
        var sent: [String] = []
    }

    private static let fence = "\u{1B}[?62;22c"
    private static let query = KeyboardProtocolQuery.request

    private func makeTerminal(reads: [String]) -> (Terminal, Script) {
        let terminal = Terminal()
        let script = Script()
        script.reads = reads.map { Array($0.utf8) }
        terminal.readSource = { buffer in
            guard !script.reads.isEmpty else { return 0 }
            let chunk = script.reads.removeFirst()
            for (index, byte) in chunk.enumerated() { buffer[index] = byte }
            return chunk.count
        }
        terminal.exchangeTransport = .init(
            send: { script.sent.append($0) }, waitForInput: { _ in true })
        return (terminal, script)
    }

    @Test("A terminal that answers gets every enhancement pushed, and is asked what it took")
    func supportedTerminal() {
        let (terminal, script) = makeTerminal(reads: ["\u{1B}[?0u" + Self.fence, "\u{1B}[?31u" + Self.fence])
        terminal.negotiateKeyboardEnhancement(timeout: 5)
        #expect(script.sent == [Self.query, "\u{1B}[>31u", Self.query])
        #expect(terminal.keyboardEnhancement == .requested)
        #expect(terminal.keyboardFlagsPushed)
    }

    @Test("A terminal that answers only the fence is left in its legacy encoding")
    func unsupportedTerminal() {
        let (terminal, script) = makeTerminal(reads: [Self.fence])
        terminal.negotiateKeyboardEnhancement(timeout: 5)
        #expect(script.sent == [Self.query])
        #expect(terminal.keyboardEnhancement.isEmpty)
        #expect(!terminal.keyboardFlagsPushed)
        #expect(terminal.negotiatedKeyboardFlags == nil)
    }

    @Test("A terminal that takes only some enhancements is read with those")
    func partialSupport() {
        let (terminal, _) = makeTerminal(reads: ["\u{1B}[?0u" + Self.fence, "\u{1B}[?3u" + Self.fence])
        terminal.negotiateKeyboardEnhancement(timeout: 5)
        #expect(terminal.keyboardEnhancement == [.disambiguateEscapeCodes, .reportEventTypes])
    }

    @Test("All keys as escape codes without their text is replaced by a push without the former")
    func escapeCodesWithoutText() {
        let (terminal, script) = makeTerminal(reads: [
            "\u{1B}[?0u" + Self.fence, "\u{1B}[?15u" + Self.fence, "\u{1B}[?7u" + Self.fence,
        ])
        terminal.negotiateKeyboardEnhancement(timeout: 5)
        #expect(script.sent == [Self.query, "\u{1B}[>31u", Self.query, "\u{1B}[<u\u{1B}[>7u", Self.query])
        #expect(terminal.keyboardEnhancement == [.disambiguateEscapeCodes, .reportEventTypes, .reportAlternateKeys])
    }

    @Test("A second answer that misses the window is taken as the push, so keys still decode", arguments: [
        ["\u{1B}[?0u\u{1B}[?62;22c"],
        ["\u{1B}[?0u\u{1B}[?62;22c", "\u{1B}[?15u\u{1B}[?62;22c"],
    ])
    func lateSecondAnswer(answered: [String]) {
        let (terminal, script) = makeTerminal(reads: answered)
        terminal.negotiateKeyboardEnhancement(timeout: 0.05)
        let pushed = terminal.negotiatedKeyboardFlags?.pushed
        #expect(pushed != nil && terminal.keyboardFlagsPushed)
        #expect(terminal.keyboardEnhancement == pushed, "read in the grammar of what is on the terminal's stack")
        // The late answer turns up as input, and then a key in the protocol's
        // encoding: Return, which a legacy reading drops.
        script.reads.append(Array("\u{1B}[?31u\u{1B}[?62;22c\u{1B}[13u".utf8))
        var events: [TerminalInput] = []
        while let event = terminal.readEvent() { events.append(event) }
        #expect(events == [.key(KeyEvent(key: .enter))])
    }

    @Test("A pop is owed once, and a resume pushes the same flags without asking")
    func popAndRepush() {
        let (terminal, script) = makeTerminal(reads: ["\u{1B}[?0u" + Self.fence, "\u{1B}[?31u" + Self.fence])
        terminal.negotiateKeyboardEnhancement(timeout: 5)
        script.sent.removeAll()

        terminal.popKeyboardFlags()
        terminal.popKeyboardFlags()
        #expect(script.sent == ["\u{1B}[<u"], "popped once, however often asked")
        #expect(terminal.keyboardEnhancement.isEmpty, "keys after the pop are the legacy bytes")

        terminal.repushKeyboardFlags()
        terminal.repushKeyboardFlags()
        #expect(script.sent == ["\u{1B}[<u", "\u{1B}[>31u"])
        #expect(terminal.keyboardEnhancement == .requested)
    }

    @Test("Nothing is popped or pushed on a terminal that never took the protocol")
    func noPopWithoutAPush() {
        let (terminal, script) = makeTerminal(reads: [Self.fence])
        terminal.negotiateKeyboardEnhancement(timeout: 5)
        terminal.popKeyboardFlags()
        terminal.repushKeyboardFlags()
        #expect(script.sent == [Self.query])
    }

    @Test("A keystroke typed during the exchange reaches the parser; the replies do not")
    func keystrokesHandedBack() {
        let (terminal, _) = makeTerminal(reads: ["q\u{1B}[?0u" + Self.fence, "\u{1B}[?31u" + Self.fence + "x"])
        terminal.negotiateKeyboardEnhancement(timeout: 5)
        var events: [TerminalInput] = []
        while let event = terminal.readEvent() { events.append(event) }
        #expect(events == [.key(KeyEvent(character: "q")), .key(KeyEvent(character: "x"))])
    }

    @Test("The reply is told apart from a DA1 answer, and from a key report")
    func replyShapes() {
        #expect(KeyboardProtocolQuery.flags(in: Array("\u{1B}[?31u".utf8)) == .requested)
        #expect(KeyboardProtocolQuery.flags(in: Array(Self.fence.utf8)) == nil)
        #expect(KeyboardProtocolQuery.flags(in: Array("\u{1B}[97;5u".utf8)) == nil)
        #expect(KeyboardProtocolQuery.sawFence(Array(Self.fence.utf8)))
        #expect(!KeyboardProtocolQuery.sawFence(Array("\u{1B}[?31u".utf8)))
    }

    @Test("TUIKIT_KEYBOARD_PROTOCOL=0 keeps TUIkit from asking; anything else lets it")
    func environmentOptOut() {
        #expect(!Terminal.keyboardProtocolAllowed(environment: ["TUIKIT_KEYBOARD_PROTOCOL": "0"]))
        #expect(Terminal.keyboardProtocolAllowed(environment: ["TUIKIT_KEYBOARD_PROTOCOL": "1"]))
        #expect(Terminal.keyboardProtocolAllowed(environment: [:]))
    }

    // MARK: - What the app is told

    @Test("Which enhancements a terminal took decides what it reports")
    func reportingFromFlags() {
        #expect(KeyboardReporting(flags: []) == .legacy)
        #expect(!KeyboardReporting.legacy.isEnhanced)
        let all = KeyboardReporting(flags: .requested)
        #expect(all.isEnhanced && all.disambiguatesKeys && all.reportsShiftedKeys)
        #expect(all.reportsRepeats && all.reportsReleases)
        #expect(all.reportsModifierKeys && all.reportsLockStates && all.reportsNumericPad)
        let disambiguateOnly = KeyboardReporting(flags: .disambiguateEscapeCodes)
        #expect(disambiguateOnly.isEnhanced && disambiguateOnly.disambiguatesKeys)
        #expect(!disambiguateOnly.reportsReleases && !disambiguateOnly.reportsModifierKeys)
        #expect(!disambiguateOnly.reportsShiftedKeys)
    }

    @Test("The environment carries what the run loop negotiated, and the legacy answer by default")
    func environmentPublishing() {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        #expect(environment.keyboardReporting == .legacy)

        tui.keyboardReporting = KeyboardReporting(flags: .requested)
        environment.applyRuntimeServices(from: tui)
        #expect(environment.keyboardReporting.reportsReleases)
    }
}
