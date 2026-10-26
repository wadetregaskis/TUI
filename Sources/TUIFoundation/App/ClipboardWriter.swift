//  🖥️ TUI — A Terminal UI framework for Swift
//  ClipboardWriter.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

// MARK: - What became of a copy

/// What became of one copy.
package enum ClipboardWriteResult: Equatable, Sendable {
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
    /// machine (``SessionLocality``).
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
package protocol ClipboardBackend: Sendable {
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

// MARK: - Representations

/// One more form of a copy than its text: a MIME type and its bytes —
/// `text/html` for styled text, `text/markdown`, `text/uri-list` for a link,
/// `image/png` for a picture.
///
/// Carried only where the terminal takes them (OSC 5522,
/// ``TerminalClient/mimeClipboard``); everywhere else a copy is its text.
package struct ClipboardRepresentation: Equatable, Sendable {
    /// The MIME type, as a pasteboard names it: `text/html`.
    package let type: String
    /// The bytes.
    package let data: Data

    package init(type: String, data: Data) {
        self.type = type
        self.data = data
    }

    /// Text in `type`, as UTF-8.
    package init(type: String, text: String) {
        self.init(type: type, data: Data(text.utf8))
    }
}

// MARK: - OSC 52

/// The OSC 52 write TUI sends, spelled as Ghostty's documentation requires
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
    /// - **ST, not BEL.** The terminator TUI's other OSCs use.
    /// - **Never `?`.** A read prompts the user on Ghostty, and its reply
    ///   arrives in the input stream; paste stays the terminal's own,
    ///   bracketed.
    static func write(_ text: String) -> String? {
        write(text, through: .none)
    }

    /// The write for `text` wrapped to reach the terminal past a session
    /// keeper (``TerminalClient/ClipboardPassthrough``), or `nil` for empty
    /// text.
    ///
    /// - **tmux:** `ESC P tmux;`, the write with each of its ESCs doubled,
    ///   `ESC \`. tmux undoubles them and passes the write on as above.
    /// - **GNU screen:** the write, BEL-terminated — an `ESC \` inside would
    ///   end screen's string — cut into DCS strings `ESC P … ESC \` of at most
    ///   ``screenStringBytes`` each, which screen passes on back to back,
    ///   making one write again. The write is ASCII, so a cut never splits a
    ///   character.
    static func write(_ text: String, through passthrough: TerminalClient.ClipboardPassthrough) -> String? {
        guard !text.isEmpty else { return nil }
        let data = Data(text.utf8).base64EncodedString()
        switch passthrough {
        case .none:
            return "\u{1B}]52;c;" + data + "\u{1B}\\"
        case .tmux:
            return "\u{1B}Ptmux;\u{1B}\u{1B}]52;c;" + data + "\u{1B}\u{1B}\\\u{1B}\\"
        case .screen:
            let sequence = Array(("\u{1B}]52;c;" + data + "\u{07}").utf8)
            let room = screenStringBytes - 4
            var out: [UInt8] = []
            out.reserveCapacity(sequence.count + (sequence.count / room + 1) * 4)
            var start = 0
            while start < sequence.count {
                let end = min(start + room, sequence.count)
                out += [0x1B, UInt8(ascii: "P")]
                out += sequence[start..<end]
                out += [0x1B, UInt8(ascii: "\\")]
                start = end
            }
            return String(bytes: out, encoding: .utf8)
        }
    }

    /// The most bytes one of GNU screen's DCS strings may hold, its `ESC P`
    /// and `ESC \` included: screen 4.00.03 passes a string of 256 bytes on
    /// and drops one of 260 whole (measured, `keeper_passthrough_probe.py`).
    /// Later releases are reported to allow 512 and then 768; 256 serves all.
    static let screenStringBytes = 256

    /// The OSC 5522 write of `text` as `text/plain` and every one of
    /// `representations` after it, or `nil` for empty text: kitty's clipboard
    /// protocol (https://sw.kovidgoyal.net/kitty/clipboard/).
    ///
    /// `type=write` opens it; each type follows as `type=wdata` packets, its
    /// MIME type and its bytes base64 (standard, padded), at most 4096 bytes
    /// before encoding to a packet, one type's packets all sent before the
    /// next type's; an empty `type=wdata` closes it. The terminal answers
    /// `type=write:status=DONE`, or an error, which the input parser swallows
    /// with every other reply. A type with no bytes is left out: an empty
    /// `wdata` would close the write.
    static func write(_ text: String, representations: [ClipboardRepresentation]) -> String? {
        let parts =
            (text.isEmpty ? [] : [ClipboardRepresentation(type: "text/plain", text: text)])
            + representations.filter { !$0.data.isEmpty }
        guard !parts.isEmpty else { return nil }
        let introducer = "\u{1B}]5522;"
        let terminator = "\u{1B}\\"
        var out = introducer + "type=write" + terminator
        for part in parts where !part.data.isEmpty {
            let mime = Data(part.type.utf8).base64EncodedString()
            var offset = part.data.startIndex
            while offset < part.data.endIndex {
                let end = part.data.index(offset, offsetBy: mimeChunkBytes, limitedBy: part.data.endIndex)
                    ?? part.data.endIndex
                out += introducer + "type=wdata:mime=" + mime + ";"
                    + part.data[offset..<end].base64EncodedString() + terminator
                offset = end
            }
        }
        return out + introducer + "type=wdata" + terminator
    }

    /// The most bytes of a type an OSC 5522 packet carries, before encoding:
    /// the protocol's limit.
    static let mimeChunkBytes = 4096
}

// MARK: - The writer

/// The one way TUI puts text on the clipboard: a text field's or editor's
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
package final class ClipboardWriter: @unchecked Sendable {
    /// How long the status bar keeps the line about a copy.
    static let noteDuration: UInt64 = 3_000_000_000

    /// How far the terminal takes an OSC 52 write, and how the write is
    /// wrapped to cross a session keeper on its way. Asked once per copy, as
    /// the next is, because the answer can change while the app runs: tmux's
    /// `set-clipboard` or `allow-passthrough`, set from another pane.
    private let terminal: @MainActor () -> TerminalClient.ClipboardDelivery

    /// Whether this machine's clipboard is the user's (``SessionLocality``).
    /// A tmux session can be attached from another machine at any moment.
    private let isLocal: @MainActor () -> Bool

    /// Whether the terminal takes OSC 5522, so a terminal copy carries every
    /// representation rather than its text alone.
    private let mimeSupport: @MainActor () -> Bool

    /// This machine's clipboard (``ClipboardBackend``): its helpers in a
    /// running app, memory everywhere else.
    ///
    /// Internal rather than private so a test can check which one the app's
    /// runner installed: built with the in-memory default instead, a running
    /// app's copies would report `.copied` and never reach the pasteboard.
    let system: any ClipboardBackend

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
    /// user is at this machine. `requestFrame` asks the app the writer is
    /// drawn in for a frame — its context passes its render state's — and
    /// asks nothing by default, for a writer no app draws.
    init(
        terminal: @escaping @MainActor () -> TerminalClient.ClipboardDelivery = {
            TerminalClient.clipboardDelivery
        },
        isLocal: @escaping @MainActor () -> Bool = { SessionLocality.isLocal() },
        mimeSupport: @escaping @MainActor () -> Bool = { TerminalClient.mimeClipboard },
        system: any ClipboardBackend,
        nowNanos: @escaping @Sendable () -> UInt64 = { MonotonicClock.nowNanoseconds },
        requestFrame: @escaping @Sendable () -> Void = {}
    ) {
        self.terminal = terminal
        self.isLocal = isLocal
        self.mimeSupport = mimeSupport
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
    /// - Parameter representations: More forms of the copy than its text —
    ///   styled text as HTML, a link as a URI list — which go with it where
    ///   the terminal takes them (``TerminalClient/mimeClipboard``), and
    ///   nowhere else: this machine's clipboard is written by a helper that
    ///   takes text.
    @MainActor @discardableResult
    func write(
        _ text: String, representations: [ClipboardRepresentation] = [], announcingSuccess: Bool
    ) -> ClipboardWriteResult {
        let result: ClipboardWriteResult
        let hasRepresentations = representations.contains { !$0.data.isEmpty }
        if text.isEmpty, !hasRepresentations {
            result = .nothingToCopy
        } else if text.isEmpty {
            // Only types that are not text — a picture: they cross only where
            // the terminal takes types, and over its own write, which no
            // keeper's passthrough carries.
            let delivery = terminal()
            let route = ClipboardRoute.choose(
                terminal: delivery.support, hasSystemHelper: hasSystemHelper, isLocal: isLocal)
            if case .terminal(let confirmed) = route, delivery.passthrough == .none, mimeSupport(),
                let sequence = ClipboardSequence.write(text, representations: representations)
            {
                pending.append(sequence)
                result = confirmed ? .copied : .sentToTerminal
            } else {
                result = .unavailable
            }
        } else {
            let delivery = terminal()
            let route = ClipboardRoute.choose(
                terminal: delivery.support, hasSystemHelper: hasSystemHelper, isLocal: isLocal)
            switch route {
            case .terminal(let confirmed):
                // Non-nil: the text is not empty. Through a keeper's
                // passthrough the text alone: its other types are a write of
                // their own (OSC 5522) that the passthroughs are not measured
                // to carry.
                let sequence =
                    delivery.passthrough == .none && mimeSupport()
                    ? ClipboardSequence.write(text, representations: representations)
                    : ClipboardSequence.write(text, through: delivery.passthrough)
                if let sequence { pending.append(sequence) }
                result = confirmed ? .copied : .sentToTerminal
            case .system:
                result = system.write(text) ? .copied : .failed
            case .none:
                result = .unavailable
            }
        }
        if result != .nothingToCopy, !text.isEmpty { lastCopy = text }
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
    package func takePendingSequences() -> String {
        guard !pending.isEmpty else { return "" }
        defer { pending.removeAll() }
        return pending.joined()
    }

    /// The status bar's line about the latest copy, while it is fresh: its
    /// text, and the instant it goes.
    package func statusNote(atNanos now: UInt64) -> (text: String, expiresAtNanos: UInt64)? {
        guard let note else { return nil }
        let expiry = note.postedAtNanos &+ Self.noteDuration
        guard now < expiry else {
            self.note = nil
            return nil
        }
        return (LocalizationService.shared.string(for: note.line), expiry)
    }
}
