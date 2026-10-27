//  🖥️ TUI — A Terminal UI framework for Swift
//  ScriptedTerminalOutput.swift
//
//  A real `Terminal` whose output is captured rather than written to stdout,
//  for the tests that pin the bytes it sends: the modes raw mode turns on and
//  off, a frame and its synchronized-output markers, the frame dump's notice;
//  and what it would owe a fatal signal, each time it arms that debt.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

/// What a scripted terminal was sent, one entry per write.
@MainActor
final class ScriptedTerminalOutput {
    /// Each write the terminal made, in order: one per immediate write, one
    /// (or, where a frame is flushed in parts, more) per frame.
    private(set) var writes: [String] = []

    /// Every byte sent, as one string.
    var bytes: String { writes.joined() }

    /// One arming of what a fatal signal would be owed
    /// (`Terminal.armSignalRestore()`), which the process's handler would
    /// have been handed.
    struct Arming {
        /// What any other fatal signal would write (`Terminal.signalDebt`).
        let signalDebt: String
        /// What a `SIGQUIT` would write (`Terminal.quitDebt`).
        let quitDebt: String
        /// How many of ``writes`` were made before it: a debt armed before a
        /// write is owed while it goes out, one armed after it is not.
        let afterWrites: Int
    }

    /// Each time the terminal armed the debt, in order.
    private(set) var armings: [Arming] = []

    /// What a `SIGTERM` would write now: the debt last armed, or `nil` where
    /// none was since the last ``clear()``.
    var armedDebt: String? { armings.last?.signalDebt }

    /// Forgets what was sent and armed so far, so a test can look at one step
    /// alone.
    func clear() {
        writes.removeAll()
        armings.removeAll()
    }

    fileprivate func record(_ write: String) { writes.append(write) }

    fileprivate func recordArming(signalDebt: String, quitDebt: String) {
        armings.append(Arming(signalDebt: signalDebt, quitDebt: quitDebt, afterWrites: writes.count))
    }

    /// A terminal that writes here instead of stdout, reads nothing, and
    /// leaves the process's termios and signal handlers alone, arming its
    /// debt here instead (see `Terminal.exchangeTransport`).
    ///
    /// - Parameter environment: What the terminal reads its `TUI_*`
    ///   switches from: none set, unless a test sets one.
    static func terminal(environment: [String: String] = [:]) -> (Terminal, ScriptedTerminalOutput) {
        let terminal = Terminal(environment: environment)
        let output = ScriptedTerminalOutput()
        terminal.readSource = { _ in 0 }
        terminal.exchangeTransport = .init(
            send: { [output] in output.record($0) }, waitForInput: { _ in false },
            armSignalRestore: { [output] in output.recordArming(signalDebt: $0, quitDebt: $1) })
        return (terminal, output)
    }
}

#endif
