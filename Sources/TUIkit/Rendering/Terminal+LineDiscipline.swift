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
    /// `_POSIX_VDISABLE`, which Swift does not import: `0xFF` on Darwin and
    /// the BSDs, NUL on Linux (glibc and musl alike).
    nonisolated static let disabledControlCharacter: cc_t = {
        #if canImport(Darwin)
            0xFF
        #else
            0
        #endif
    }()

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
    nonisolated static func rawModeAttributes(from original: termios) -> termios {
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
                #if canImport(Darwin)
                    buffer[Int(VDSUSP)] = disabledControlCharacter
                    buffer[Int(VSTATUS)] = disabledControlCharacter
                #endif
            }
        }
        return raw
    }
}

#endif
