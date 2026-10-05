//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Terminal+KeyboardProtocol.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(WASILibc)
import WASILibc
#endif

// MARK: - Asking whether the terminal speaks the kitty keyboard protocol

/// The exchange that asks a terminal whether it speaks the kitty keyboard
/// protocol, and the sequences that turn it on and off.
///
/// The protocol's own detection, from its specification
/// (<https://sw.kovidgoyal.net/kitty/keyboard-protocol/>): ask for the current
/// flags with `CSI ? u` and fence it with a request every terminal answers. A
/// terminal that answers the fence without answering `CSI ? u` does not speak
/// the protocol. The specification's fence is Primary Device Attributes,
/// `CSI c`; any answered request behind the question serves, since a terminal
/// answers in order. So the first question rides on the startup colour
/// exchange (``question``, fenced by its `CSI 5 n`), which every app already
/// pays for, and a terminal that does not speak the protocol pays nothing
/// more. Only the questions after a push (``request``) take a round trip of
/// their own, on the terminals that answered.
///
/// `CSI ? u` carries a `?` and no intermediate byte, the shape measured clean on
/// Apple Terminal 455.1 (`Documentation/Terminal-compatibility.md`, "Asking the
/// terminal — Device Attributes"). It is not sent there anyway: Apple Terminal
/// does not speak the protocol, so the round trip could only cost.
///
/// The flags are pushed (`CSI > flags u`), not set, and popped (`CSI < u`) on
/// the way out, so whatever the shell had is what it gets back. The terminal
/// keeps a separate stack per screen, and TUIkit pushes on the alternate screen,
/// so even a process that dies without popping leaves the shell's own screen's
/// keyboard as it was.
enum KeyboardProtocolQuery {

    /// The question alone, for an exchange that brings its own fence: the
    /// startup colour exchange's (`Terminal.askColors(isTmux:timeout:askingKeyboardFlags:)`).
    static let question = "\u{1B}[?u"

    /// The question and its fence, in one write: what is asked after a push.
    static let request = question + "\u{1B}[c"

    /// Pushes `flags` onto the terminal's stack.
    static func push(_ flags: KittyKeyboardFlags) -> String {
        "\u{1B}[>\(flags.rawValue)u"
    }

    /// Pops the entry this process pushed.
    static let pop = "\u{1B}[<u"

    /// The flags a `CSI ? flags u` reply in `bytes` reports, or `nil` when
    /// there is none — which, once the fence is in, means the terminal does
    /// not speak the protocol.
    static func flags(in bytes: [UInt8]) -> KittyKeyboardFlags? {
        var found: KittyKeyboardFlags?
        forEachSequence(in: bytes) { sequence in
            guard isReply(sequence) else { return }
            let digits = sequence.dropFirst(3).dropLast()
            // `ASCIIDecimal`, which declines a sign or an overflow: the reply
            // comes off the wire.
            if let value = ASCIIDecimal.value(of: digits) {
                found = KittyKeyboardFlags(rawValue: value)
            }
        }
        return found
    }

    /// Whether `bytes` holds the fence's reply, a Primary Device Attributes
    /// answer.
    static func sawFence(_ bytes: [UInt8]) -> Bool {
        var seen = false
        forEachSequence(in: bytes) { if isFence($0) { seen = true } }
        return seen
    }

    /// Whether one complete escape sequence is the answer to `CSI ? u`:
    /// `CSI ? digits u`.
    static func isReply(_ sequence: ArraySlice<UInt8>) -> Bool {
        isPrivateCSI(sequence, final: 0x75)  // 'u'
    }

    /// Whether one complete escape sequence is a Primary Device Attributes
    /// reply, `CSI ? … c`: the fence.
    static func isFence(_ sequence: ArraySlice<UInt8>) -> Bool {
        isPrivateCSI(sequence, final: 0x63)  // 'c'
    }

    /// Whether `sequence` is `CSI ?`, then digits and `;`, then `final`.
    private static func isPrivateCSI(_ sequence: ArraySlice<UInt8>, final: UInt8) -> Bool {
        guard sequence.count >= 4, sequence.first == 0x1B,
            sequence[sequence.startIndex + 1] == 0x5B, sequence[sequence.startIndex + 2] == 0x3F,
            sequence.last == final
        else { return false }
        return sequence.dropFirst(3).dropLast().allSatisfy { (0x30...0x39).contains($0) || $0 == 0x3B }
    }

    /// Calls `body` with each complete CSI sequence in `bytes`.
    private static func forEachSequence(in bytes: [UInt8], _ body: (ArraySlice<UInt8>) -> Void) {
        var index = 0
        while index + 1 < bytes.count {
            guard bytes[index] == 0x1B, bytes[index + 1] == 0x5B else {
                index += 1
                continue
            }
            var cursor = index + 2
            while cursor < bytes.count, !(0x40...0x7E).contains(bytes[cursor]) { cursor += 1 }
            guard cursor < bytes.count else { return }
            body(bytes[index...cursor])
            index = cursor + 1
        }
    }
}

// MARK: - Negotiating, pushing and popping

extension Terminal {

    /// Turns on the kitty keyboard protocol if the terminal speaks it, and
    /// records which of its enhancements the terminal took.
    ///
    /// The first question has been asked already, on the startup colour
    /// exchange (``KeyboardProtocolQuery/question``), and its answer is
    /// ``keyboardProtocolAnswer``: so call this after
    /// `TerminalClient.detectColors(using:)`. A terminal that answered gets
    /// ``KittyKeyboardFlags/requested`` pushed, and is asked again, because a
    /// terminal may implement only some of the enhancements and the second
    /// answer says which it took. A terminal that takes "report all keys as
    /// escape codes" but not "report associated text" would deliver typed
    /// text as bare key codes, losing every dead key, compose sequence and
    /// non-US layout, so then the push is replaced by one without the former.
    ///
    /// Costs nothing on a terminal that does not speak the protocol and one
    /// round trip on one that does (two where the push is replaced). Skipped
    /// where there is no TTY in raw mode, and wherever
    /// ``asksKeyboardProtocol`` is `false`.
    func negotiateKeyboardProtocol(timeout: Double = 0.5) {
        guard isatty(STDIN_FILENO) == 1, isRawMode, asksKeyboardProtocol else { return }
        negotiateKeyboardEnhancement(firstAnswer: keyboardProtocolAnswer, timeout: timeout)
    }

    /// Whether the startup exchange asks this terminal about the protocol at
    /// all: not Apple Terminal, which does not speak it, and not where
    /// `TUIKIT_KEYBOARD_PROTOCOL=0` is set — the user's way out, should a
    /// terminal claim the protocol and then encode keys in a way TUIkit
    /// misreads.
    var asksKeyboardProtocol: Bool {
        !TerminalHost.isAppleTerminal
            && Self.keyboardProtocolAllowed(environment: ProcessInfo.processInfo.environment)
    }

    /// Whether the environment lets TUIkit ask for the protocol at all: yes,
    /// unless `TUIKIT_KEYBOARD_PROTOCOL` is `0`.
    nonisolated static func keyboardProtocolAllowed(environment: [String: String]) -> Bool {
        environment["TUIKIT_KEYBOARD_PROTOCOL"] != "0"
    }

    /// The negotiation behind ``negotiateKeyboardProtocol(timeout:)``, without
    /// its guards, so a test can run it through ``readSource`` and
    /// ``exchangeTransport``.
    ///
    /// - Parameter firstAnswer: What the terminal answered to the first
    ///   question, on the startup exchange; `nil` when it did not, and then
    ///   nothing is pushed.
    ///
    /// ## An answer after the push that does not come
    ///
    /// The terminal answered the first question, so it speaks the protocol,
    /// and the push has been sent: from here on the terminal encodes keys by
    /// whatever it took of it. An answer to the question after the push that
    /// misses the window (a hiccup over ssh) says nothing about what it took,
    /// and reading keys as legacy bytes then would be the one wrong guess that
    /// costs everything — Return, `q` and Ctrl-C all arrive as `CSI … u`, which
    /// the legacy parser drops, and the app can be neither typed at nor quit.
    /// So a missing answer is taken as the push: keys are read in the
    /// protocol's grammar, which decodes a key whichever enhancements the
    /// terminal took, and `\.keyboardReporting` claims what was asked for.
    /// The late answer arrives as input afterwards, and the parser drops it as
    /// it drops any reply.
    func negotiateKeyboardEnhancement(firstAnswer: KittyKeyboardFlags?, timeout: Double) {
        guard firstAnswer != nil else { return }
        var pushed = KittyKeyboardFlags.requested
        sendToTerminal(KeyboardProtocolQuery.push(pushed))
        var granted = askKeyboardFlags(timeout: timeout) ?? pushed
        if granted.contains(.reportAllKeysAsEscapeCodes), !granted.contains(.reportAssociatedText) {
            pushed = granted.subtracting(.reportAllKeysAsEscapeCodes)
            sendToTerminal(KeyboardProtocolQuery.pop + KeyboardProtocolQuery.push(pushed))
            granted = askKeyboardFlags(timeout: timeout) ?? pushed
        }
        negotiatedKeyboardFlags = (pushed: pushed, granted: granted.intersection(pushed))
        noteKeyboardFlagsPushed()
    }

    /// Asks for the current flags; `nil` when the terminal answered only the
    /// fence, or nothing.
    func askKeyboardFlags(timeout: Double) -> KittyKeyboardFlags? {
        let collected = fencedExchange(
            request: KeyboardProtocolQuery.request, timeout: timeout,
            sawFence: KeyboardProtocolQuery.sawFence)
        handBackUnconsumed(
            from: collected, isReply: KeyboardProtocolQuery.isReply,
            isFence: KeyboardProtocolQuery.isFence)
        return KeyboardProtocolQuery.flags(in: collected)
    }

    /// Pushes the negotiated flags again, on the way back from a suspend.
    /// Does nothing if they were never negotiated or are already pushed.
    func repushKeyboardFlags() {
        guard let negotiatedKeyboardFlags, !keyboardFlagsPushed else { return }
        sendToTerminal(KeyboardProtocolQuery.push(negotiatedKeyboardFlags.pushed))
        noteKeyboardFlagsPushed()
    }

    /// Pops the flags this process pushed, if it pushed any and has not
    /// popped them yet. On exit and on the way into a suspend, while the
    /// alternate screen whose stack they were pushed on is still showing.
    func popKeyboardFlags() {
        guard keyboardFlagsPushed else { return }
        sendToTerminal(KeyboardProtocolQuery.pop)
        keyboardFlagsPushed = false
        keyboardEnhancement = []
        keyboardMemory = KittyKeyMemory()
        armSignalRestore()
    }

    /// The bookkeeping of a push: the parser reads the terminal's keys in the
    /// protocol's grammar, a pop is owed, and a signal pays it.
    private func noteKeyboardFlagsPushed() {
        keyboardFlagsPushed = true
        keyboardEnhancement = negotiatedKeyboardFlags?.granted ?? []
        armSignalRestore()
    }

    /// Writes a mode change to the terminal, or to the scripted transport a
    /// test installed.
    private func sendToTerminal(_ sequence: String) {
        if let exchangeTransport {
            exchangeTransport.send(sequence)
        } else {
            writeImmediate(sequence)
        }
    }
}
