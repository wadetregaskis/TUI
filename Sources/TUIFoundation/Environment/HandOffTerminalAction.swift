//  🖥️ TUI — A Terminal UI framework for Swift
//  HandOffTerminalAction.swift
//
//  Handing the terminal to another program — `$EDITOR`, a pager, `git
//  commit` — for as long as a closure runs, and taking it back.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Hand Off Terminal Action

/// An action that hands the terminal to another program for as long as a
/// closure runs, and then takes it back: for running `$EDITOR`, a pager, or
/// `git commit` from inside an app.
///
/// Read it from the environment and call it with the work to do while the
/// other program has the terminal. The closure runs at once, on the main
/// actor, and the call returns what it returns:
///
/// ```swift
/// struct NoteView: View {
///     @Environment(\.handOffTerminal) private var handOffTerminal
///     @State private var note = ""
///
///     var body: some View {
///         Button("Edit in $EDITOR") {
///             let file = FileManager.default.temporaryDirectory.appendingPathComponent("note.txt")
///             try? note.write(to: file, atomically: true, encoding: .utf8)
///             // `runInForeground` is the app's: see "Starting the program" below.
///             let status = handOffTerminal {
///                 runInForeground(["/bin/sh", "-c", "${EDITOR:-vi} \"$1\"", "sh", file.path])
///             }
///             if status == 0, let edited = try? String(contentsOf: file, encoding: .utf8) {
///                 note = edited
///             }
///         }
///     }
/// }
/// ```
///
/// The closure may throw: the action throws what it throws, and takes the
/// terminal back first, as it does when it returns.
///
/// ## What the other program gets
///
/// The terminal as it was before the app started, as a suspend (⌃Z) leaves it:
/// the main screen with the shell's lines on it, the cursor shown, the
/// terminal's own settings back (canonical input and echo, ⌃C, ⌃Z and ⌃\\ as
/// signals), and none of the app's modes left on: no mouse reports, no
/// bracketed paste, no focus reports, the kitty keyboard protocol's flags
/// popped, the window title and styling the shell had. The app's pictures and
/// hairlines are taken off the screen with it. Input the terminal has queued
/// and the app has not read is dropped as the terminal's settings change, as
/// it is for a suspend: it may hold the terminal's reports in the app's
/// encodings, mouse motion among them, which the other program would read as
/// typing. Input the app had read already, and not yet handled, stays the
/// app's: it was typed at the app, and is handled after the closure, in order.
/// What the other program leaves unread is dropped as the app takes the
/// terminal back, for the same reason the other way round.
///
/// ## While it runs
///
/// The app draws nothing, and its timers, animations and tasks wait: the
/// closure has the main actor until it returns. The scene is
/// ``ScenePhase/background``, as for a suspend: a frame at that phase is drawn
/// before the terminal is handed over, so an `onChange(of: scenePhase)` that
/// saves on the way down runs, and the phase is ``ScenePhase/active`` again
/// after.
///
/// ⌃C and ⌃\\ are the other program's, and end it rather than the app: the
/// app ignores `SIGINT` and `SIGQUIT` while the closure runs, as `system(3)`
/// does, and one that arrives meanwhile is forgotten after. A `SIGTERM` is
/// not ignored: the app ends once the closure returns. A resize is drawn at
/// the new size.
///
/// ## Taking it back
///
/// Once the closure returns, the app takes the terminal back as it does after
/// a suspend, and as if the other program had changed anything it liked: raw
/// mode made again from the terminal's settings, every mode set again, the
/// size read again, and every line drawn again. A program that sets modes and
/// does not put them back cannot leave them on.
///
/// ## Starting the program
///
/// The closure runs the other program however it likes, and waits for it.
/// For an interactive one, start it in the app's process group, with every
/// signal at its default action: `posix_spawn` with the
/// `POSIX_SPAWN_SETSIGDEF` and `POSIX_SPAWN_SETSIGMASK` flags (every signal in
/// the first set, none in the mask), and `waitpid` for it. Not Foundation's
/// `Process`: it starts its child in a process group of its own (measured on
/// macOS), which the terminal treats as a background job, so an editor that
/// reads the keyboard is stopped by `SIGTTIN` and never returns. And with the
/// defaults, because a program inherits the signals its parent ignores: the
/// app ignores `SIGPIPE` always, and `SIGINT` and `SIGQUIT` for the hand-off,
/// so a program spawned without them could not be stopped by ⌃C.
///
/// ## ⌃Z while the other program runs
///
/// The closure is opaque to TUI, which cannot tell what it starts. So ⌃Z
/// works as job control does for a program in the app's process group: the
/// app takes the stop's default action for the hand-off, ⌃Z stops the app
/// and the program together, the shell reports the job stopped, and `fg`
/// resumes both, as for `git commit` running an editor. A program in another
/// process group, or one that stops itself alone, is out of TUI's reach: the
/// app goes on waiting in the closure, and the terminal looks hung until the
/// program is continued (`kill -CONT`) from elsewhere. Nothing of TUI's own
/// suspend is left pending when the closure returns.
///
/// ## Where it does nothing
///
/// Outside a running app — a headless app, a test's `TestApp`, a snapshot, a
/// WebAssembly host, anything without a terminal of its own — there is nothing
/// to hand over, and the closure just runs. A call made inside the closure
/// runs its closure the same way, the terminal being the other program's
/// already.
///
/// Call it from an action, as a button's or a key's. Called while a frame is
/// drawn — from a view's `body` — it hands the terminal over without the
/// `.background` frame, which cannot be drawn inside another.
///
/// TUI-specific, with no SwiftUI counterpart: a Mac app does not share its
/// window with other programs. Textual's `App.suspend()` and Bubble Tea's
/// `tea.ExecProcess` are the prior art.
public struct HandOffTerminalAction {
    /// The context's hand-off: the running app's, with a handler, or one
    /// without, where a closure just runs.
    private let handOff: TerminalHandOff?

    /// The action that hands the terminal over through `handOff`.
    package init(handOff: TerminalHandOff?) {
        self.handOff = handOff
    }

    /// Hands the terminal to another program while `body` runs, and takes it
    /// back.
    ///
    /// - Parameter body: The work to do while the other program has the
    ///   terminal: typically, starting it and waiting for it to end. Runs at
    ///   once, on the main actor.
    /// - Returns: What `body` returns.
    /// - Throws: What `body` throws, once the terminal is back.
    @MainActor
    public func callAsFunction<Result, Failure: Error>(
        _ body: () throws(Failure) -> Result
    ) throws(Failure) -> Result {
        guard let handOff else { return try body() }
        return try handOff.run(body)
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// An action that hands the terminal to another program for as long as a
    /// closure runs, and takes it back — see ``HandOffTerminalAction``.
    ///
    /// Read-only: the running app's own, which reaches every view it draws.
    /// Outside a running app — a test, a snapshot — the closure just runs.
    public var handOffTerminal: HandOffTerminalAction {
        HandOffTerminalAction(handOff: terminalHandOff)
    }
}
