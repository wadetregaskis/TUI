//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalHandOff.swift
//
//  Where a running app hands its terminal to another program and takes it
//  back: the handler its run loop installs, and the depth that makes a nested
//  hand-off run its closure as it is.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// A context's way of handing the terminal to another program and taking it
/// back (``HandOffTerminalAction``).
///
/// Holds a handler only while an app's run loop runs (`AppRunner`, in
/// `TUIApp`, which has the terminal and installs it): a headless app, a test's,
/// a snapshot and WebAssembly's host have nothing to hand back, so their
/// contexts' never gets one, and a closure handed to it just runs. The type
/// lives here, below `TUIApp`, so that the action can be read from any view's
/// environment on every platform, Windows included, where `TUIApp` does not
/// build.
///
/// One per ``TUIContext``, as the bell is (``TerminalBell``), so two apps in
/// one process (a test suite) do not reach each other's terminal.
package final class TerminalHandOff {
    /// Hands the terminal over, runs `body`, and takes the terminal back:
    /// installed by the run loop for its run, and `nil` everywhere else.
    package typealias Handler = @MainActor (_ body: () -> Void) -> Void

    /// The run loop's handler, while it runs.
    package var handler: Handler?

    /// Whether a hand-off is under way: a call made inside one runs its
    /// closure as it is, the terminal being the other program's already.
    package private(set) var isHandedOff = false

    package init() {}

    /// Runs `body` with the terminal handed over, where a running app has one
    /// to hand, and returns what it returns or throws what it throws, the
    /// terminal taken back either way.
    ///
    /// Outside a running app, and inside a hand-off already under way, it runs
    /// `body` as it is.
    @MainActor
    package func run<Value, Failure: Error>(_ body: () throws(Failure) -> Value) throws(Failure) -> Value {
        guard let handler, !isHandedOff else { return try body() }
        isHandedOff = true
        defer { isHandedOff = false }
        // The handler takes a closure that neither returns nor throws, so it
        // need not be generic: what `body` gives, value or error, is kept here
        // and given once the terminal is back.
        var outcome: Result<Value, Failure>?
        handler { outcome = Result(catching: body) }
        // A handler that never ran `body` would be a bug of TUI's; running it
        // here, still marked as handed off, keeps the caller's promise rather
        // than stopping the app.
        guard let outcome else { return try body() }
        return try outcome.get()
    }
}

private struct TerminalHandOffKey: EnvironmentKey {
    static var defaultValue: TerminalHandOff? { nil }
}

extension EnvironmentValues {
    /// The running app's hand-off — its context's, handed down each frame
    /// (`applyRuntimeServices(from:)`) — or `nil` where no context's services
    /// reached.
    package var terminalHandOff: TerminalHandOff? {
        get { self[TerminalHandOffKey.self] }
        set { self[TerminalHandOffKey.self] = newValue }
    }
}
