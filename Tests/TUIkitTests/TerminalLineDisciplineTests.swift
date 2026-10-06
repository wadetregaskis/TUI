//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalLineDisciplineTests.swift
//
//  The termios raw mode runs in, computed from the user's: every signal
//  character off but the quit key, which stays as the user had it.
//
//  Created by Wade Tregaskis
//  License: MIT

#if !canImport(WASILibc)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

import Testing

@testable import TUIkit

@Suite("Raw mode's line discipline")
struct TerminalLineDisciplineTests {
    static let off = Terminal.disabledControlCharacter

    /// A shell's cooked termios: echo, canonical input, signals and the
    /// extensions on; the usual control characters.
    static func cooked(quit: cc_t = 0x1C, signals: Bool = true) -> termios {
        var attributes = termios()
        attributes.c_lflag = tcflag_t(ECHO | ECHOE | ICANON | IEXTEN) | (signals ? tcflag_t(ISIG) : 0)
        attributes.c_iflag = tcflag_t(ICRNL | IXON | BRKINT)
        attributes.c_oflag = tcflag_t(OPOST)
        set(&attributes, [
            (VINTR, 0x03), (VQUIT, quit), (VSUSP, 0x1A), (VEOF, 0x04), (VERASE, 0x7F), (VMIN, 1), (VTIME, 0),
        ])
        #if canImport(Darwin)
            set(&attributes, [(VDSUSP, 0x19), (VSTATUS, 0x14)])
        #endif
        return attributes
    }

    static func set(_ attributes: inout termios, _ values: [(Int32, cc_t)]) {
        withUnsafeMutablePointer(to: &attributes.c_cc) { pointer in
            pointer.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { buffer in
                for (index, value) in values { buffer[Int(index)] = value }
            }
        }
    }

    static func character(_ attributes: termios, _ index: Int32) -> cc_t {
        var copy = attributes
        return withUnsafeBytes(of: &copy.c_cc) { $0[Int(index)] }
    }

    private static func has(_ attributes: termios, _ flag: Int32) -> Bool {
        attributes.c_lflag & tcflag_t(flag) != 0
    }

    /// The owner's request (2026-10-05): `⌃\` quits again, as a real SIGQUIT,
    /// even when the app hangs — so the driver, not the app, has to take it,
    /// and `ISIG` stays on. Every other signal character goes, so ⌃C and ⌃Z
    /// stay keys. Until then raw mode cleared `ISIG`, and `⌃\` arrived as a
    /// byte nothing read.
    @Test("Raw mode keeps signals on with only the quit key live, as the user had it")
    func onlyTheQuitKeyIsLive() {
        let raw = Terminal.rawModeAttributes(from: Self.cooked())
        #expect(Self.has(raw, ISIG), "the driver still turns the quit key into SIGQUIT")
        #expect(!Self.has(raw, ECHO) && !Self.has(raw, ICANON) && !Self.has(raw, IEXTEN))
        #expect(Self.character(raw, VQUIT) == 0x1C)
        #expect(Self.character(raw, VINTR) == Self.off, "⌃C is a key")
        #expect(Self.character(raw, VSUSP) == Self.off, "⌃Z is a key")
        #if canImport(Darwin)
            #expect(Self.character(raw, VDSUSP) == Self.off, "⌃Y is a key")
            #expect(Self.character(raw, VSTATUS) == Self.off, "⌃T is a key")
        #endif
        #expect(Self.character(raw, VMIN) == 0 && Self.character(raw, VTIME) == 0)
        #expect(Self.character(raw, VEOF) == 0x04 && Self.character(raw, VERASE) == 0x7F, "the rest untouched")
        #expect(raw.c_iflag & tcflag_t(IXON | ICRNL | BRKINT) == 0)
        #expect(raw.c_oflag & tcflag_t(OPOST) == 0)
        #expect(raw.c_cflag & tcflag_t(CS8) == tcflag_t(CS8))
    }

    @Test("A quit key the user turned off, or moved, or signals the user turned off, stay as they were")
    func theUsersQuitKeyIsRespected() {
        let undefined = Terminal.rawModeAttributes(from: Self.cooked(quit: Self.off))
        #expect(Self.character(undefined, VQUIT) == Self.off, "stty quit undef")
        let moved = Terminal.rawModeAttributes(from: Self.cooked(quit: 0x18))
        #expect(Self.character(moved, VQUIT) == 0x18, "stty quit ^X")
        let noSignals = Terminal.rawModeAttributes(from: Self.cooked(signals: false))
        #expect(!Self.has(noSignals, ISIG), "stty -isig")
    }

    /// An app that binds the quit key's chord has it masked: the byte then
    /// arrives as a key (`Terminal.maskQuitKey(for:)`). Signals stay on, so a
    /// mask lifted is the driver's quit again, and the rest is raw mode's.
    @Test("Masking the quit key turns it off too, signals still on")
    func maskedQuitKey() {
        let masked = Terminal.rawModeAttributes(from: Self.cooked(), maskingQuitKey: true)
        #expect(Self.character(masked, VQUIT) == Self.off)
        #expect(Self.has(masked, ISIG))
        var unmasked = Terminal.rawModeAttributes(from: Self.cooked())
        Self.set(&unmasked, [(VQUIT, Self.off)])
        #expect(Self.same(masked, unmasked), "nothing else differs")
    }

    /// Whether two termios hold the same flags, characters and speeds —
    /// field by field, never the struct's bytes, whose padding is not
    /// initialised.
    static func same(_ lhs: termios, _ rhs: termios) -> Bool {
        lhs.c_iflag == rhs.c_iflag && lhs.c_oflag == rhs.c_oflag && lhs.c_cflag == rhs.c_cflag
            && lhs.c_lflag == rhs.c_lflag && cfgetispeed([lhs]) == cfgetispeed([rhs])
            && cfgetospeed([lhs]) == cfgetospeed([rhs])
            && (0..<Int32(NCCS)).allSatisfy { character(lhs, $0) == character(rhs, $0) }
    }

    /// `_POSIX_VDISABLE` differs by system, not by C library: a BSD's is
    /// 0xFF, on whichever C library Swift imports there. So it is asked of
    /// the system (`fpathconf`), and only a system that does not say falls
    /// back to the platform's own.
    @Test("The value that turns a control character off is the system's answer, or the platform's own")
    func disabledCharacterIsAsked() {
        #expect(Terminal.disabledControlCharacter(answer: 0xFF) == 0xFF, "Darwin's and the BSDs' answer")
        #expect(Terminal.disabledControlCharacter(answer: 0) == 0, "Linux's answer")
        #if canImport(Darwin)
            #expect(Terminal.disabledControlCharacter(answer: -1) == 0xFF, "no answer: Darwin's own")
        #else
            #expect(Terminal.disabledControlCharacter(answer: -1) == 0, "no answer: Linux's own")
        #endif
        let asked = fpathconf(STDIN_FILENO, Int32(_PC_VDISABLE))
        if asked >= 0 { #expect(Int(Self.off) == asked, "standard input's own answer") }
    }
}

#endif
