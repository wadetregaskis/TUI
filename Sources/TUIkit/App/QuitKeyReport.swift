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
///
/// One thing first that the driver's quit cannot do: the settings an app
/// stored are flushed to disk. Here the app is still running its input loop,
/// so it can, and a value stored a moment before the key — saved on a queue,
/// asynchronously — would otherwise go with the process. The signal's handler
/// cannot: a flush is no async-signal-safe call. So by the byte (a terminal
/// without the protocol, or a hung app) such a value can be lost, as it can by
/// `kill -QUIT`.
///
/// And one thing after that the driver's quit needs no help with: nothing more
/// of the app runs on this thread (``awaitTheQuit()``). `kill` sends a signal
/// to processes, not to the calling thread as `raise` did, so its handler may
/// run on another thread after `kill` has returned — on Linux the main actor
/// need not run on the main thread.
enum QuitKeyReport {

    /// Quits as the driver would, the settings saved first: `SIGQUIT` to the
    /// process group, and then nothing more on this thread until it ends the
    /// process.
    ///
    /// - Parameters:
    ///   - synchronize: Flushes stored settings to disk:
    ///     `StorageDefaults.backend.synchronize()`, unless a test hands in
    ///     another.
    ///   - signal: `kill(2)`, unless a test hands in another that records
    ///     what it was asked.
    ///   - awaitTheEnd: Holds this thread until the signal ends the process:
    ///     ``awaitTheQuit()``, unless a test hands in another — the real one
    ///     would hold the test for ever, the signal not having been sent.
    static func quit(
        synchronize: () -> Void = { StorageDefaults.backend.synchronize() },
        signal: (pid_t, Int32) -> Int32 = { kill($0, $1) },
        awaitTheEnd: () -> Void = { Self.awaitTheQuit() }
    ) {
        synchronize()
        // Process ID 0: every process in the caller's process group.
        guard signal(0, SIGQUIT) == 0 else { return }
        awaitTheEnd()
    }

    /// Holds the calling thread until the `SIGQUIT` just sent ends the
    /// process, where it will (`FatalSignalTerminalRestore.quitEndsTheProcess()`);
    /// returns at once where it will not — ignored, or a handler of the app's
    /// own — and the input loop goes on, as after the driver's ⌃\ there.
    ///
    /// Why hold it: the kernel may hand the signal to any thread that does not
    /// block it, and the handler run there after `kill` returned. Until then
    /// this thread would go on — dispatching the rest of the batch of input
    /// the report came in (up to 128 events: a Return typed after the ⌃\
    /// would run its action), and maybe writing a frame, which after the
    /// handler's exit from the alternate screen lands on the shell's screen.
    /// Held, nothing more of the app runs here, and the handler ends the
    /// process wherever it runs: here, if no other thread takes the signal
    /// first, for it is unblocked for the wait. Another signal's handler
    /// ends a wait, not the hold.
    static func awaitTheQuit() {
        guard FatalSignalTerminalRestore.quitEndsTheProcess() else { return }
        var waiting = sigset_t()
        pthread_sigmask(SIG_SETMASK, nil, &waiting)
        sigdelset(&waiting, SIGQUIT)
        while true { sigsuspend(&waiting) }
    }
}

#endif
