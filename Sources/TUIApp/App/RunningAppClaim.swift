//  🖥️ TUI — A Terminal UI framework for Swift
//  RunningAppClaim.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - One app per process

/// Refuses a second app run while one is running in the same process.
///
/// One app runs per process, and everything a run touches outside itself is
/// the process's, one of each: standard input and its termios, the signal
/// handlers (`SignalManager`) and the debt a fatal signal pays
/// (`FatalSignalTerminalRestore`). A second run started beside the first —
/// another `App.main()` from a task, say — would read the same keystrokes,
/// and the first teardown would put the shell's termios back, disarm the
/// debt and stop the signal sources under the other, still running, which
/// would then crash or be killed with the terminal raw and nothing owed.
/// Nothing in the type system stops that, so the run loop claims the process
/// as it starts (``claim()``) and gives it back as it ends (``release()``):
/// one run after another is fine, two at once stops at a precondition naming
/// the rule.
///
/// A flag, not a service: nothing reads it to find anything, and it holds
/// no state an app or a test could see but whether a run is under way.
@MainActor
enum RunningAppClaim {
    /// Whether a run loop is running in this process.
    private(set) static var isClaimed = false

    /// Claims the process for a run, or stops if a run already has it.
    static func claim() {
        precondition(
            !isClaimed,
            """
            TUI runs one app per process, and an app is already running in this one. \
            A second run would share its terminal, signal handlers and terminal-restore debt, \
            and each one's teardown would undo the other's. Let the first run end \
            (`@Environment(\\.dismiss)`) before starting another.
            """)
        isClaimed = true
    }

    /// Gives the process back as a run ends.
    static func release() {
        isClaimed = false
    }
}
