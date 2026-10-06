//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Terminal+LineDiscipline.swift
//
//  The termios raw mode runs in: what the kernel's line discipline is left
//  to do while the app reads its keys — one thing, turning the user's quit
//  key into SIGQUIT.
//
//  Created by Wade Tregaskis
//  License: MIT

// wasip1 has no termios: a wasm program is handed a stream of bytes, with no
// line discipline in front of it.
#if !canImport(WASILibc)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

extension Terminal {
    /// The value that turns a control character off, POSIX's
    /// `_POSIX_VDISABLE`, which Swift does not import: asked of the system for
    /// standard input, the terminal raw mode is set on (`fpathconf` with
    /// `_PC_VDISABLE`), rather than assumed per platform. Darwin and the BSDs
    /// answer `0xFF`, Linux NUL (glibc and musl alike), and NUL is an
    /// ordinary character on a BSD (⌃@): a guess by C library would have
    /// made it a live signal character there.
    nonisolated static let disabledControlCharacter: cc_t = disabledControlCharacter(
        answer: fpathconf(STDIN_FILENO, Int32(_PC_VDISABLE)))

    /// `fpathconf`'s answer for `_PC_VDISABLE` as a control character, or,
    /// where the system gave none (`-1`: standard input is no terminal, as
    /// under a test runner), the value of the platforms TUIkit runs on:
    /// `0xFF` on Darwin, NUL on Linux.
    nonisolated static func disabledControlCharacter(answer: Int) -> cc_t {
        if let character = cc_t(exactly: answer) { return character }
        #if canImport(Darwin)
            return 0xFF
        #else
            return 0
        #endif
    }

    /// The line discipline raw mode runs in, made from the user's own,
    /// `original`, which the teardown puts back exactly.
    ///
    /// - Echo, canonical input and the extensions (`ECHO`, `ICANON`,
    ///   `IEXTEN`) off: each key is read as it comes, unechoed, with no line
    ///   editing and no literal-next. Input and output processing off as
    ///   before: no flow control (`IXON`, so ⌃S and ⌃Q are keys), no CR to
    ///   NL, no break or parity handling, no stripping, no output
    ///   translation (`OPOST`), eight-bit characters; and a read returns at
    ///   once (`VMIN` and `VTIME` 0).
    /// - Signals (`ISIG`) left as the user had them, with every signal
    ///   character but the quit key turned off: ⌃C (`VINTR`) and ⌃Z
    ///   (`VSUSP`) arrive as keys — ⌃C an app's to bind, ⌃Z its undo — and
    ///   on Darwin so do ⌃Y (`VDSUSP`, the delayed suspend; a text control's
    ///   yank) and ⌃T (`VSTATUS`, which asks for `SIGINFO`; transpose).
    ///   Measured on Darwin 24.6, with `ICANON` and `IEXTEN` off those two
    ///   are inert anyway — ⌃T and ⌃Y arrive as keys and raise nothing either
    ///   way — so turning them off only means nothing rests on that.
    /// - The quit key (`VQUIT`) as the user had it: `⌃\` unless they changed
    ///   it. The driver turns it into `SIGQUIT` before the app reads a byte —
    ///   whatever the app is doing, hung included, and over ssh, where the
    ///   remote side's pseudo-terminal does the same — and the signal leaves
    ///   the terminal as a quit does (`FatalSignalTerminalRestore`). A key
    ///   the app can never bind, as in a shell. A user who turned it off
    ///   (`stty quit undef`), or `ISIG` with it (`stty -isig`), keeps it off;
    ///   one who moved it keeps theirs.
    ///
    /// - Parameters:
    ///   - original: The user's termios.
    ///   - maskingQuitKey: Whether the quit key is turned off too, for an app
    ///     that declares a binding its byte could be for
    ///     (``maskQuitKey(_:)``): its byte then arrives as a key, which the
    ///     input chain offers the app first and quits on itself where nothing
    ///     takes it.
    nonisolated static func rawModeAttributes(from original: termios, maskingQuitKey: Bool = false) -> termios {
        var raw = original
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_cflag |= tcflag_t(CS8)

        // Safe: termios.c_cc is a fixed-size array; rebinding to cc_t is valid.
        withUnsafeMutablePointer(to: &raw.c_cc) { pointer in
            pointer.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { buffer in
                buffer[Int(VMIN)] = 0
                buffer[Int(VTIME)] = 0
                buffer[Int(VINTR)] = disabledControlCharacter
                buffer[Int(VSUSP)] = disabledControlCharacter
                if maskingQuitKey { buffer[Int(VQUIT)] = disabledControlCharacter }
                #if canImport(Darwin)
                    buffer[Int(VDSUSP)] = disabledControlCharacter
                    buffer[Int(VSTATUS)] = disabledControlCharacter
                #endif
            }
        }
        return raw
    }

    /// The quit key `attributes` give the driver, as its byte — ⌃\'s 0x1C
    /// unless the user moved it — or `nil` where the driver raises no
    /// `SIGQUIT`: the key turned off (`stty quit undef`), or signals with it
    /// (`stty -isig`).
    nonisolated static func quitKeyByte(of attributes: termios) -> UInt8? {
        guard attributes.c_lflag & tcflag_t(ISIG) != 0 else { return nil }
        var copy = attributes
        let quit = withUnsafeBytes(of: &copy.c_cc) { $0[Int(VQUIT)] }
        return quit == disabledControlCharacter ? nil : quit
    }
}

// MARK: - Reaching the line discipline

/// The line discipline raw mode sets: reading it and setting it, which on a
/// terminal are `tcgetattr` and `tcsetattr` on standard input.
///
/// A seam for tests, which hand a scripted terminal one of their own
/// (`Terminal.scriptedLineDiscipline`): the process's own is whatever runs
/// the tests', and no test may change it.
struct LineDiscipline {
    /// The current attributes, or `nil` where there are none to read.
    let get: () -> termios?

    /// Sets the attributes, `when` as `tcsetattr` has it: `TCSANOW`, or
    /// `TCSAFLUSH` to throw away input not yet read.
    let set: (termios, Int32) -> Void

    /// Standard input's.
    static var standardInput: Self {
        Self(
            get: {
                var attributes = termios()
                return tcgetattr(STDIN_FILENO, &attributes) == 0 ? attributes : nil
            },
            set: { attributes, when in
                var attributes = attributes
                _ = tcsetattr(STDIN_FILENO, when, &attributes)
            })
    }
}

#endif
