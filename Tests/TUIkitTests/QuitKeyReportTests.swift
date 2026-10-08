//  🖥️ TUIkit — Terminal UI Kit for Swift
//  QuitKeyReportTests.swift
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

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation

/// What the user's quit key does when the kitty keyboard protocol reports it
/// as a key: what the terminal driver does for its byte. The signal itself is
/// not sent — it would end the test process — so `kill` is handed in, and what
/// it was asked is checked; and the wait for it to end the process, which
/// would hold the test for ever. `Tools/Smoke/quit_key_smoke.py` sends it for
/// real.
@Suite("The quit key's report")
struct QuitKeyReportTests {

    /// The driver signals the terminal's foreground process group, the app's,
    /// so a child the app started ends with it; `raise` signalled only the app.
    @Test("A quit-key report sends SIGQUIT to the whole process group, as the driver does")
    func signalsTheProcessGroup() {
        var asked: [(process: pid_t, signal: Int32)] = []
        QuitKeyReport.quit(
            synchronize: {},
            signal: { process, signal in
                asked.append((process, signal))
                return 0
            },
            awaitTheEnd: {})
        #expect(asked.count == 1)
        #expect(asked.first?.process == 0, "process ID 0: every process in the caller's group")
        #expect(asked.first?.signal == SIGQUIT)
    }

    /// The app is still reading its input when the report arrives, so it can
    /// do what the signal's handler cannot: flush a setting stored a moment
    /// before, which is saved asynchronously and would go with the process.
    @Test("A quit-key report saves the stored settings before it signals")
    func savesSettingsFirst() {
        var steps: [String] = []
        QuitKeyReport.quit(
            synchronize: { steps.append("synchronize") },
            signal: { _, _ in
                steps.append("signal")
                return 0
            },
            awaitTheEnd: {})
        #expect(steps == ["synchronize", "signal"])
    }

    /// `kill(0, …)` signals processes, not this thread, as `raise` did: the
    /// handler may run on another thread after `kill` returns. Meanwhile this
    /// one would go on dispatching the rest of the input batch — a Return
    /// after the ⌃\ running its action — and maybe write a frame onto the
    /// shell's screen after the handler left the alternate one. So once the
    /// signal is sent, the thread waits for it to end the process (round 6).
    @Test("After the signal, nothing more runs on the quitting thread: it waits for the signal to end the process")
    func waitsForTheSignal() {
        var steps: [String] = []
        QuitKeyReport.quit(
            synchronize: { steps.append("synchronize") },
            signal: { _, _ in
                steps.append("signal")
                return 0
            },
            awaitTheEnd: { steps.append("wait") })
        #expect(steps == ["synchronize", "signal", "wait"])

        steps = []
        QuitKeyReport.quit(
            synchronize: {},
            signal: { _, _ in
                steps.append("signal")
                return -1
            },
            awaitTheEnd: { steps.append("wait") })
        #expect(steps == ["signal"], "a signal not sent ends nothing: no wait")
    }

    /// The wait is for a signal that ends the process: TUIkit's handler,
    /// which ends by the default action, or the default itself. Where the app
    /// ignores `SIGQUIT`, or put a handler of its own in after TUIkit's, the
    /// signal may end nothing, and a wait for it would hang the app: there is
    /// none, and the loop goes on, as after the driver's ⌃\.
    @Test("It waits only where SIGQUIT ends the process: TUIkit's handler or the default")
    func waitsOnlyWhereTheSignalEnds() {
        let foreign: @convention(c) (Int32) -> Void = { _ in }
        #expect(FatalSignalTerminalRestore.endsTheProcess(handlerAddress: 0), "SIG_DFL")
        #expect(FatalSignalTerminalRestore.endsTheProcess(handlerAddress: FatalSignalTerminalRestore.handlerAddress))
        #expect(!FatalSignalTerminalRestore.endsTheProcess(handlerAddress: 1), "SIG_IGN")
        #expect(!FatalSignalTerminalRestore.endsTheProcess(handlerAddress: unsafeBitCast(foreign, to: Int.self)))
    }
}

#endif
