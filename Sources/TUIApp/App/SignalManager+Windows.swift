//  🖥️ TUI — A Terminal UI framework for Swift
//  SignalManager+Windows.swift
//
//  The Windows arm of SignalManager.swift: the console's control events, where
//  POSIX has signals.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Synchronization
import TUIFoundation
import WinSDK

/// The same manager, on Windows, where what POSIX sends as signals the console
/// sends as control events, to a handler on a thread it starts for each one
/// (`SetConsoleCtrlHandler`).
///
/// - **Shutdown**: `CTRL_C_EVENT` (sent by another program, or the key while
///   raw mode is off: in raw mode ⌃C is a key, as on POSIX), `CTRL_CLOSE_EVENT`
///   (the window or tab closed), `CTRL_LOGOFF_EVENT` and `CTRL_SHUTDOWN_EVENT`
///   set ``shouldShutdown``, which the run loop takes for an orderly quit, as
///   it does `SIGINT` and `SIGTERM`. For the last three the system ends the
///   process as soon as the handler returns, so the handler waits for the
///   loop's teardown, which ends the process itself, up to the five seconds
///   the system allows.
/// - **Resize** is no control event: the console sends it as an input record,
///   which its reader passes on (``noteResize()``; `ConsoleInput`).
/// - **Ctrl-Break** is the quit key's, handled where the debt is
///   (`FatalSignalTerminalRestore`).
/// - **Job control** does not exist: nothing suspends a Windows process from
///   its console, so the suspend and continue flags are never set.
/// - **A hand-off** (``beginHandOff()``) has the console's ⌃C and Ctrl-Break
///   ignored, as `system(3)` ignores `SIGINT` and `SIGQUIT`: the console
///   raises them in every process attached to it, the app among them, and
///   they are meant for the other program.
@MainActor
final class SignalManager {

    /// Whether the console asked the app to stop.
    private(set) var shouldShutdown = false

    /// Whether the console's window changed size since the loop last asked.
    private var resized = false

    /// What rouses the run loop.
    private var wake: (@MainActor @Sendable () -> Void)?

    /// Where the console's handler sends a shutdown: the installed manager's.
    /// The handler is a C function, which can capture nothing, so it finds its
    /// way here through a process-wide value, as a POSIX signal handler does
    /// (`FatalSignalTerminalRestore`, "Why a process-wide global").
    private static let route = Mutex<(@Sendable () -> Void)?>(nil)

    /// Returns and clears the resize flag.
    func consumeResizeFlag() -> Bool {
        defer { resized = false }
        return resized
    }

    /// Never true: no job control.
    func consumeSuspendFlag() -> Bool { false }

    /// Never true: no job control.
    func consumeContinueFlag() -> Bool { false }

    /// A no-op: no job control.
    func expectSelfResume() {}

    /// Whether the console is handed to another program
    /// (``beginHandOff()``): read by the console's handlers, on threads of
    /// their own, so process-wide, as their route is.
    nonisolated static let isHandingOff = Atomic(false)

    /// Sets the console's events up for it being handed to another program
    /// (`AppRunner.handOffTerminal`). With raw mode off the console's own
    /// input mode is back, ⌃C and Ctrl-Break are its control events again,
    /// and the console raises them in every process attached to it, the app
    /// included (`SetConsoleCtrlHandler`'s documentation: a console's control
    /// events go to all the processes that share it).
    /// They are meant for the other program, so the app takes them and does
    /// nothing, as `system(3)` ignores `SIGINT` and `SIGQUIT` while its child
    /// runs: neither ends the app, nor shuts it down once the closure returns.
    /// A closed window, a logoff or a shutdown still shuts it down.
    func beginHandOff() {
        Self.isHandingOff.store(true, ordering: .sequentiallyConsistent)
    }

    /// Takes them back, as the app takes the console back.
    func endHandOff() {
        Self.isHandingOff.store(false, ordering: .sequentiallyConsistent)
    }

    /// The console's window changed size: called by the console's reader, on
    /// the main actor.
    func noteResize() {
        resized = true
        wake?()
    }

    /// Takes the console's control events from here on, waking the loop with
    /// `wake` when one arrives.
    func install(wake: @escaping @MainActor @Sendable () -> Void) async {
        self.wake = wake
        Self.route.withLock {
            $0 = { [weak self] in
                Task { @MainActor in
                    self?.shouldShutdown = true
                    self?.wake?()
                }
            }
        }
        _ = SetConsoleCtrlHandler(Self.handler, true)
    }

    /// Stops taking them. Idempotent.
    func stop() {
        _ = SetConsoleCtrlHandler(Self.handler, false)
        Self.route.withLock { $0 = nil }
        wake = nil
    }

    /// The console's control handler: a shutdown for the events above, and
    /// nothing for the rest, which go on to the next handler. ⌃C during a
    /// hand-off is taken and ignored (``beginHandOff()``).
    static let handler: @convention(c) (DWORD) -> WindowsBool = { event in
        switch Int32(event) {
        case CTRL_C_EVENT where isHandingOff.load(ordering: .sequentiallyConsistent):
            return true
        case CTRL_C_EVENT, CTRL_CLOSE_EVENT, CTRL_LOGOFF_EVENT, CTRL_SHUTDOWN_EVENT:
            guard let route = SignalManager.route.withLock({ $0 }) else { return false }
            route()
            if Int32(event) != CTRL_C_EVENT { Sleep(5_000) }
            return true
        default:
            return false
        }
    }
}

#endif
