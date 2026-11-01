//  🖥️ TUI — A Terminal UI framework for Swift
//  ColorDepth.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization

/// The color depth supported by the terminal.
///
/// Detected automatically from `TERM` and `COLORTERM` environment
/// variables. The detected value is cached and used by
/// `ANSIRenderer` to downsample colors that exceed the terminal's
/// capabilities.
///
/// ## Detection Order
///
/// 1. `COLORTERM` containing `truecolor` or `24bit` → ``truecolor``
/// 2. `TERM` not set → ``truecolor`` (backward-compatible default)
/// 3. `TERM` equal to `dumb` → ``noColor``
/// 4. `TERM` naming a terminal that is truecolour by its own documentation —
///    `xterm-ghostty`, `xterm-kitty`, `wezterm`, `alacritty`, `foot` →
///    ``truecolor`` (what ssh forwards: it carries `TERM` and drops
///    `COLORTERM`)
/// 5. `TERM` containing `direct` → ``truecolor``
/// 6. `TERM` containing `256color` → ``palette256`` (`xterm-256color`,
///    `screen-256color`, `tmux-256color` — the common case)
/// 7. `TERM` containing `color` → ``basic16``
/// 8. `TERM` set but unrecognized → ``basic16``
///
/// > Note: `NO_COLOR` (https://no-color.org/) is not handled here because
/// > it represents a user preference, not a terminal capability. It should
/// > be handled at the output layer (e.g., by stripping ANSI codes before
/// > writing to stdout). Use ``noColor`` directly if you need to disable
/// > color output programmatically.
///
/// ## Override
///
/// Set ``current`` to override the detected value, for example when
/// building for a known target environment or in tests:
///
/// ```swift
/// ColorDepth.current = .palette256
/// ```
public enum ColorDepth: Int, Sendable, Comparable, AtomicRepresentable {
    /// No color output.
    ///
    /// Detected when `TERM` is `dumb`. Can also be set manually
    /// to disable color output programmatically.
    /// `ANSIRenderer` emits no color escape codes at this level;
    /// text attributes (bold, underline, etc.) are still emitted.
    case noColor = 0

    /// 16 colors: 8 standard + 8 bright ANSI colors (SGR 30–37, 90–97).
    case basic16 = 1

    /// 256 colors: 16 ANSI + 6×6×6 RGB cube + 24 grayscale (SGR 38;5;n).
    case palette256 = 2

    /// 24-bit true color / 16.7 million colors (SGR 38;2;r;g;b).
    case truecolor = 3

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Detection

extension ColorDepth {
    /// The process-wide colour depth, before any task-local pin.
    ///
    /// Atomic because anything may read it, whatever thread sets it: the value
    /// is set once during initialization (from environment variables that
    /// don't change) and read from the render path. Any override is expected
    /// before rendering starts. Relaxed, since no other memory is published
    /// with it, and a read costs what a plain load does.
    ///
    /// Being a `static let` with an initializer, this is LAZY: `detect()` runs
    /// on the first read of ``current`` from anywhere in the process, and the
    /// answer it gives then is the one the whole process keeps. That is the
    /// designed behaviour; see ``detect(environment:)`` for why it means no
    /// test may put a fake `TERM` in the real environment.
    private static let processCurrent = Atomic<ColorDepth>(detect())

    /// A task-scoped pin of ``current``, bound by ``withCurrent(_:operation:)-(_,()->T)``.
    ///
    /// Task-local rather than a plain global so a scoped pin — a test
    /// asserting on rendered colour, a subtree deliberately rendered at a
    /// different depth — is visible ONLY to work on the pinning task.
    /// Parallel tasks (notably Swift Testing's parallel test runner) keep
    /// seeing the process value; a global mutate-and-restore would bleed a
    /// pinned depth into every concurrently-rendering test.
    @TaskLocal private static var taskCurrent: ColorDepth?

    /// The process-wide ceiling on ``current``, before any task-local pin.
    /// Atomic for the same reason ``processCurrent`` is.
    private static let processCap = Atomic<ColorDepth>(.truecolor)

    /// A task-scoped ceiling, bound by ``withCap(_:operation:)-(_,()->T)``.
    @TaskLocal private static var taskCap: ColorDepth?

    /// The color depth to use for rendering.
    ///
    /// Automatically detected from environment variables at launch, and never
    /// above ``cap``.
    /// Assign a value to override detection process-wide (expected before
    /// rendering starts); use ``withCurrent(_:operation:)-(_,()->T)`` for a scoped,
    /// task-local pin.
    public static var current: ColorDepth {
        get {
            min(
                taskCurrent ?? processCurrent.load(ordering: .relaxed),
                taskCap ?? processCap.load(ordering: .relaxed))
        }
        set { processCurrent.store(newValue, ordering: .relaxed) }
    }

    /// The most colour the app will use, whatever the terminal offers.
    ///
    /// Separate from ``current`` because the two answer different questions.
    /// `current` is *what this terminal can do*, detected once and occasionally
    /// pinned; `cap` is *what this app chooses to use*, and it composes with
    /// detection rather than replacing it — set it to ``palette256`` and a
    /// truecolor terminal renders in 256 colours while a 16-colour one still
    /// renders in 16.
    ///
    /// Assigning `current` cannot express that: it would have to be re-derived
    /// every time detection changed, and would silently UPGRADE a terminal that
    /// cannot honour it. A ceiling only ever removes colour, which is the safe
    /// direction and the one worth having — for a deliberately flatter look, to
    /// see what an app looks like where it will be run, or to cut the bytes a
    /// frame spends on styling.
    ///
    /// Defaults to ``truecolor``, which is no cap at all.
    public static var cap: ColorDepth {
        get { taskCap ?? processCap.load(ordering: .relaxed) }
        set { processCap.store(newValue, ordering: .relaxed) }
    }

    /// Runs `operation` with ``cap`` pinned to `depth` on the current task,
    /// restoring the previous ceiling afterwards. Task-local for the same
    /// reason ``withCurrent(_:operation:)-(_,()->T)`` is.
    @discardableResult
    public static func withCap<T>(
        _ depth: ColorDepth, operation: () throws -> T
    ) rethrows -> T {
        try $taskCap.withValue(depth, operation: operation)
    }

    /// Async variant of ``withCap(_:operation:)-(_,()->T)``.
    ///
    /// The function AND `operation` are both `nonisolated(nonsending)`, so the
    /// ceiling is set on the caller's execution context rather than on the
    /// generic executor: a `@MainActor` caller's `operation` stays on the main
    /// actor and may touch main-actor state directly.
    ///
    /// Marking only the parameter would not achieve that. A plain `nonisolated`
    /// async function hops to the generic executor before it ever invokes the
    /// closure, so the closure runs there too — and an actor-isolated caller
    /// cannot pass an actor-isolated closure to it at all, because that sends a
    /// non-`Sendable` value across an isolation boundary.
    ///
    /// This is NOT `@Sendable` and does not make the closure concurrent: it
    /// removes a hop rather than adding one.
    @discardableResult
    nonisolated(nonsending) public static func withCap<T>(
        _ depth: ColorDepth, operation: nonisolated(nonsending) () async throws -> T
    ) async rethrows -> T {
        try await $taskCap.withValue(depth, operation: operation)
    }

    /// Runs `operation` with ``current`` pinned to `depth` on the current
    /// task, restoring the previous behaviour afterwards.
    ///
    /// The pin is task-local: concurrent tasks are unaffected, so parallel
    /// test runs can each pin their own depth without serialization.
    @discardableResult
    public static func withCurrent<T>(
        _ depth: ColorDepth, operation: () throws -> T
    ) rethrows -> T {
        try $taskCurrent.withValue(depth, operation: operation)
    }

    /// Async variant of ``withCurrent(_:operation:)-(_,()->T)`` — the pin covers the
    /// whole async operation, including its suspensions (task-locals are
    /// inherited across awaits and by child tasks, but not by detached ones).
    ///
    /// The function AND `operation` are both `nonisolated(nonsending)`, so the
    /// depth is pinned on the caller's execution context rather than on the
    /// generic executor: a `@MainActor` caller's `operation` stays on the main
    /// actor and may touch main-actor state directly.
    ///
    /// Marking only the parameter would not achieve that. A plain `nonisolated`
    /// async function hops to the generic executor before it ever invokes the
    /// closure, so the closure runs there too — and an actor-isolated caller
    /// cannot pass an actor-isolated closure to it at all, because that sends a
    /// non-`Sendable` value across an isolation boundary.
    ///
    /// This is NOT `@Sendable` and does not make the closure concurrent: it
    /// removes a hop rather than adding one.
    @discardableResult
    nonisolated(nonsending) public static func withCurrent<T>(
        _ depth: ColorDepth, operation: nonisolated(nonsending) () async throws -> T
    ) async rethrows -> T {
        try await $taskCurrent.withValue(depth, operation: operation)
    }

    /// Detects the terminal's color depth from environment variables.
    ///
    /// This method inspects `COLORTERM` and `TERM` in the order
    /// described in ``ColorDepth``. It is called once to initialize
    /// ``current`` and can be called again if the environment changes.
    ///
    /// # Why the environment is a parameter
    ///
    /// It defaults to what the running process actually has, so every existing
    /// caller is unaffected — the shape the package's other environment readers
    /// already use (`TerminalHost.detectAppleTerminal(environment:)` and its
    /// four siblings, `LocalizationService.systemPreferredLanguage(environment:)`,
    /// `TerminalColorQuery.resolve(_:environment:)`). Here it is not merely for
    /// tidiness, because this is the one detector whose answer LATCHES.
    ///
    /// `processCurrent` is a lazy static whose initializer is this function, so
    /// whoever first reads ``current`` anywhere in the process fixes the
    /// process-wide depth for the rest of the run — and ``current`` is in turn
    /// the DEFAULT ARGUMENT of `Color.foregroundCodes(depth:)`,
    /// `backgroundCodes(depth:)` and `backgroundEscape(depth:)`, so that reader
    /// is simply the first code to spell any colour. Posing the decision table
    /// by putting a fake `TERM` in the real environment therefore risks
    /// freezing a *parallel* test's colours at, say, `dumb` for the remainder
    /// of the process. Posing it on a dictionary cannot: the process
    /// environment is never written, so no fake value exists for the latch to
    /// catch. `.swiftlint.yml`'s `process_terminal_environment_mutation` rule
    /// keeps it that way.
    ///
    /// Latching once per process is the intended behaviour and is unchanged:
    /// the default argument is evaluated per call, so the lazy initializer
    /// still reads the live environment exactly once.
    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ColorDepth {
        // COLORTERM is the most reliable indicator of truecolor support.
        // Modern terminals (iTerm2, GNOME Terminal, Alacritty, WezTerm,
        // Ghostty, etc.) set this to "truecolor" or "24bit".
        if let colorterm = environment["COLORTERM"]?.lowercased() {
            if colorterm.contains("truecolor") || colorterm.contains("24bit") {
                return .truecolor
            }
        }

        // TERM encodes the terminal type and sometimes color depth.
        guard let term = environment["TERM"]?.lowercased() else {
            // TERM is not set. This typically means the process is not
            // running in a traditional terminal (e.g. IDE, redirected
            // output, or env wasn't propagated). Default to truecolor
            // to preserve backward compatibility — we only downgrade
            // when there is positive evidence of limited capabilities.
            return .truecolor
        }

        // TERM=dumb means a very limited terminal (e.g. Emacs shell,
        // CI log viewers). No escape codes should be emitted.
        if term == "dumb" {
            return .noColor
        }

        // A TERM that names a truecolour terminal. Locally Ghostty and kitty
        // also set COLORTERM, so rung 1 has already answered; this rung is for
        // the case where it is missing, and the common one is ssh, which
        // forwards TERM and not COLORTERM. Without it, a Ghostty or kitty user
        // who sshes to a box running a TUI app got the 16-colour rendering.
        if Self.truecolorTerminalNames.contains(term) {
            return .truecolor
        }

        // "direct" suffix indicates direct-color (24-bit) support,
        // e.g. "xterm-direct", "iterm2-direct".
        if term.contains("direct") {
            return .truecolor
        }

        // "-256color" suffix is the standard indicator for 256-color
        // support, e.g. "xterm-256color", "screen-256color", "tmux-256color".
        if term.contains("256color") {
            return .palette256
        }

        // "-Ncolor" pattern (e.g. "xterm-16color") or any TERM value
        // containing "color" indicates at least basic color support.
        if term.contains("color") {
            return .basic16
        }

        // TERM is set but doesn't match any known pattern.
        // Default to basic 16-color as the safest assumption for
        // an unknown terminal type.
        return .basic16
    }

    /// The `TERM` values that name a terminal which is truecolour by its own
    /// documentation, matched whole and lowercased.
    ///
    /// Whole names, not substrings: the rung is evidence about one program, and
    /// a substring match would credit any terminfo entry that happens to
    /// contain the word. None of these contains `256color` or `direct`, which
    /// is why, before this rung, the substring rungs sent all five to
    /// ``basic16``.
    ///
    /// - `xterm-ghostty`: Ghostty's own terminfo entry.
    /// - `xterm-kitty`: kitty's.
    /// - `wezterm`, `alacritty`, `foot`: each terminal's own entry, which it
    ///   sets when that entry is installed. Unmeasured here; their
    ///   documentation is the evidence.
    ///
    /// A terminal that has rewritten `TERM` to `xterm-256color` before the hop
    /// (Ghostty's opt-in ssh integration does) reaches rung 6 and gets
    /// ``palette256``, which is still the honest answer for that `TERM`.
    static let truecolorTerminalNames: Set<String> = [
        "xterm-ghostty", "xterm-kitty", "wezterm", "alacritty", "foot",
    ]
}
