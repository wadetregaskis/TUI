//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHostState.swift
//
//  The ledger of what the app has set on the terminal emulator itself, beyond
//  its screen — the window title, the pointer's shape, the progress bar — and
//  what giving it back takes; and the spelling of a request for the person's
//  attention.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The Ledger

/// What the app has set on the terminal emulator beyond the screen, and how to
/// give it back: the window's title (refusal review P15; Ghostty adoption
/// study, C2, "build once, on the ledger"), the progress bar (C3) and the
/// pointer's shape (C4, ``pointerShape``).
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
/// sent only to a terminal documented to take one: `OSC 9 ; 4`, on a change,
/// and again whenever it has gone ``progressKeepAliveNanos`` unsent, even with
/// nothing to draw (``keepAlive(atNanos:)``) — Ghostty removes a bar no
/// program has updated for about fifteen seconds — where the terminal is one
/// that may (``keepsProgressAlive``; not tmux). Suspending and quitting take
/// it down (`OSC 9 ; 4 ; 0`), and a resume's first frame puts it up again.
///
/// A value, and one instance of it: the terminal's (``HostStateKeeping``,
/// `Terminal.hostState`), because the terminal is what the bytes go to, what
/// composes the debt a signal pays, and what changes the mouse modes that
/// reset the pointer's shape on Ghostty. What each frame wants is the render
/// loop's to say — the title of the window in front, the progress the views
/// drawn state — and it says so to this ledger, through the terminal it draws
/// on (`RenderLoop+HostState.swift`); the pointer's shape is the app runner's,
/// from the views under the pointer (`Terminal.showPointerShape(_:)`). Nothing
/// here writes: each change returns the bytes it takes, for the caller to send
/// with the frame, at once, or with the hand-back. (Decisions HOSTLEDGER,
/// B-HOSTLEDGER-1.)
struct TerminalHostState: Equatable {
    /// The pointer's shape (OSC 22), where the terminal takes one by name;
    /// `nil` where it is left alone.
    var pointerShape: TerminalHostSetting?

    /// Whether a progress bar is sent again before the terminal can drop it
    /// (``keepAlive(atNanos:)``): `false` for tmux, which keeps a pane's bar
    /// with no time limit and passes a report the same as the bar on to no
    /// client (both measured, 3.7c, `progress_probe.py`), so the repeat would
    /// reach no terminal and only wake the run loop for it. The render loop's
    /// to decide, as whether the bar is sent at all is
    /// (`RenderLoop.sendsProgressReports`): it sets it on the terminal's
    /// ledger as it is made.
    var keepsProgressAlive: Bool

    /// A ledger with nothing set on the terminal yet, for a terminal that may
    /// drop a bar no program updates (`keepsProgressAlive`), or not.
    init(keepsProgressAlive: Bool = true) {
        self.keepsProgressAlive = keepsProgressAlive
    }

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
    /// title is sanitised (``sanitizedText(_:)``), and one that sanitises to
    /// nothing is no title.
    mutating func show(title asked: String?) -> String {
        guard askedTitle != .some(asked) else { return "" }
        defer { askedTitle = .some(asked) }
        let title = asked.map(Self.sanitizedText(_:)).flatMap { $0.isEmpty ? nil : $0 }
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
    /// shown, or where none is sent again (``keepsProgressAlive``): the
    /// instant the run loop wakes for, if nothing wakes it sooner.
    var keepAliveDeadline: Int64? {
        guard keepsProgressAlive, writtenProgress != nil else { return nil }
        return progressSentAtNanos &+ Self.progressKeepAliveNanos
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

    /// Which values owe the terminal a reset: what ``debt`` and ``resets``
    /// are spelled from, so a change to either is a change here. The terminal
    /// compares it at every change to its ledger, and arms the debt a signal
    /// pays again only when it moved (`Terminal.hostState`).
    var owed: Owed {
        var owed: Owed = []
        if savedHostTitle { owed.insert(.windowTitle) }
        if writtenProgress != nil { owed.insert(.progress) }
        if pointerShape?.isOwed == true { owed.insert(.pointerShape) }
        return owed
    }

    /// The values that may owe the terminal a reset.
    struct Owed: OptionSet {
        let rawValue: UInt8

        /// The terminal's own title, saved on its title stack.
        static let windowTitle = Self(rawValue: 1 << 0)

        /// The app's progress bar, up.
        static let progress = Self(rawValue: 1 << 1)

        /// The pointer's shape, sent since the last reset.
        static let pointerShape = Self(rawValue: 1 << 2)
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
    /// program has updated (the Ghostty adoption study, C3; iTerm2's limit is
    /// unknown). tmux keeps one, measured, and is sent none again
    /// (``keepsProgressAlive``).
    static let progressKeepAliveNanos: Int64 = 5_000_000_000

    /// `OSC 9 ; 4 ; 0 ST`: no progress bar.
    static let removeProgressReport = "\u{1B}]9;4;0\u{1B}\\"

    /// `OSC 9 ; message ST`: a desktop notification carrying `message`
    /// (iTerm2's sequence, which Ghostty takes too), or `nil` where `message`
    /// is nothing but spaces once sanitised (``sanitizedText(_:)``), for which
    /// the bell rings instead. A message that starts with a digit is sent after
    /// a space: `OSC 9` carries ConEmu's commands as well — `9 ; 4 ; …` is a
    /// progress report — and a terminal that takes those would read a message
    /// like `4;1;50 files` as one (the Ghostty adoption study, C6).
    static func notification(_ message: String) -> String? {
        let text = sanitizedText(message)
        guard text.contains(where: { !$0.isWhitespace }) else { return nil }
        let leadsWithDigit = text.unicodeScalars.first.map { ("0"..."9").contains($0) } ?? false
        return "\u{1B}]9;" + (leadsWithDigit ? " " : "") + text + "\u{1B}\\"
    }

    /// `BEL`: the terminal's bell, which it sounds, flashes or marks as its
    /// user has set it.
    static let bell = "\u{07}"

    /// `text`, safe inside an OSC — a title, a notification's message: a line
    /// break or a tab is a space, and every other control character — C0,
    /// DEL, C1 — is dropped. A `BEL` or an `ESC` would end the OSC early, and
    /// what followed would be printed or obeyed; `sanitizedForTerminal` keeps
    /// C0, for text drawn on the screen, so text sent in an OSC has its own.
    static func sanitizedText(_ text: String) -> String {
        var sanitized = ""
        sanitized.reserveCapacity(text.utf8.count)
        for character in text {
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

// MARK: - Who keeps it

/// A terminal that keeps the ledger of what the app has set on it beyond its
/// screen: every terminal the render loop draws on, since every frame may set
/// the window title and the progress bar there.
///
/// A requirement of the render loop's terminal, where ``SynchronizedUpdating``
/// and ``CellGeometryReporting`` are capabilities it looks for: the ledger is
/// not something a terminal may lack, only something a test's terminal keeps
/// without a signal to owe it to. Not on the public ``TerminalProtocol``,
/// which the ledger, internal to this module, cannot reach.
@MainActor
protocol HostStateKeeping: TerminalProtocol {
    /// What the app has set on this terminal outside its grid, and owes it.
    var hostState: TerminalHostState { get set }
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
/// — whose resets raw mode's teardown writes, ahead of the mouse modes
/// (`Terminal.inputModesOwed`), rather than the hand-back (``restore()``):
/// on Ghostty the mouse modes going off is itself a reset of the pointer's
/// shape, and nothing may follow it that sets one.
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
