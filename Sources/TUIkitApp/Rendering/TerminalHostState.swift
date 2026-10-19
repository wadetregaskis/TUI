//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHostState.swift
//
//  The ledger of what the app has set on the terminal emulator itself, beyond
//  its screen — the window title, the pointer's shape, the progress bar — and
//  what giving it back takes.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The Ledger

/// What the app has set on the terminal emulator beyond the screen, and how to
/// give it back: the window's title (refusal review P15; Ghostty adoption
/// study, C2, "build once, on the ledger") and the progress bar (C3; pointer
/// shapes are to join them).
///
/// The title is the window in front's: its scene's title, or a root
/// `.navigationTitle` no top bar shows (`RenderLoop+HostState.swift`). It is
/// written as `OSC 2`, on a change only. The first time, the terminal's own
/// title is saved first, on its title stack (XTWINOPS 22); when the app has
/// no title to show, on suspend and on exit, it is restored (XTWINOPS 23), so
/// the shell gets its title back. A host without the stack ignores both, and
/// keeps the app's title until the shell's next prompt sets one — which
/// shell integration does on every measured host that has it.
///
/// The progress bar is what the views drawn state (`.terminalProgress(_:)`),
/// sent only to a terminal documented to draw one: `OSC 9 ; 4`, on a change,
/// and again whenever it has gone ``progressKeepAliveNanos`` unsent, even with
/// nothing to draw (``keepAlive(atNanos:)``) — Ghostty removes a bar no
/// program has updated for about fifteen seconds. Suspending and quitting
/// take it down (`OSC 9 ; 4 ; 0`), and a resume's first frame puts it up
/// again.
///
/// A value: the run loop owns one (``RenderLoop``), and nothing here writes —
/// each change returns the bytes it takes, for the caller to send with the
/// frame or the hand-back.
///
/// Two lanes built this ledger at once, and both halves are here: the window
/// title (lane O9), kept by the run loop's instance, and the pointer's shape
/// (lane O12, ``pointerShape``), kept by the ``Terminal``'s, which changes the
/// mouse modes that reset it on Ghostty. One owner for every value is queued
/// (HOSTLEDGER); until then each instance uses its own half.
struct TerminalHostState: Equatable {
    /// The pointer's shape (OSC 22), where the terminal takes one by name;
    /// `nil` where it is left alone. The ``Terminal``'s instance keeps it.
    var pointerShape: TerminalHostSetting?

    /// The title the terminal was last given, or `nil` while it shows its own.
    private(set) var writtenTitle: String?

    /// Whether the terminal's own title is saved on its title stack, owed a
    /// restore.
    private(set) var savedHostTitle = false

    /// The title last asked for, as asked — unsanitised — or `.none` since
    /// the last restore: a frame asking for the same is answered with one
    /// comparison, every frame asking.
    private var askedTitle: String??

    /// The progress report the terminal was last given, or `nil` while it
    /// shows none of the app's.
    private(set) var writtenProgress: ProgressReport?

    /// When ``writtenProgress`` was last sent, on the monotonic clock: what
    /// the keep-alive counts from.
    private var progressSentAtNanos: Int64 = 0

    /// The bytes that make the terminal show `title`, or give it its own back
    /// for `nil` (``restore()``): nothing where it shows that already. The
    /// title is sanitised (``sanitizedTitle(_:)``), and one that sanitises to
    /// nothing is no title.
    mutating func show(title asked: String?) -> String {
        guard askedTitle != .some(asked) else { return "" }
        defer { askedTitle = .some(asked) }
        let title = asked.map(Self.sanitizedTitle(_:)).flatMap { $0.isEmpty ? nil : $0 }
        guard title != writtenTitle else { return "" }
        guard let title else { return restoreHostTitle() }
        var bytes = ""
        if !savedHostTitle {
            bytes += Self.saveTitle
            savedHostTitle = true
        }
        writtenTitle = title
        return bytes + Self.setTitle(title)
    }

    /// The bytes that make the terminal show `progress` — or no bar, for
    /// `nil` — at `now` on the monotonic clock: nothing where it shows that
    /// already, to the whole percent it is told.
    mutating func show(progress: TerminalProgress?, atNanos now: Int64) -> String {
        let report = progress.map(ProgressReport.init)
        guard report != writtenProgress else { return "" }
        guard let report else { return removeProgress() }
        writtenProgress = report
        progressSentAtNanos = now
        return report.sequence
    }

    /// The bytes that send the progress bar again, where it has gone
    /// ``progressKeepAliveNanos`` unsent by `now`, or nothing: the write the run
    /// loop makes between frames, which draws nothing, and a frame makes when
    /// it is due anyway.
    mutating func keepAlive(atNanos now: Int64) -> String {
        guard let report = writtenProgress, let due = keepAliveDeadline, now >= due else { return "" }
        progressSentAtNanos = now
        return report.sequence
    }

    /// When the progress bar is next to be sent again, or `nil` while none is
    /// shown: the instant the run loop wakes for, if nothing wakes it sooner.
    var keepAliveDeadline: Int64? {
        writtenProgress == nil ? nil : progressSentAtNanos &+ Self.progressKeepAliveNanos
    }

    /// The bytes that give the terminal back what the app set on it — its own
    /// title, restored where one was saved, and no progress bar — and forgets
    /// what the app set, so the next frame sets it again: for suspend and exit.
    mutating func restore() -> String {
        restoreHostTitle() + removeProgress()
    }

    /// The bytes that give the terminal its own title back — a restore, where
    /// one was saved — and forgets the app's, so the next ``show(title:)``
    /// saves and sets again: for a frame with no title, and the hand-back.
    private mutating func restoreHostTitle() -> String {
        writtenTitle = nil
        askedTitle = .none
        guard savedHostTitle else { return "" }
        savedHostTitle = false
        return Self.restoreTitle
    }

    /// The bytes that take the app's progress bar down, where one is up.
    private mutating func removeProgress() -> String {
        guard writtenProgress != nil else { return "" }
        writtenProgress = nil
        return Self.removeProgressReport
    }

    /// What the terminal is owed should the process die now
    /// (`Terminal.signalDebt`): the title's restore, where one was saved, and
    /// the bar taken down, where one is up — both harmless on a terminal that
    /// took neither.
    var debt: String {
        (savedHostTitle ? Self.restoreTitle : "") + (writtenProgress == nil ? "" : Self.removeProgressReport)
    }

    // MARK: The Sequences

    /// `CSI 22 ; 2 t`: push the window title onto the title stack (XTWINOPS).
    static let saveTitle = "\u{1B}[22;2t"

    /// `CSI 23 ; 2 t`: pop the window title from the title stack (XTWINOPS).
    static let restoreTitle = "\u{1B}[23;2t"

    /// `OSC 2 ; title ST`: the window title, in UTF-8, ended by `ESC \`.
    /// `OSC 2` rather than `OSC 0`, which sets the icon name too, as the
    /// Ghostty adoption study recommends (C2).
    static func setTitle(_ title: String) -> String {
        "\u{1B}]2;\(title)\u{1B}\\"
    }

    /// How long a progress bar may go unsent before it is sent again: five
    /// seconds, well inside the fifteen after which Ghostty removes a bar no
    /// program has updated (the Ghostty adoption study, C3; tmux 3.7c keeps
    /// one, measured, and iTerm2's limit is unknown).
    static let progressKeepAliveNanos: Int64 = 5_000_000_000

    /// `OSC 9 ; 4 ; 0 ST`: no progress bar.
    static let removeProgressReport = "\u{1B}]9;4;0\u{1B}\\"

    /// `title`, safe inside an OSC: a line break or a tab is a space, and
    /// every other control character — C0, DEL, C1 — is dropped. A `BEL` or
    /// an `ESC` would end the OSC early, and what followed would be printed
    /// or obeyed; `sanitizedForTerminal` keeps C0, for text drawn on the
    /// screen, so the title has its own.
    static func sanitizedTitle(_ title: String) -> String {
        var sanitized = ""
        sanitized.reserveCapacity(title.utf8.count)
        for character in title {
            if character.isNewline || character == "\t" {
                sanitized.append(" ")
            } else if !character.unicodeScalars.contains(where: isControl(_:)) {
                sanitized.append(character)
            }
        }
        return sanitized
    }

    /// Whether `scalar` is a C0 control, DEL or a C1 control.
    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
    }
}

// MARK: - One value outside the grid

/// One thing the app sets on the terminal outside its grid of cells: what it
/// wants now, what it last sent, how to put the terminal's own back mid-run,
/// and what is owed as the app leaves.
///
/// The Ghostty study's "one mechanism for state outside the grid" (§1.2): a
/// pointer shape, a window title and a progress bar each need the value the
/// frame wants, the value last sent, a write when they differ, and a reset on
/// suspend, exit and fatal signal, sent again on resume — so each is one of
/// these, held by ``TerminalHostState``, rather than a copy of that logic of
/// its own. Bytes in, bytes out: what a value means, and how a host spells
/// it, is the caller's.
struct TerminalHostSetting: Equatable {
    /// The bytes that put back the terminal's own value while the app runs.
    let unset: String

    /// The bytes that put back the terminal's own value as the app leaves —
    /// a quit, a suspend, the debt a signal pays — once they are owed
    /// (``isOwed``).
    let reset: String

    /// What the terminal was last sent: `.some(nil)` its own value, `nil`
    /// unknown, which the next ``update(to:)`` settles by sending.
    private var sent: String?? = .some(nil)

    /// Whether anything has been sent since the last ``reset`` went out, so
    /// that one is owed.
    ///
    /// Not from the start: the Ghostty study's rule is that a reset joins
    /// the debt a signal pays only once it is measured harmless where nothing
    /// was set, and no host's is yet (`pointer_shape_card.py`). An app that
    /// never sets the value sends the terminal nothing, as it leaves either;
    /// one that set it owes the reset, which beats leaving its value behind.
    private(set) var isOwed = false

    init(unset: String, reset: String) {
        self.unset = unset
        self.reset = reset
    }

    /// The bytes that set `wanted` (`nil`: the terminal's own), or `nil` when
    /// the terminal already shows it. The write is the caller's.
    mutating func update(to wanted: String?) -> String? {
        if case .some(let last) = sent, last == wanted { return nil }
        sent = .some(wanted)
        isOwed = true
        return wanted ?? unset
    }

    /// Forgets what was sent: the terminal may have changed it itself.
    mutating func forgetSent() {
        if case .some(.some) = sent { sent = nil }
    }

    /// Takes note that ``reset`` went out: the terminal shows its own again,
    /// so a resume sends the wanted value afresh, and nothing is owed until
    /// it does.
    mutating func noteReset() {
        sent = .some(nil)
        isOwed = false
    }
}

// MARK: - The values set by name

/// The ledger's values kept as ``TerminalHostSetting``s — the pointer's shape
/// — which the ``Terminal``'s instance holds: the terminal writes each
/// change, owes each reset and pays it as the app leaves, because it is what
/// the bytes go to, what composes the debt a signal pays
/// (`Terminal.signalDebt`), and what changes the mouse modes, which on
/// Ghostty change the pointer's shape themselves.
extension TerminalHostState {
    /// What every value owes as the app leaves, in one string: written before
    /// the input modes go off (`Terminal.inputModesOwed`). Empty until a
    /// value has been sent (``TerminalHostSetting/isOwed``).
    var resets: String {
        guard let pointerShape, pointerShape.isOwed else { return "" }
        return pointerShape.reset
    }

    /// Takes note that ``resets`` went out.
    mutating func noteResets() {
        pointerShape?.noteReset()
    }
}

// MARK: - The Progress Report

extension TerminalHostState {
    /// A progress report as the terminal is told it: ConEmu's state and a
    /// whole percent, which is what a change is judged by, so a fraction that
    /// moves less than a percent sends nothing.
    struct ProgressReport: Equatable {
        /// ConEmu's state: `1` a value, `2` an error, `3` indeterminate, `4`
        /// paused. (`0`, no bar, is ``TerminalHostState/removeProgressReport``.)
        let state: Int

        /// `0...100`, or `nil` for none: the terminal keeps the value its bar
        /// already had (measured on tmux 3.7c, as ConEmu documents it).
        let percent: Int?

        init(_ progress: TerminalProgress) {
            switch progress {
            case .value(let fraction): (state, percent) = (1, Self.percent(fraction))
            case .error(let fraction): (state, percent) = (2, fraction.map(Self.percent(_:)))
            case .indeterminate: (state, percent) = (3, nil)
            case .paused(let fraction): (state, percent) = (4, fraction.map(Self.percent(_:)))
            }
        }

        /// `fraction` as a whole percent: clamped to `0...1`, `NaN` as none
        /// done, and rounded.
        static func percent(_ fraction: Double) -> Int {
            guard !fraction.isNaN else { return 0 }
            return Int((min(max(fraction, 0), 1) * 100).rounded())
        }

        /// `OSC 9 ; 4 ; state [; percent] ST`, ended by `ESC \` as every OSC
        /// TUIkit sends is.
        var sequence: String {
            "\u{1B}]9;4;\(state)" + (percent.map { ";\($0)" } ?? "") + "\u{1B}\\"
        }
    }
}
