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

@testable import TUIkit

/// What the user's quit key does when the kitty keyboard protocol reports it
/// as a key: what the terminal driver does for its byte. The signal itself is
/// not sent — it would end the test process — so `kill` is handed in, and what
/// it was asked is checked. `Tools/Smoke/quit_key_smoke.py` sends it for real.
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
            })
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
            })
        #expect(steps == ["synchronize", "signal"])
    }
}

#endif
