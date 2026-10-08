//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScriptedTerminalOutput.swift
//
//  A real `Terminal` whose output is captured rather than written to stdout,
//  for the tests that pin the bytes it sends: the modes raw mode turns on and
//  off, a frame and its synchronized-output markers, the frame dump's notice.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit
@testable import TUIkitFoundation

/// What a scripted terminal was sent, one entry per write.
@MainActor
final class ScriptedTerminalOutput {
    /// Each write the terminal made, in order: one per immediate write, one
    /// (or, where a frame is flushed in parts, more) per frame.
    private(set) var writes: [String] = []

    /// Every byte sent, as one string.
    var bytes: String { writes.joined() }

    /// Forgets what was sent so far, so a test can look at one step alone.
    func clear() { writes.removeAll() }

    fileprivate func record(_ write: String) { writes.append(write) }

    /// A terminal that writes here instead of stdout, reads nothing, and
    /// leaves the process's termios and signal handlers alone (see
    /// `Terminal.exchangeTransport`).
    ///
    /// - Parameter environment: What the terminal reads its `TUIKIT_*`
    ///   switches from: none set, unless a test sets one.
    static func terminal(environment: [String: String] = [:]) -> (Terminal, ScriptedTerminalOutput) {
        let terminal = Terminal(environment: environment)
        let output = ScriptedTerminalOutput()
        terminal.readSource = { _ in 0 }
        terminal.exchangeTransport = .init(
            send: { [output] in output.record($0) }, waitForInput: { _ in false })
        return (terminal, output)
    }
}
