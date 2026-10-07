//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClipboardWriter.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - What became of a copy

/// What became of one copy.
enum ClipboardWriteResult: Equatable, Sendable {
    /// On the user's clipboard: written by this machine's clipboard helper
    /// while the terminal is on this machine, or sent by OSC 52 to a terminal
    /// that writes it by default.
    case copied

    /// Sent by OSC 52 to a terminal that may not write it: a setting decides,
    /// as iTerm2's does, or tmux passes it on. No terminal acknowledges the
    /// write, so this is all that can be said.
    case sentToTerminal

    /// Not copied. The terminal is not known to take OSC 52, and the session
    /// is not known to be on this machine, or this machine has no clipboard
    /// helper.
    case unavailable

    /// Not copied: this machine's clipboard helper was run and failed.
    case failed

    /// Nothing was sent, because there was nothing to copy.
    case nothingToCopy

    /// The status bar's line for it, or `nil` for none.
    var statusLine: String? {
        statusKey.map { LocalizationService.shared.string(for: $0) }
    }

    /// The key of the status bar's line for it, or `nil` for none.
    var statusKey: LocalizationKey.StatusBar? {
        switch self {
        case .copied: .copied
        case .sentToTerminal: .sentToTerminalClipboard
        case .unavailable: .notCopiedNoClipboard
        case .failed: .notCopiedHelperFailed
        case .nothingToCopy: nil
        }
    }
}

/// Where one copy goes.
enum ClipboardRoute: Equatable, Sendable {
    /// OSC 52 to the terminal; `confirmed` when the terminal writes it by
    /// default (``TerminalClient/ClipboardWriteSupport/honoured``).
    case terminal(confirmed: Bool)

    /// This machine's clipboard helper, because the terminal is on this
    /// machine (``ClipboardLocality``).
    case system

    /// Nowhere the user would find it.
    case none

    /// The rule, posed on its inputs. In order:
    ///
    /// 1. A terminal that writes OSC 52 by default is sent it — over ssh
    ///    too, which is the point: the terminal is on the user's machine.
    /// 2. Otherwise this machine's clipboard, but only on positive evidence
    ///    that the user is at this machine, and only where it has a helper.
    /// 3. Otherwise a terminal that MAY write OSC 52 is sent it, and the copy
    ///    is reported as sent rather than made.
    /// 4. Otherwise nothing is copied, and that is reported.
    ///
    /// One route per copy, never two: this machine's clipboard is written
    /// only when it is the user's, and then it is the surer of the two.
    static func choose(
        terminal: TerminalClient.ClipboardWriteSupport, hasSystemHelper: Bool, isLocal: () -> Bool
    ) -> Self {
        if terminal == .honoured { return .terminal(confirmed: true) }
        if hasSystemHelper, isLocal() { return .system }
        if terminal == .unconfirmed { return .terminal(confirmed: false) }
        return .none
    }
}

// MARK: - This machine's clipboard

/// This machine's clipboard, as ``ClipboardWriter`` reaches it: the route the
/// rule calls ``ClipboardRoute/system``.
///
/// Declared here and implemented above: the app's run loop installs the one
/// that runs this machine's helpers (`SystemClipboard.Backend`, `pbcopy` or
/// `xclip` as a subprocess, which belongs with the run loop's other POSIX
/// code) into the ``TUIContext`` it creates, and every other context — a
/// headless run's, a snapshot's, a test's — gets an ``InMemoryClipboard``,
/// so nothing but a running app ever touches the user's pasteboard. The rule
/// is the same whichever stands behind it: OSC 52 to a terminal that writes it
/// by default comes first, and this clipboard only where the user is at this
/// machine.
protocol ClipboardBackend: Sendable {
    /// Whether there is a clipboard here to write at all: `false` where this
    /// machine has no helper to run. Asked once, when a writer is made.
    var isAvailable: Bool { get }

    /// Puts `text` on the clipboard, answering whether it took it.
    func write(_ text: String) -> Bool

    /// The clipboard's text, or `nil` where it holds none or cannot be read.
    func read() -> String?
}

/// A clipboard held in memory: what a context gets unless the app's run loop
/// installs this machine's (``ClipboardBackend``).
///
/// A copy routed to this machine's clipboard lands here and a paste reads it
/// back, so a headless run or a test exercises the whole route without a
/// helper and without writing the developer's pasteboard. One per context, so
/// two contexts in one process — a test suite — keep their copies apart.
final class InMemoryClipboard: ClipboardBackend {
    /// What a paste reads: the latest copy.
    private let contents = Lock<String?>(initialState: nil)

    var isAvailable: Bool { true }

    func write(_ text: String) -> Bool {
        contents.withLock { $0 = text }
        return true
    }

    func read() -> String? {
        contents.withLock { $0 }
    }
}

// MARK: - OSC 52

/// The OSC 52 write TUIkit sends, spelled as Ghostty's documentation requires
/// (and xterm's allows): `ESC ] 52 ; c ; <base64> ESC \`.
enum ClipboardSequence {
    /// The write for `text`, or `nil` for empty text.
    ///
    /// - **`c`, spelled out.** An empty selector means `c` to Ghostty but
    ///   `s0` to xterm.
    /// - **One selector.** Ghostty takes no more than one per sequence.
    /// - **Never an empty or malformed payload.** Ghostty CLEARS the clipboard
    ///   when the payload is neither valid base64 nor `?`, so an empty copy
    ///   sends nothing at all, and the base64 is Foundation's default:
    ///   unwrapped, so no line break can land inside it.
    /// - **ST, not BEL.** The terminator TUIkit's other OSCs use.
    /// - **Never `?`.** A read prompts the user on Ghostty, and its reply
    ///   arrives in the input stream; paste stays the terminal's own,
    ///   bracketed.
    static func write(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        return "\u{1B}]52;c;" + Data(text.utf8).base64EncodedString() + "\u{1B}\\"
    }
}

// MARK: - The writer

/// The one way TUIkit puts text on the clipboard: a text field's or editor's
/// copy and cut, a `copyable` view's ⌘C, and a selection on the screen.
///
/// Each copy takes one route (``ClipboardRoute/choose(terminal:hasSystemHelper:isLocal:)``)
/// and reports what became of it, and the status bar says so for a few
/// seconds — except a text control's plain success, which is what the user
/// expected and needs no line of its own.
///
/// An OSC 52 write is queued rather than written: the run loop owns the
/// terminal, and writes the queue at the start of its next frame
/// (``takePendingSequences()``), which the writer asks for.
///
/// One per ``TUIContext``, never a shared instance: two apps in one process —
/// a test suite — must not drain each other's writes.
final class ClipboardWriter: @unchecked Sendable {
    /// How long the status bar keeps the line about a copy.
    static let noteDuration: UInt64 = 3_000_000_000

    /// How far the terminal takes an OSC 52 write. Asked once per copy, as
    /// the next is, because the answer can change while the app runs: tmux's
    /// `set-clipboard`, set from another pane.
    private let terminalSupport: @MainActor () -> TerminalClient.ClipboardWriteSupport

    /// Whether this machine's clipboard is the user's (``ClipboardLocality``).
    /// A tmux session can be attached from another machine at any moment.
    private let isLocal: @MainActor () -> Bool

    /// This machine's clipboard (``ClipboardBackend``): its helpers in a
    /// running app, memory everywhere else.
    private let system: any ClipboardBackend

    /// Whether ``system`` has a clipboard to write — its
    /// ``ClipboardBackend/isAvailable``, asked once.
    private let hasSystemHelper: Bool

    /// The run loop's clock, which notes are stamped and aged on.
    private let nowNanos: @Sendable () -> UInt64

    /// Asks the run loop for a frame, so a queued write and its note reach
    /// the screen without waiting for some other event to draw one.
    private let requestFrame: @Sendable () -> Void

    // Touched from the main actor only (copies run in event handlers), and
    // read by the run loop on the same actor; `@unchecked` because the
    // environment that carries the writer is `Sendable`.
    private var pending: [String] = []
    private var note: (line: LocalizationKey.StatusBar, postedAtNanos: UInt64)?

    /// The text of the latest copy this app made, whatever became of it: what
    /// a paste chord finds where this machine's clipboard is not the user's
    /// (``read()``).
    private var lastCopy: String?

    /// A writer over `system`, this machine's clipboard. The other answers
    /// default to this process's: the terminal it is drawn in, and whether the
    /// user is at this machine.
    init(
        terminalSupport: @escaping @MainActor () -> TerminalClient.ClipboardWriteSupport = {
            TerminalClient.clipboardWrites
        },
        isLocal: @escaping @MainActor () -> Bool = { ClipboardLocality.isLocal() },
        system: any ClipboardBackend,
        nowNanos: @escaping @Sendable () -> UInt64 = { MonotonicClock.nowNanoseconds },
        requestFrame: @escaping @Sendable () -> Void = { AppState.shared.setNeedsRender() }
    ) {
        self.terminalSupport = terminalSupport
        self.isLocal = isLocal
        self.system = system
        self.hasSystemHelper = system.isAvailable
        self.nowNanos = nowNanos
        self.requestFrame = requestFrame
    }

    /// Puts `text` on the clipboard by the route the rule picks, and reports
    /// what became of it.
    ///
    /// - Parameter announcingSuccess: Whether a plain success earns a line in
    ///   the status bar. A selection's copy does — nothing else on screen says
    ///   it happened — and a text control's does not. Anything short of a
    ///   plain success always does.
    @MainActor @discardableResult
    func write(_ text: String, announcingSuccess: Bool) -> ClipboardWriteResult {
        let result: ClipboardWriteResult
        if text.isEmpty {
            result = .nothingToCopy
        } else {
            let route = ClipboardRoute.choose(
                terminal: terminalSupport(), hasSystemHelper: hasSystemHelper, isLocal: isLocal)
            switch route {
            case .terminal(let confirmed):
                // Non-nil: the text is not empty.
                if let sequence = ClipboardSequence.write(text) { pending.append(sequence) }
                result = confirmed ? .copied : .sentToTerminal
            case .system:
                result = system.write(text) ? .copied : .failed
            case .none:
                result = .unavailable
            }
        }
        if result != .nothingToCopy { lastCopy = text }
        if let key = result.statusKey, result != .copied || announcingSuccess {
            note = (key, nowNanos())
        }
        if !pending.isEmpty || note != nil { requestFrame() }
        return result
    }

    /// What a paste chord — a field's Ctrl-V, a `PasteButton`, a
    /// `pasteDestination` — reads: this machine's clipboard when it is the
    /// user's, and otherwise the latest copy this app made.
    ///
    /// Over ssh this machine's clipboard is the server's, which holds nothing
    /// the user put there (and something someone else may have), so it is not
    /// read. The app's own copy stands in for it, so a value copied in the app
    /// pastes back into it — a field's Ctrl-C then another's Ctrl-V, a
    /// `copyable` view and a `PasteButton` — as the server's pasteboard used
    /// to carry it, and as tmux's buffer or vim's register does. Text copied
    /// on the user's machine comes in through the terminal's own paste,
    /// bracketed, which works everywhere, and the status bar says so either
    /// way: that what was pasted is the app's own last copy, which may be
    /// older than what the user last copied on their machine — under a
    /// session keeper at the desk too, where the desk's clipboard is no
    /// longer read — or, with none to give, to use the terminal's paste.
    /// Never OSC 52's `?`: a read prompts the user on Ghostty, and its reply
    /// would arrive in the input stream.
    @MainActor func read() -> String? {
        if hasSystemHelper, isLocal() { return system.read() }
        if let lastCopy {
            note = (.pastedAppCopy, nowNanos())
            requestFrame()
            return lastCopy
        }
        note = (.pasteWithTerminal, nowNanos())
        requestFrame()
        return nil
    }

    /// The OSC 52 writes owed to the terminal, oldest first, and forgets them.
    func takePendingSequences() -> String {
        guard !pending.isEmpty else { return "" }
        defer { pending.removeAll() }
        return pending.joined()
    }

    /// The status bar's line about the latest copy, while it is fresh: its
    /// text, and the instant it goes.
    func statusNote(atNanos now: UInt64) -> (text: String, expiresAtNanos: UInt64)? {
        guard let note else { return nil }
        let expiry = note.postedAtNanos &+ Self.noteDuration
        guard now < expiry else {
            self.note = nil
            return nil
        }
        return (LocalizationService.shared.string(for: note.line), expiry)
    }
}
