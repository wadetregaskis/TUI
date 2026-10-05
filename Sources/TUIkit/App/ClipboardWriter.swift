//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClipboardWriter.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

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
        let key: LocalizationKey.StatusBar
        switch self {
        case .copied: key = .copied
        case .sentToTerminal: key = .sentToTerminalClipboard
        case .unavailable: key = .notCopiedNoClipboard
        case .failed: key = .notCopiedHelperFailed
        case .nothingToCopy: return nil
        }
        return LocalizationService.shared.string(for: key)
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

    /// Whether this machine has a clipboard helper to run.
    private let hasSystemHelper: Bool

    /// Writes this machine's clipboard, answering whether it worked.
    private let systemWrite: @Sendable (String) -> Bool

    /// Reads this machine's clipboard, where that is the user's.
    private let systemRead: @Sendable () -> String?

    /// The run loop's clock, which notes are stamped and aged on.
    private let nowNanos: @Sendable () -> UInt64

    /// Asks the run loop for a frame, so a queued write and its note reach
    /// the screen without waiting for some other event to draw one.
    private let requestFrame: @Sendable () -> Void

    // Touched from the main actor only (copies run in event handlers), and
    // read by the run loop on the same actor; `@unchecked` because the
    // environment that carries the writer is `Sendable`.
    private var pending: [String] = []
    private var note: (result: ClipboardWriteResult, postedAtNanos: UInt64)?

    init(
        terminalSupport: @escaping @MainActor () -> TerminalClient.ClipboardWriteSupport,
        isLocal: @escaping @MainActor () -> Bool,
        hasSystemHelper: Bool,
        systemWrite: @escaping @Sendable (String) -> Bool,
        systemRead: @escaping @Sendable () -> String?,
        nowNanos: @escaping @Sendable () -> UInt64 = { MonotonicClock.nowNanoseconds },
        requestFrame: @escaping @Sendable () -> Void = { AppState.shared.setNeedsRender() }
    ) {
        self.terminalSupport = terminalSupport
        self.isLocal = isLocal
        self.hasSystemHelper = hasSystemHelper
        self.systemWrite = systemWrite
        self.systemRead = systemRead
        self.nowNanos = nowNanos
        self.requestFrame = requestFrame
    }

    /// The writer of a running app: the terminal the app is drawn in, this
    /// machine's helpers, and the rule between them.
    static func live() -> ClipboardWriter {
        ClipboardWriter(
            terminalSupport: { TerminalClient.clipboardWrites },
            isLocal: { ClipboardLocality.isLocal() },
            hasSystemHelper: SystemClipboard.hasHelper,
            systemWrite: { SystemClipboard.copy($0) },
            systemRead: { SystemClipboard.paste() })
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
                result = systemWrite(text) ? .copied : .failed
            case .none:
                result = .unavailable
            }
        }
        if result != .nothingToCopy, result != .copied || announcingSuccess {
            note = (result, nowNanos())
        }
        if !pending.isEmpty || note != nil { requestFrame() }
        return result
    }

    /// This machine's clipboard: what a paste chord reads.
    @MainActor func read() -> String? {
        systemRead()
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
        guard now < expiry, let text = note.result.statusLine else {
            self.note = nil
            return nil
        }
        return (text, expiry)
    }
}
