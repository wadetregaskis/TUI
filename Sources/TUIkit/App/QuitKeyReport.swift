//  🖥️ TUIkit — Terminal UI Kit for Swift
//  QuitKeyReport.swift
//
//  What the user's quit key does when it arrives as a key report rather than
//  as the byte the terminal driver acts on.
//
//  Created by Wade Tregaskis
//  License: MIT

// Signals are POSIX; wasip1 has no process group to signal, and no driver to
// stand in for.
#if !canImport(WASILibc)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The user's quit key, ⌃\\, reported by the kitty keyboard protocol
/// (`CSI 92;5u`) instead of sent as the 0x1C the terminal driver turns into
/// `SIGQUIT`: what `InputHandler` does in the driver's place
/// (`InputHandler.onQuitKey`).
///
/// It does what the driver does for the byte, so the key quits the same way
/// whichever encoding the terminal sends it in: `SIGQUIT` to every process in
/// the app's process group. The driver signals the terminal's foreground
/// process group, which is the app's while it has the terminal; a child the
/// app started (a helper, a pager it waits on) is in it, and ends with it.
/// `raise` would signal only this process and leave the children running.
enum QuitKeyReport {

    /// Quits as the driver would: `SIGQUIT` to the process group.
    ///
    /// - Parameter signal: `kill(2)`, unless a test hands in another that
    ///   records what it was asked.
    static func quit(signal: (pid_t, Int32) -> Int32 = { kill($0, $1) }) {
        // Process ID 0: every process in the caller's process group.
        _ = signal(0, SIGQUIT)
    }
}

#endif
