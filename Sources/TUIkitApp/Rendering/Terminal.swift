//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Terminal.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitFoundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#elseif canImport(WASILibc)
    import WASILibc
#endif

/// Represents the terminal and controls input and output.
///
/// `Terminal` is the central interface to the terminal. It provides:
/// - Terminal size queries
/// - Raw mode configuration
/// - Safe input and output
/// - Frame-buffered output (all writes collected, flushed in one syscall)
///
/// ## Output Buffering
///
/// During rendering, call ``beginFrame()`` before writing and ``endFrame()``
/// after. All ``write(_:)`` calls between them are collected in an internal
/// `[UInt8]` buffer and flushed as a single `write()` syscall, reducing
/// per-frame syscalls from ~40+ to exactly 1.
///
/// Outside of a frame (setup, teardown), ``write(_:)`` writes immediately
/// as before — safe by default.
///
/// ## Thread Safety
///
/// `Terminal` is `@MainActor` isolated. All terminal operations must occur
/// on the main thread, which is enforced by the Swift concurrency system.
@MainActor
final class Terminal: TerminalProtocol {
    /// Whether raw mode is active.
    /// Readable across the module so the mode-negotiation extension in
    /// `TerminalModeQuery.swift` can refuse to query a terminal that is not in
    /// raw mode; still only writable here.
    private(set) var isRawMode = false

    /// Whether this process turned DEC mode 2027 (grapheme clustering) on and
    /// therefore owes the terminal a reset on the way out.
    ///
    /// Lives here rather than beside the code that sets it because an
    /// extension cannot hold stored state; ``pinGraphemeClusteringIfNeeded()``
    /// in `TerminalModeQuery.swift` is its only writer, and
    /// ``disableRawMode()`` its only reader.
    var pinnedGraphemeClustering = false

    /// The mouse tracking mode last sent to the terminal.
    ///
    /// `applyMouseSupport` consults this to decide whether to emit a
    /// new mode-set escape code; idempotency lets it be called every
    /// frame at no cost.
    private var appliedMouseMode: MouseTrackingMode = .none

    /// All input bytes that have been drained from stdin but not yet
    /// dispatched as events. Bytes are appended at the back by
    /// ``appendDrain()`` (one `read()` syscall per call) and consumed
    /// from the front by ``readEvent()`` as it identifies events.
    ///
    /// ``InputByteBuffer`` removes from the front in O(1) and hands
    /// `read()` free storage at its back, so stdin is read straight
    /// into it with no intermediate copy. Capacity grows
    /// geometrically when needed and ``consume(_:)`` shrinks it back
    /// to ``baselineCapacity`` once a transient large paste has been
    /// fully consumed.
    ///
    /// This and the parser state below it are module-internal rather than
    /// private, and NOT because anything outside wants them: the parser that
    /// owns them lives in `Terminal+Input.swift` (and the reply walk in
    /// `Terminal+Replies.swift`), split out because this file had reached its
    /// length limit, and an extension cannot hold stored properties. Nothing
    /// outside this module can see `Terminal` at all.
    var input = InputByteBuffer(minimumCapacity: Terminal.baselineCapacity)

    /// How many bytes one ``appendDrain()`` asks `read()` for. Sized
    /// to comfortably hold a frame's worth of bursty mouse events.
    static let readChunk = 4096

    /// Initial — and steady-state minimum — capacity for ``input``:
    /// one ``readChunk`` and twice ``maxReplyBytes``, so a drain never
    /// has to grow the buffer under a sequence the parser is waiting on.
    ///
    /// The arithmetic. A sequence is partial only because the buffer
    /// ends inside it, so while the parser waits, the buffer holds that
    /// sequence and nothing else, and it is shorter than
    /// ``maxReplyBytes`` (a longer one is dropped). A drain needs room
    /// when the back is past `baselineCapacity − readChunk`, which is
    /// `2 × maxReplyBytes`; so more than ``maxReplyBytes`` bytes were
    /// removed in front of the partial, more than the partial holds,
    /// and ``InputByteBuffer`` slides it down rather than growing (it
    /// slides when the bytes removed in front are at least as many as
    /// the live ones). Paste content is not bounded that way: a large
    /// paste grows the buffer, and ``consume(_:)`` gives the room back.
    ///
    /// It was one ``readChunk`` until 2026-10-10. A drain asks for a
    /// whole chunk of free room, so ANY partial sequence left at the
    /// front — a read boundary through a mouse report, the lone `ESC`
    /// of an Escape key held a round — grew the buffer by half, and the
    /// next ``consume(_:)`` shrank it straight back: two reallocations
    /// each time. Two chunks fixed that for partials of up to half a
    /// chunk, but not for a longer reply: 1,000 keys and the first
    /// 3,096 bytes of a reply in one read, then a few more of its bytes,
    /// still grew it (the 1,000 bytes in front were fewer than the
    /// 3,106 to slide).
    static let baselineCapacity = readChunk + 2 * maxReplyBytes

    /// True while we're between the bracketed-paste start (`ESC[200~`)
    /// and end (`ESC[201~`) markers. Paste content is accumulated
    /// across as many `readEvent()` calls as it takes for the end
    /// marker to arrive — no blocking, no `usleep`. The run loop
    /// stays responsive even for very large pastes.
    var inPasteMode: Bool = false {
        didSet {
            pasteScanCursor = 0
            keptPaste = nil
        }
    }

    /// How many leading bytes of ``input`` have already been checked and ruled
    /// out as the START of the bracketed-paste end marker.
    ///
    /// Meaningful only while ``inPasteMode``, which is why its `didSet` clears
    /// this: a cursor into a buffer that belongs to a finished paste is
    /// nonsense, and leaving a stale one behind would skip past the next
    /// paste's marker. Nothing is consumed from the front while a paste is
    /// open, so an index taken on one pass still means the same byte on the
    /// next — except past ``pasteByteLimit``, where the bytes the cursor has
    /// passed are dropped and the cursor goes back to zero with them.
    var pasteScanCursor: Int = 0

    /// The most of one bracketed paste that reaches the app: 16 MiB.
    ///
    /// A longer paste still ends at its end marker (or the stall timeout), and
    /// nothing in it is ever read as a key. The app is given its first 16 MiB,
    /// cut back to a whole UTF-8 character, and the rest is dropped as it
    /// arrives, so no paste holds more memory than this, however long it is.
    /// Until 2026-10-11 the limit was 1 MiB and ended paste mode: the rest of
    /// the paste then went to the key parser, and an 8 MiB paste of prose quit
    /// Stress on its first `q`. Why 16 MiB, and what else was weighed:
    /// `Documentation/SwiftUI-API-completion-decisions-PASTE.md`, B-PASTE-1.
    static let maxPasteBytes = 16 << 20

    /// ``maxPasteBytes``, as this terminal applies it.
    ///
    /// Stored rather than read from the constant only so that tests can
    /// lower it: going past the real limit would cost each of them 16 MiB of
    /// input to feed.
    var pasteByteLimit = Terminal.maxPasteBytes

    /// The first ``pasteByteLimit`` bytes of the open paste, set aside when
    /// it ran past the limit, or `nil` while it has not.
    ///
    /// Kept apart from ``input`` so that the bytes behind it can be dropped
    /// as the end-marker scan passes them, and the buffer can shrink back to
    /// its baseline while the rest of the paste streams through it. Cleared
    /// with ``inPasteMode``.
    var keptPaste: [UInt8]?

    /// Frames during which we couldn't make progress on whatever
    /// sits at the front of the input buffer. Increments only when
    /// a drain produced no new bytes *and* the buffer still has an
    /// unparseable partial at the front. Resets on any drained byte
    /// or successful extract.
    ///
    /// Two roles:
    /// - Bare-Esc disambiguation: `0x1B` alone looks identical to
    ///   the first byte of a CSI / SS3 / Alt+key sequence until
    ///   something definitive arrives. After two stale frames
    ///   (~48ms) we *defer* it via ``pendingBareEsc`` rather than
    ///   committing immediately — so a split sequence's late tail
    ///   can still cancel it (see ``resolveStuckPartial()``).
    /// - Stuck-byte recovery: if a malformed or truncated sequence
    ///   sits at the front and the terminal really isn't sending
    ///   anything more, we consume one byte to make progress and
    ///   let the parser try again.
    var staleFrames: Int = 0

    /// Set when a lone `ESC` has gone stale and we've removed it from the
    /// buffer but not yet committed it as the Escape key.
    ///
    /// A `0x1B` at the front is ambiguous: it can be the Escape key, OR the
    /// introducer of a CSI/SS3 sequence (arrow key, mouse report, focus event,
    /// …) or of a terminal reply (a graphics acknowledgement, an OSC colour
    /// answer) whose remaining bytes were split into a later `read()`.
    /// Committing it as Escape too early strands that introducer to be parsed
    /// as a literal keystroke on the next pass — which is how an arrow key
    /// could momentarily register as `[` (e.g. jumping `Example` to its `[` =
    /// Sliders page). So instead we hold the decision one round: the next
    /// ``readEvent()`` re-attaches the `ESC` if an introducer arrived (parsing
    /// the real sequence, no Escape emitted), and otherwise commits the
    /// Escape. `Terminal+Input.swift`'s `continuesEscapeSequence(_:)` is the
    /// one place that says which bytes those are.
    var pendingBareEsc: Bool = false

    /// The `ESC ESC` twin of ``pendingBareEsc``: both ESCs have left the buffer
    /// but the alt+escape chord is held one round, in case the second ESC turns
    /// out to be a split sequence's introducer rather than the Escape key.
    var pendingAltEsc: Bool = false

    /// The family of the over-long escape sequence whose rest the parser is
    /// skipping, or `nil` when it is skipping nothing.
    ///
    /// Set when a sequence runs past ``maxReplyBytes`` with no terminator,
    /// cleared at its terminator, at a new sequence's `ESC`, or after the
    /// dead-sequence wait; see `skipAbandonedSequence()` in
    /// `Terminal+Replies.swift`.
    var abandonedSequence: AbandonedSequence?

    /// The kitty keyboard protocol's enhancements the terminal took when this
    /// process pushed them, or empty for the legacy encodings — which is also
    /// what it is between a pop (exit, suspend) and the push that follows.
    ///
    /// The parser reads it to decide how to read a key: the protocol gives the
    /// legacy forms' shared bits a meaning of their own (see
    /// `KittyKeyDecoder`). Declared here rather than beside the parser because
    /// an extension cannot hold stored properties.
    var keyboardEnhancement: KittyKeyboardFlags = []

    /// What the terminal answered to the kitty keyboard protocol's first
    /// question, asked on the startup colour exchange; `nil` until then, where
    /// it did not answer (it does not speak the protocol), and where it was not
    /// asked.
    var keyboardProtocolAnswer: KittyKeyboardFlags?

    /// What the negotiation pushed, and which of it the terminal said it took,
    /// or `nil` when the terminal does not speak the kitty keyboard protocol
    /// (or was never asked). Kept across a suspend, so the resume pushes the
    /// same flags without asking again.
    var negotiatedKeyboardFlags: (pushed: KittyKeyboardFlags, granted: KittyKeyboardFlags)?

    /// Whether this process's push is on the terminal's stack: a pop is owed.
    var keyboardFlagsPushed = false

    /// What the kitty key decoder remembers from one report to the next — the
    /// keys that are down, so a release is the key its press was. Forgotten
    /// with the protocol, at a pop.
    var keyboardMemory = KittyKeyMemory()

    /// Events one sequence decoded to beyond the first, waiting their turn.
    ///
    /// A kitty key report carries the text its key typed, and an input method
    /// can commit several characters through one key. Each is delivered as a
    /// key event of its own, as the legacy encoding's bytes would be, so all
    /// but the first wait here for the next ``readEvent()``.
    var queuedInputs = InputQueue<TerminalInput>()

    /// Colour answers the terminal volunteered, siphoned out of the keystrokes
    /// by the parser and waiting for the run loop to take them.
    ///
    /// Empty except between a reply landing and the end of that frame's drain,
    /// where `AppRunner` hands what is here to
    /// `RenderLoop.noteVolunteeredColorReplies`. Bounded, because a `Terminal`
    /// with no run loop behind it — a test, a one-off render — never drains it.
    ///
    /// Declared here for the reason the parser state above it is: the code that
    /// owns it lives in `Terminal+Replies.swift`, and an extension cannot hold
    /// stored properties.
    var volunteeredColorReplies: [UInt8] = []

    /// Whether the terminal has answered the fence (`CSI 0 n`) of a colour
    /// request made after the startup exchange, since the run loop last took it.
    ///
    /// Kept apart from ``volunteeredColorReplies`` rather than among them, for
    /// the reason ``takeStatusFence()`` gives: the reply walk stops at a fence.
    var sawVolunteeredStatusFence = false

    /// The raw byte source feeding the parser. Production reads from stdin;
    /// tests inject a closure to script split reads deterministically, since
    /// the parser is otherwise impossible to drive without a live TTY.
    var readSource: (UnsafeMutableBufferPointer<UInt8>) -> Int = { buffer in
        guard let base = buffer.baseAddress else { return 0 }
        while true {
            let n = read(STDIN_FILENO, base, buffer.count)
            // Retry only on EINTR (a signal interrupted the read before any byte
            // arrived); surface everything else — n >= 0, or a real error / the
            // benign EAGAIN of a non-blocking fd with no data — unchanged, which
            // `appendDrain`'s `n > 0` check already handles.
            if n < 0 && errno == EINTR { continue }
            return n
        }
    }

    /// Where everything this terminal writes goes, and how a startup exchange
    /// waits for its reply, or `nil` for the real terminal: stdout, and `poll`
    /// on stdin.
    ///
    /// The other half of ``readSource``, which ``fencedExchange(request:timeout:sawFence:)``
    /// reads through. A test sets both, so an exchange runs against scripted
    /// replies without a TTY, and every byte the terminal is sent — a query,
    /// a mode ``enableRawMode()`` turns on, a frame — can be read back rather
    /// than printed to the console the tests run in. While it is set the
    /// process's termios is left alone and no signal handler is armed: the
    /// scripted terminal is the test's, and the process's own is not.
    var exchangeTransport: ExchangeTransport?

    /// The original terminal settings, on a platform that has them.
    ///
    /// WebAssembly's wasip1 has no `termios`: a wasm program is handed a stream
    /// of bytes and has no line discipline to turn off, because there is none
    /// in front of it. Everything else raw mode does — bracketed paste, the
    /// modifier-key mode, mouse tracking — is escape sequences, and those are
    /// the terminal's business rather than the kernel's, so they are sent on
    /// every platform alike.
    #if !canImport(WASILibc)
        private var originalTermios: termios?

        /// The line discipline a scripted terminal (``exchangeTransport``)
        /// sets instead of standard input's, which belongs to whatever runs
        /// the tests: none, unless a test hands one in.
        var scriptedLineDiscipline: LineDiscipline?

        /// The line discipline raw mode sets: standard input's, or for a
        /// scripted terminal ``scriptedLineDiscipline``.
        var lineDiscipline: LineDiscipline? {
            exchangeTransport == nil ? .standardInput : scriptedLineDiscipline
        }
    #endif

    /// Whether the user's quit key is masked in the driver
    /// (``maskQuitKey(for:)``): the last state set, which a resume's raw mode
    /// is made with too.
    private(set) var quitKeyMasked = false

    /// The app's bindings on the chords the quit key's byte could be, as
    /// last handed to ``maskQuitKey(for:)``: what the mask follows, and what
    /// arms the stall watchdog (``refreshStallWatch()``).
    private(set) var quitKeyBindings = QuitKeyBindings.unbound

    #if !canImport(WASILibc)
        /// The lock every write to standard output takes, shared with the
        /// stall watchdog (`StallWatchdog`), which pops the kitty keyboard
        /// protocol's flags under it while the main loop is stalled — never
        /// in the middle of a frame.
        let writeGate = TerminalWriteGate()
    #endif

    /// What a quit writes ahead of the hand-back, kept current for a
    /// `SIGQUIT`, which skips the teardown: a delete for each image the app
    /// put in the terminal (`TerminalImageStore.farewell(fitting:)`), which
    /// the terminal otherwise keeps for as long as IT runs. The run loop has
    /// it spelled after every frame that put an image in or took one out
    /// (``oweFarewell(for:)``), and it is owed from then on
    /// (``armSignalRestore()``).
    ///
    /// At most ``quitFarewellCapacity`` bytes, whole deletes only: about 150
    /// images. One more is left in the terminal by a `SIGQUIT`, as every image
    /// was before 2026-10-06; an orderly quit deletes them all.
    private(set) var quitFarewell = "" {
        didSet {
            if quitFarewell != oldValue { armSignalRestore() }
        }
    }

    /// The image store's generation ``quitFarewell`` was last spelled from.
    private var owedImageGeneration = 0

    /// Whether frame buffering is active.
    ///
    /// When `true`, ``write(_:)`` appends to ``frameBuffer`` instead of
    /// writing to `STDOUT_FILENO` immediately.
    private var isBuffering = false

    /// Whether the alternate screen is up: entered and not yet left. What a
    /// `SIGQUIT` leaves (``quitDebt``).
    private(set) var isOnAlternateScreen = false

    /// Collects all output bytes during a buffered frame.
    ///
    /// Starts empty, grows via ``write(_:)`` calls, flushed by ``endFrame()``.
    /// Initial capacity of 16 KB covers typical frames without reallocation.
    private var frameBuffer: [UInt8] = []

    /// A copy of the last fully-assembled frame, as it was sent, saved just
    /// before it is flushed to the terminal. Used by
    /// ``dumpLastFrame(inDirectory:)`` so that a debugging snapshot can be
    /// written without re-rendering.
    private(set) var lastFrameData: [UInt8] = []

    /// Whether a frame that writes more than one row holds the terminal's
    /// display while it is drawn (DEC mode 2026, synchronized output): yes,
    /// unless `TUIKIT_SYNCHRONIZED_OUTPUT=0`. See
    /// ``beginSynchronizedUpdate()``.
    let synchronizesOutput: Bool

    /// Where this frame's begin marker sits in ``frameBuffer``, or `nil` when
    /// the frame has none: before ``beginSynchronizedUpdate()``, with
    /// ``synchronizesOutput`` off, and outside a frame.
    private var synchronizedUpdateStart: Int?

    /// How many rows the cursor has been moved to since the begin marker,
    /// counted only as far as the two that decide whether the frame is held.
    private var synchronizedRows = 0

    /// The row the cursor was last moved to since the begin marker, or 0
    /// before the first move (rows count from 1).
    private var synchronizedLastRow = 0

    /// Whether autowrap stays on while the app runs: on Apple Terminal, until
    /// a card measures it there, and everywhere else it goes off
    /// (``outputModesOn``).
    ///
    /// The plan made Apple Terminal's card the precondition
    /// (`Documentation/Ghostty-VT-adoption.md`, K3): its phantom right-edge
    /// repaint (`FrameDiffWriter.repaintRightEdge`) and the peak its clip lets
    /// an over-advancer reach at the last cell were both written against a row
    /// that wraps. So it runs with the terminal's default, which it asserts
    /// (``outputModesOn`` turns autowrap on there) rather than inherits: a
    /// window a killed program left with autowrap off would otherwise run the
    /// clip's bet on a row that does not wrap. Named by the environment, it is
    /// known here; reached over ssh, only once the startup exchange has named
    /// it (``keepAutowrapIfAppleTerminal(environment:)``).
    private(set) var keepsAutowrap: Bool

    /// Creates a new terminal instance.
    ///
    /// - Parameter environment: Where `TUIKIT_SYNCHRONIZED_OUTPUT` is read
    ///   from, and the host that decides ``keepsAutowrap``: the process's
    ///   own, unless a test poses another.
    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        frameBuffer.reserveCapacity(16_384)
        synchronizesOutput = Self.synchronizedOutputAllowed(environment: environment)
        // The pure detector, not `TerminalHost.isAppleTerminal`: that one
        // freezes on its first read, which must wait for the startup exchange.
        keepsAutowrap = TerminalHost.detectAppleTerminal(environment: environment)
    }

    /// Destructor ensures raw mode is disabled.
    ///
    /// Note: `deinit` cannot be actor-isolated, so we use `MainActor.assumeIsolated`,
    /// which is safe because `Terminal` instances are created and released under
    /// main-actor isolation (in `AppRunner`) — the last reference goes away there,
    /// so this runs in the main actor's context.
    ///
    /// The isolation is the guarantee, not a thread: which OS thread drains the
    /// main actor is not fixed, and on Linux it is a cooperative pool thread
    /// rather than the process main thread (measured; see the "Thread
    /// correctness" note in TUIkitCore's `StackGuard`).
    deinit {
        if isRawMode {
            MainActor.assumeIsolated {
                disableRawMode()
            }
        }
    }
}

// MARK: - Internal API

extension Terminal {
    /// Returns the current terminal size.
    ///
    /// - Returns: A tuple with width and height in characters/lines.
    func getSize() -> (width: Int, height: Int) {
        // No `ioctl` on wasip1, and nothing to ask it: a wasm program has no
        // controlling terminal to measure. The environment fallback below is
        // the whole answer there, which is why a WebAssembly host has to put the
        // size in `COLUMNS`/`LINES` — see `Documentation/WebAssembly.md`.
        #if !canImport(WASILibc)
            var windowSize = winsize()

            #if canImport(Glibc) || canImport(Musl)
                let result = ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &windowSize)
            #else
                let result = ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize)
            #endif

            if result == 0 && windowSize.ws_col > 0 && windowSize.ws_row > 0 {
                return (Int(windowSize.ws_col), Int(windowSize.ws_row))
            }
        #endif

        // Fallback to environment variables.
        //
        // Validated, not just parsed: `COLUMNS` / `LINES` are ordinary
        // environment variables that anything may set — a shell's
        // `checkwinsize`, a multiplexer, a CI runner, a stale export inherited
        // from a since-resized window. `Int("0")` succeeds, so an unvalidated
        // parse hands back a 0-row terminal from a *fallback* path that exists
        // precisely because the real size was unavailable. Only a positive
        // value is a size; anything else means "unknown", which is what the
        // 80x24 default is for.
        let cols = terminalDimension(fromEnvironment: "COLUMNS") ?? 80
        let rows = terminalDimension(fromEnvironment: "LINES") ?? 24

        return (cols, rows)
    }

    /// Parses an environment variable as a terminal dimension, accepting only a
    /// positive count; `nil` when unset, unparseable, or non-positive.
    ///
    /// `environment` is the process's own unless a caller poses the question
    /// on a dictionary, as `ColorDepth.detect(environment:)` does, which asks
    /// it without writing the one environment every thread reads.
    func terminalDimension(
        fromEnvironment name: String,
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int? {
        guard let raw = environment[name],
            let value = Int(raw),
            value > 0
        else { return nil }
        return value
    }

    /// The terminal cell's height-to-width ratio, derived from the window's
    /// reported pixel size, or `nil` when the terminal doesn't report it.
    ///
    /// `TIOCGWINSZ` also carries the drawable area in pixels (`ws_xpixel`,
    /// `ws_ypixel`); dividing by the cell grid gives each cell's pixel size, and
    /// their ratio is the aspect an undistorted image needs (see
    /// ``View/imageCellAspect(_:)``). Not every terminal fills these fields —
    /// some report `0` — in which case this returns `nil` and callers keep their
    /// default. This self-corrects for the terminal + font + line spacing on the
    /// terminals that do report it, without any escape-sequence round trip.
    func cellPixelAspect() -> Double? {
        #if canImport(WASILibc)
            // The pixel fields ride on the same `ioctl` the size does, so this
            // is unavailable for the same reason; callers keep their default
            // aspect, which is what they do on the terminals that report zero.
            return nil
        #else
        var windowSize = winsize()
        #if canImport(Glibc) || canImport(Musl)
            let result = ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &windowSize)
        #else
            let result = ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize)
        #endif
        guard result == 0,
            windowSize.ws_col > 0, windowSize.ws_row > 0,
            windowSize.ws_xpixel > 0, windowSize.ws_ypixel > 0
        else { return nil }

        let cellWidth = Double(windowSize.ws_xpixel) / Double(windowSize.ws_col)
        let cellHeight = Double(windowSize.ws_ypixel) / Double(windowSize.ws_row)
        guard cellWidth > 0 else { return nil }
        let aspect = cellHeight / cellWidth
        // Guard against nonsense (a cell that's wider than tall, or absurdly
        // tall) so a misreporting terminal can't distort worse than the default.
        return (aspect >= 1.0 && aspect <= 4.0) ? aspect : nil
        #endif
    }

    /// Enables raw mode for direct character handling.
    ///
    /// In raw mode:
    /// - Each keystroke is reported immediately (without Enter)
    /// - Echo is disabled
    /// - Ctrl+C and Ctrl+Z arrive as keys, not as signals, while the user's
    ///   quit key (`⌃\`) still quits, by `SIGQUIT`
    ///   (``rawModeAttributes(from:)``)
    func enableRawMode() {
        guard !isRawMode else { return }

        // A scripted terminal (``exchangeTransport``) has no line discipline
        // of its own, and the one on stdin then belongs to whatever runs the
        // tests (``lineDiscipline``).
        #if !canImport(WASILibc)
            if let lineDiscipline, let original = lineDiscipline.get() {
                originalTermios = original
                lineDiscipline.set(
                    Self.rawModeAttributes(from: original, maskingQuitKey: quitKeyMasked), TCSAFLUSH)
            }
        #endif
        isRawMode = true

        // The defaults every frame relies on, asserted rather than assumed:
        // a program killed before it put them back leaves them for the next
        // one (``inheritedDefaults``). Then the output modes TUIkit runs in,
        // which ``disableRawMode()`` puts back (``outputModesOn``).
        writeImmediate(Self.inheritedDefaults + outputModesOn)

        // Enable bracketed paste mode so that terminal paste operations
        // are wrapped in ESC[200~ ... ESC[201~ markers. This allows the
        // application to detect pasted text and insert it as a single
        // bulk operation instead of processing each character individually.
        writeImmediate("\u{1B}[?2004h")

        // Ask for focus reports (mode 1004): `ESC [ I` when the window, tab or
        // pane gains focus and `ESC [ O` when it loses it, which the run loop
        // turns into `ScenePhase.inactive` and back. Always on. A terminal
        // without the mode ignores the request and never reports, and neither
        // does tmux without `focus-events on`, so the phase then simply stays
        // `.active`. A report sent the moment this is enabled can be swallowed
        // by the startup queries that read stdin next. See
        // Documentation/Terminal-compatibility.md, "Focus reporting (mode 1004)".
        writeImmediate("\u{1B}[?1004h")

        // Ask to be told when the terminal's own palette changes (DEC mode
        // 2031): it then sends `CSI ? 997 ; Ps n`, which `TerminalColorRefresher`
        // turns into asking what it paints now. Without it, a theme flipped
        // under a running app goes unnoticed until something else asks — a
        // resize, or the window taking the focus back.
        //
        // Sent to every host, measured or not, as the focus request above is.
        // On the five hosts measured (2026-09-14) it printed nothing and moved
        // no cursor, and tmux sets it on its own clients at attach; Ghostty is
        // unmeasured. Its DECRQM is never sent: `CSI ? Ps $ p` is the
        // `?`-plus-intermediate shape Apple Terminal prints, and the answer
        // would only say whether the mode this process just set is set. See
        // Documentation/Terminal-compatibility.md, "Colour-palette update
        // notifications (mode 2031)".
        writeImmediate("\u{1B}[?2031h")

        // Ask xterm-compatible terminals (iTerm2, Ghostty, kitty, wezterm,
        // gnome-terminal, …) to report modified cursor keys in canonical
        // `ESC[1;<mod><letter>` form so that combinations like
        // Shift+Option+Left arrive with both modifier bits set. Without
        // this, many terminals fall back to a stripped form that drops
        // the Option modifier and reports only Shift.
        //
        //   `CSI > 1 ; 2 m`  — modifyCursorKeys = 2 (canonical reporting)
        //
        // macOS Terminal.app ignores this hint; users on Terminal.app who
        // want word-level Shift+Option selection need to remap the key in
        // its preferences (or use a terminal with full modifier support).
        writeImmediate("\u{1B}[>1;2m")

        // The kitty keyboard protocol, on the way back from a suspend: the
        // flags negotiated at startup, pushed again without asking. At
        // startup nothing is negotiated yet, so this does nothing; the
        // negotiation pushes once it has its answer.
        repushKeyboardFlags()

        // Should the process die of a signal from here on, the modes just
        // turned on and the shell's termios are owed back.
        armSignalRestore()
        refreshStallWatch()

        // Mouse tracking is now managed dynamically by
        // ``applyMouseSupport(_:)`` — see ``MouseSupport`` for the
        // selection of tracking modes. We always end up enabling SGR
        // extended position reporting (?1006h) when any mouse feature
        // is requested.
    }

    /// Masks the user's quit key in the driver, or gives it back, for the
    /// app's declared `bindings` on the chords its byte could be
    /// (`InputHandler.quitKeyBindings(byte:hostAliases:)`), asked after
    /// every frame: masked for a binding on the quit key's own chord, and for
    /// one on ⌃4, ⌃| or ⌃⇧\ only in the legacy encoding, where they may be
    /// its byte (``QuitKeyBindings/masksQuitKey(inLegacyEncoding:)``).
    ///
    /// The owner's rule (2026-10-06): the driver's quit is the backup that
    /// ends a hung app, and stays live unless the app binds the key — ⌃\\
    /// itself, or ⌃4, ⌃| or ⌃⇧\ where the terminal may send ⌃\\'s byte for
    /// them — and then the byte arrives as a key, which the app's bindings
    /// hear first and which quits where none takes it (`InputHandler`). What
    /// that costs: while masked, a HUNG app does not quit by the key. Nor,
    /// under the kitty keyboard protocol, while a binding on ⌃4, ⌃| or ⌃⇧\\
    /// is on screen, though the driver's quit is live there: the stall
    /// watchdog is not armed for it (``refreshStallWatch()``).
    ///
    /// Sets the line discipline only when the mask changes, and at once
    /// (`TCSANOW`: unlike raw mode's own `TCSAFLUSH`, no typed-ahead input is
    /// thrown away). Kept across a suspend: the resume's raw mode is made
    /// with it. The teardown puts the user's termios back whole, as ever.
    func maskQuitKey(for bindings: QuitKeyBindings) {
        let masked = bindings.masksQuitKey(inLegacyEncoding: keyboardEnhancement.isEmpty)
        guard bindings != quitKeyBindings || masked != quitKeyMasked else { return }
        quitKeyBindings = bindings
        let maskChanged = masked != quitKeyMasked
        quitKeyMasked = masked
        refreshStallWatch()
        #if !canImport(WASILibc)
            guard maskChanged, isRawMode, let lineDiscipline, let original = originalTermios else { return }
            lineDiscipline.set(Self.rawModeAttributes(from: original, maskingQuitKey: masked), TCSANOW)
        #endif
    }

    /// Arms the stall watchdog while it can do some good, and disarms it
    /// otherwise: armed while raw mode is on, the kitty keyboard protocol's
    /// flags are pushed, and the user's quit key is live in the driver — not
    /// turned off by the user — and would stay live after the watchdog's
    /// pop: the app declares no binding on a chord its byte could be in the
    /// legacy encoding the pop puts the terminal in (``quitKeyBindings``).
    /// Called at each of those changes.
    ///
    /// The legacy encoding's answer, not the protocol's: under the protocol
    /// a ⌘4 shortcut (⌃4) leaves the driver's quit live, since ⌃4 arrives
    /// as itself — but after a pop the terminal may send ⌃\\'s 0x1C for ⌃4
    /// (kitty, Ghostty, WezTerm and foot do, by the protocol's table of the
    /// legacy encoding), and the driver, never told to mask it, would quit
    /// the app on the user's ⌃4 during a slow frame. So with one on screen a
    /// hung app does not quit by ⌃\ under the protocol either, as it does
    /// not where the quit is masked.
    func refreshStallWatch() {
        #if !canImport(WASILibc)
            writeGate.setArmed(
                isRawMode && keyboardFlagsPushed && quitKeyByte != nil && quitKeyBindings == .unbound)
        #endif
    }

    /// The user's quit key, as the byte a legacy encoding sends for it: what
    /// the driver turns into `SIGQUIT` while raw mode is on
    /// (``rawModeAttributes(from:)``) — ⌃\\'s 0x1C unless the user moved it —
    /// or `nil` where there is none: turned off, signals off, or no line
    /// discipline (a scripted terminal, wasip1). Read from the termios raw
    /// mode was made from, so `nil` until raw mode is first on. Where the
    /// terminal speaks the kitty keyboard protocol the key arrives as a
    /// report instead, which the input chain offers the app's bindings and
    /// turns into the signal where none takes it (`InputHandler.quitKey`).
    /// The user's key whether or not the driver's quit is masked
    /// (``maskQuitKey(for:)``).
    var quitKeyByte: UInt8? {
        #if canImport(WASILibc)
            return nil
        #else
            return originalTermios.flatMap(Self.quitKeyByte(of:))
        #endif
    }

    /// Disables raw mode and restores normal terminal operation.
    func disableRawMode() {
        guard isRawMode else { return }

        // The output modes back first (``outputModesOff``): a frame's hold on
        // the display let go, should a failed write have left one open, so
        // what the shell is handed is shown at once; and autowrap on.
        writeImmediate(outputModesOff)

        // The kitty keyboard protocol's flags off first, while the alternate
        // screen whose stack they were pushed on is still up, so the keys the
        // shell reads next are the legacy bytes it expects.
        popKeyboardFlags()

        writeImmediate(Self.inputModesOff)
        appliedMouseMode = .none

        // Put grapheme clustering back only if we turned it on: the mode
        // outlives the process, so leaving it changed would hand the next
        // program a terminal we reconfigured.
        if pinnedGraphemeClustering {
            writeImmediate(Self.graphemeClusteringOff)
            pinnedGraphemeClustering = false
        }

        // Absent only where ``enableRawMode()`` left the termios alone: a
        // scripted terminal's.
        #if !canImport(WASILibc)
            if let original = originalTermios {
                lineDiscipline?.set(original, TCSAFLUSH)
            }
        #endif
        isRawMode = false
        refreshStallWatch()
        // Torn down in order: a signal from here on owes the terminal nothing.
        if exchangeTransport == nil { FatalSignalTerminalRestore.disarm() }
    }

    /// The terminal state a frame takes for granted, put back to the power-on
    /// defaults by ``enableRawMode()``, at startup and on every resume.
    ///
    /// Each of these outlives the program that set it, so a killed `vim`,
    /// `less` or `htop`, or a shell that sends terminfo's `smkx` without its
    /// `rmkx`, hands the next program a terminal that is not in its defaults:
    ///
    /// - `CSI r` (DECSTBM, no parameters): the scrolling region back to the
    ///   whole screen. With origin mode off an absolute cursor move ignores a
    ///   region; what one left by a crashed program confines is scrolling — a
    ///   line feed at its bottom margin scrolls only the region — which no
    ///   frame does today, and which hardware scrolling (the adoption plan's
    ///   O2) will rely on, with a region of its own.
    /// - `CSI ? 69 l`: left-right margin mode (DECLRMM) off. While it is on,
    ///   left and right margins a program set (DECSLRM; tmux sets them where
    ///   the terminal has them) stop or wrap every row at the right margin,
    ///   and `CSI s` sets margins instead of saving the cursor. Off, margins
    ///   do not apply, and resetting it puts them back to the full width
    ///   (xterm's control-sequence notes and the VT510 manual say so).
    /// - `CSI ? 6 l`: origin mode (DECOM) off. On, every row (and column) number
    ///   is taken relative to the region and the margins and clamped into
    ///   them: this, not the region alone, is what offsets or clamps a frame.
    /// - `CSI ? 1 l`: cursor keys back to normal mode (DECCKM), so arrows,
    ///   Home and End arrive as `CSI A`… rather than their SS3 spellings —
    ///   which the parser reads as well, for a terminal that sends them
    ///   anyway (`KeyEvent.parse`).
    /// - `ESC >`: the keypad back to numeric mode (DECKPNM), so its keys
    ///   arrive as the characters on them.
    ///
    /// None is restored on the way out: these are the defaults a shell
    /// expects. All five are shapes Apple Terminal consumes: `CSI r` has no
    /// `?` and no intermediate byte, `?69l`, `?6l` and `?1l` a `?` and no
    /// intermediate (`Documentation/Terminal-compatibility.md`, "Asking the
    /// terminal — Device Attributes"), and `ESC >` is a two-byte VT100
    /// escape. Found by reading Ghostty's VT reference
    /// (`Documentation/Ghostty-VT-adoption.md`, K2; DECLRMM, which K6 names,
    /// joined in review).
    static let inheritedDefaults = "\u{1B}[r" + "\u{1B}[?69l" + "\u{1B}[?6l" + "\u{1B}[?1l" + "\u{1B}>"

    /// Turns off every input mode ``enableRawMode()`` turned on, in one write
    /// — the orderly teardown's, and the debt a signal pays
    /// (``armSignalRestore()``):
    ///
    /// - modifyCursorKeys back to the terminal's default;
    /// - every mouse tracking mode this process might have enabled, and SGR
    ///   coordinates (a terminal ignores a disable for a mode that is not on);
    /// - focus reports, so the shell (or whatever runs after a suspend or
    ///   quit) is not sent `ESC [ I` / `ESC [ O` it never asked for;
    /// - palette-change reports (mode 2031), for the same reason: the mode
    ///   outlives this process, and the shell never asked to be told about
    ///   themes;
    /// - bracketed paste.
    static let inputModesOff =
        "\u{1B}[>1;0m"
        + "\u{1B}[?1006l\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l"
        + "\u{1B}[?1004l"
        + "\u{1B}[?2031l"
        + "\u{1B}[?2004l"

    /// Puts back the grapheme-clustering mode this process pinned on
    /// (``pinnedGraphemeClustering``).
    static let graphemeClusteringOff = "\u{1B}[?\(TerminalModeQuery.graphemeClustering)l"

    /// The output modes TUIkit runs in, set by ``enableRawMode()`` at startup
    /// and on every resume, and put back by ``outputModesOff``:
    ///
    /// - Autowrap off (DECAWM, `CSI ? 7 l`), except where it is kept on
    ///   (``keepsAutowrap``: Apple Terminal, until its card), where it is
    ///   turned on (`CSI ? 7 h`), as the inherited defaults are asserted, not
    ///   assumed. Every row TUIkit
    ///   writes is as wide as the screen by its own count, and nothing it draws
    ///   relies on wrapping. Where a host advances a cluster further than
    ///   TUIkit counted — a host it has not measured, or iTerm2 with
    ///   "ambiguous characters are wide" — the row wrapped into the next one,
    ///   and on the bottom row scrolled the whole screen up a line, leaving the
    ///   diff writer's picture of the screen wrong until something invalidated
    ///   it. With autowrap off the row loses its own last cells instead. Costs
    ///   nothing per frame. `?`, no intermediate byte: the shape Apple Terminal
    ///   consumes, which matters because over ssh it is sent before the host
    ///   is known. Found by reading Ghostty's VT reference
    ///   (`Documentation/Ghostty-VT-adoption.md`, K3).
    var outputModesOn: String {
        keepsAutowrap ? Self.autowrapOn : Self.autowrapOff
    }

    /// `CSI ? 7 l`: autowrap (DECAWM) off.
    static let autowrapOff = "\u{1B}[?7l"

    /// `CSI ? 7 h`: autowrap (DECAWM) on, every terminal's default.
    static let autowrapOn = "\u{1B}[?7h"

    /// Puts autowrap back on for good if the startup exchange has just named
    /// Apple Terminal (``keepsAutowrap``), which the environment did not:
    /// reached over ssh, it was sent ``outputModesOn`` before anything knew
    /// which host it was. Does nothing otherwise, and nothing a second time.
    ///
    /// - Parameter environment: The process's environment, where the exchange
    ///   seeds what it found (`TerminalHost.seedDiscoveredHost(_:)`).
    func keepAutowrapIfAppleTerminal(environment: [String: String]) {
        guard !keepsAutowrap, TerminalHost.detectAppleTerminal(environment: environment) else { return }
        keepsAutowrap = true
        if isRawMode { writeImmediate(Self.autowrapOn) }
    }

    /// Puts back every output mode the frames may have changed, in one write —
    /// the orderly teardown's, and the head of the debt a signal pays:
    ///
    /// - the end of a synchronized update (``synchronizedUpdateEnd``), where
    ///   frames are held at all. A frame sends its own end marker in the
    ///   write that sends its begin marker, so this matters only where that
    ///   write failed partway, or a signal landed in the middle of it. Then
    ///   the terminal goes on holding its display: Ghostty for a second (its
    ///   `sync_reset_ms`), other hosts for as long as they do, unmeasured.
    ///   Harmless where nothing is held.
    /// - autowrap back on (`CSI ? 7 h`), the default a shell expects:
    ///   ``outputModesOn`` turned it off. Not per screen, so leaving the
    ///   alternate screen does not put it back. Sent where it was kept on too:
    ///   harmless there, and one debt for every host.
    var outputModesOff: String {
        (synchronizesOutput ? Self.synchronizedUpdateEnd : "") + Self.autowrapOn
    }

    /// What the terminal is owed, should the process die of a signal now:
    /// everything it has been changed by — the output modes, the kitty flags
    /// if pushed, the input modes, a pinned grapheme-clustering mode, the
    /// hidden cursor. ``armSignalRestore()`` hands it to
    /// ``FatalSignalTerminalRestore`` with the shell's termios.
    var signalDebt: String {
        var owed = outputModesOff
        if keyboardFlagsPushed { owed += KeyboardProtocolQuery.pop }
        owed += Self.inputModesOff
        if pinnedGraphemeClustering { owed += Self.graphemeClusteringOff }
        owed += ANSIRenderer.showCursor
        return owed
    }

    /// What the terminal is owed should the process die of `SIGQUIT`, the
    /// user's quit key: what a quit writes (``handBack(farewell:restoringStyling:)``),
    /// in a quit's order — the farewell (``quitFarewell``), the styling reset
    /// (`RenderLoop.restoreTerminalStyling()`), ``signalDebt``, which is raw
    /// mode's teardown and the cursor shown, and the alternate screen left
    /// (``isOnAlternateScreen``). Unlike a crash, a quit has no report to keep
    /// on the screen.
    var quitDebt: String {
        quitFarewell + ANSIRenderer.reset + signalDebt
            + (isOnAlternateScreen ? ANSIRenderer.exitAlternateScreen : "")
    }

    /// Keeps ``quitFarewell`` in step with `images`, after a frame: one
    /// integer compare, and the deletes spelled again only when the frame put
    /// an image in or took one out.
    func oweFarewell(for images: TerminalImageStore) {
        guard images.generation != owedImageGeneration else { return }
        owedImageGeneration = images.generation
        quitFarewell = images.farewell(fitting: Self.quitFarewellCapacity)
    }

    /// The most bytes ``quitFarewell`` may be: what the signal handler's
    /// buffer holds beyond the rest of ``quitDebt``.
    nonisolated static let quitFarewellCapacity = 4096

    /// Owes the terminal ``signalDebt``, or ``quitDebt`` for a `SIGQUIT`, and
    /// the shell's termios, should the process die of a signal now; see
    /// ``FatalSignalTerminalRestore``. Called whenever the debt changes while
    /// raw mode is on: raw mode itself, a push or pop of the kitty flags, a
    /// pin, the alternate screen entered or left.
    ///
    /// A scripted terminal is a test's, and the process's signal handlers are
    /// not its to install.
    func armSignalRestore() {
        #if !canImport(WASILibc)
            guard isRawMode, exchangeTransport == nil else { return }
            FatalSignalTerminalRestore.arm(owing: signalDebt, onQuit: quitDebt, restoring: originalTermios)
        #endif
    }

    /// Updates the terminal's mouse-tracking mode to match the
    /// effective mouse-support configuration.
    ///
    /// Picks the lowest-impact tracking mode that satisfies the
    /// configuration (1000 → clicks only, 1002 → adds drag, 1003 →
    /// adds motion). SGR extended coordinate reporting is enabled
    /// whenever any tracking mode is active.
    ///
    /// Idempotent: only writes escape codes when the effective mode
    /// differs from the last applied mode, so it's cheap to call
    /// every frame.
    func applyMouseSupport(_ support: MouseSupport) {
        let target = trackingMode(for: support)
        guard target != appliedMouseMode else { return }

        // Turn off the previous mode (if any) before turning on the
        // new one. Disabling a mode that isn't active is a no-op on
        // every terminal we care about, so this also handles the
        // "stale state from a crashed prior process" case.
        if appliedMouseMode != .none {
            writeImmediate("\u{1B}[?\(appliedMouseMode.escapeNumber)l")
        }
        if target != .none {
            writeImmediate("\u{1B}[?\(target.escapeNumber)h")
            // SGR coords are paired with whichever tracking mode is on.
            writeImmediate("\u{1B}[?1006h")
        } else {
            writeImmediate("\u{1B}[?1006l")
        }
        appliedMouseMode = target
    }

    /// The tracking modes we know about. Higher values are strict
    /// supersets of lower ones.
    enum MouseTrackingMode: Equatable {
        case none
        case clicks       // ?1000h — press/release/scroll
        case drag         // ?1002h — adds drag motion
        case motion       // ?1003h — adds any-event motion

        var escapeNumber: Int {
            switch self {
            case .none: return 0
            case .clicks: return 1000
            case .drag: return 1002
            case .motion: return 1003
            }
        }
    }

    /// Picks the smallest tracking mode that satisfies the
    /// requested feature set.
    private func trackingMode(for support: MouseSupport) -> MouseTrackingMode {
        if support.motion { return .motion }
        if support.drag { return .drag }
        if support.clicks || support.scrolling { return .clicks }
        return .none
    }

    /// Begins a buffered frame.
    ///
    /// After this call, all ``write(_:)`` calls append to an internal
    /// `[UInt8]` buffer instead of issuing syscalls. Call ``endFrame()``
    /// to flush the collected output in a single `write()` syscall.
    func beginFrame() {
        guard !isBuffering else { return }
        isBuffering = true
        frameBuffer.removeAll(keepingCapacity: true)
        synchronizedUpdateStart = nil
    }

    /// Ends a buffered frame and flushes all collected output: held, if it
    /// began a synchronized update and went on to write more than one row,
    /// and without its begin marker if it began one and did not (see
    /// ``beginSynchronizedUpdate()``).
    func endFrame() {
        guard isBuffering else { return }
        isBuffering = false
        guard let start = synchronizedUpdateStart else {
            lastFrameData = frameBuffer          // snapshot before flush
            flushBuffer()
            return
        }
        synchronizedUpdateStart = nil
        if synchronizedRows > 1 {
            frameBuffer.append(contentsOf: Self.synchronizedUpdateEnd.utf8)
            lastFrameData = frameBuffer
            flushBuffer(holdingDisplay: true)
        } else {
            let marker = start..<(start + Self.synchronizedUpdateBegin.utf8.count)
            lastFrameData = frameBuffer
            lastFrameData.removeSubrange(marker)
            flushBuffer(omitting: marker)
        }
    }

    /// `CSI ? 2026 h`: the terminal holds its display until the end marker.
    static let synchronizedUpdateBegin = "\u{1B}[?2026h"

    /// `CSI ? 2026 l`: the terminal shows what the hold kept back.
    static let synchronizedUpdateEnd = "\u{1B}[?2026l"

    /// Begins this frame's synchronized update (DEC mode 2026, synchronized
    /// output) here: after the image transmissions, before the first cell.
    ///
    /// The terminal holds its display between `CSI ? 2026 h` and
    /// `CSI ? 2026 l`, so a frame that reaches it in several reads is shown
    /// whole rather than torn. Ghostty's help names the defect: an app that
    /// redraws a large area tears or flickers, worst where it erases a row and
    /// then redraws it — which is what a whole-line row is, `ESC[2K` and its
    /// content. The begin marker goes into the frame buffer here, and
    /// ``endFrame()`` decides whether to keep it:
    ///
    /// - A frame that moved the cursor to more than one row keeps it, and gets
    ///   the end marker after its last byte: one write, 16 bytes more.
    /// - Any other frame — a single row (a breath, a caret's blink), or none —
    ///   cannot tear, and goes out without it, as the parts either side of
    ///   the marker. Nothing is copied: with nothing before the marker, which
    ///   is every frame with no image to transmit, that is one write starting
    ///   8 bytes in.
    ///
    /// Image transmissions stay outside the hold: they draw nothing, and they
    /// can be megabytes, which inside it could outlast Ghostty's one-second
    /// limit on a hold (`sync_reset_ms`) and show the frame half drawn anyway.
    ///
    /// Sent to every host, as the startup's mode requests are. A terminal
    /// without the mode ignores it: `CSI ? Pm h` has a `?` and no intermediate
    /// byte, the shape measured clean on Apple Terminal, iTerm2, Ghostty and
    /// Warp (`Documentation/Terminal-compatibility.md`, "Asking the terminal —
    /// Device Attributes"). Nothing is asked first: its DECRQM query is the
    /// one shape Apple Terminal prints, and setting the mode needs no answer.
    /// `TUIKIT_SYNCHRONIZED_OUTPUT=0` turns it off, should a terminal take it
    /// badly; see "Synchronized output (mode 2026)" there.
    ///
    /// Does nothing outside a frame, a second time in one, or when turned off.
    func beginSynchronizedUpdate() {
        guard synchronizesOutput, isBuffering, synchronizedUpdateStart == nil else { return }
        synchronizedUpdateStart = frameBuffer.count
        synchronizedRows = 0
        synchronizedLastRow = 0
        frameBuffer.append(contentsOf: Self.synchronizedUpdateBegin.utf8)
    }

    /// Whether the environment lets frames be held at all: yes, unless
    /// `TUIKIT_SYNCHRONIZED_OUTPUT` is `0` — the user's way out, in the shape
    /// of `TUIKIT_KEYBOARD_PROTOCOL=0`.
    nonisolated static func synchronizedOutputAllowed(environment: [String: String]) -> Bool {
        environment["TUIKIT_SYNCHRONIZED_OUTPUT"] != "0"
    }

    /// Writes a string to the terminal.
    ///
    /// When frame buffering is active (between ``beginFrame()`` and
    /// ``endFrame()``), the string's UTF-8 bytes are appended to the
    /// internal buffer. Otherwise, the bytes are written directly to
    /// `STDOUT_FILENO` via the POSIX `write` syscall.
    ///
    /// - Parameter string: The string to write.
    func write(_ string: String) {
        if isBuffering {
            appendToBuffer(string)
        } else {
            writeImmediate(string)
        }
    }

    /// Moves the cursor to the specified position.
    ///
    /// - Parameters:
    ///   - row: The row (1-based).
    ///   - column: The column (1-based).
    func moveCursor(toRow row: Int, column: Int) {
        // A row of its own counts toward holding the frame; see
        // ``beginSynchronizedUpdate()``. Every row a frame draws starts with a
        // move to it.
        if synchronizedUpdateStart != nil, synchronizedRows < 2, row != synchronizedLastRow {
            synchronizedRows += 1
            synchronizedLastRow = row
        }
        write(ANSIRenderer.moveCursor(toRow: row, column: column))
    }

    /// Hides the cursor.
    func hideCursor() {
        write(ANSIRenderer.hideCursor)
    }

    /// Shows the cursor.
    func showCursor() {
        write(ANSIRenderer.showCursor)
    }

    /// Switches to the alternate screen buffer.
    func enterAlternateScreen() {
        write(ANSIRenderer.enterAlternateScreen)
        isOnAlternateScreen = true
        armSignalRestore()
    }

    /// Exits the alternate screen buffer.
    func exitAlternateScreen() {
        write(ANSIRenderer.exitAlternateScreen)
        isOnAlternateScreen = false
        armSignalRestore()
    }

    /// Hands the terminal back to the shell: what a quit and a suspend write
    /// on the way out, in their order — `farewell` (a quit's, or nothing),
    /// the styling the last frame left in force reset (`restoreStyling`),
    /// raw mode off (``disableRawMode()``), the cursor shown and the
    /// alternate screen left. ``quitDebt`` is these bytes for a `SIGQUIT`,
    /// which skips the teardown, and a test holds the two to each other.
    ///
    /// - Parameters:
    ///   - farewell: What the app owes the terminal before it lets go: a
    ///     quit's image deletes (`TerminalImageStore.releaseAll()`) and the
    ///     clipboard copies no frame has written yet
    ///     (`ClipboardWriter.takePendingSequences()`).
    ///   - restoreStyling: Resets the styling a frame left in force, which
    ///     leaving the alternate screen does not:
    ///     `RenderLoop.restoreTerminalStyling()`.
    func handBack(farewell: String = "", restoringStyling restoreStyling: () -> Void) {
        if !farewell.isEmpty { write(farewell) }
        restoreStyling()
        disableRawMode()
        showCursor()
        exitAlternateScreen()
    }

    /// Removes `n` bytes from the front of the buffer and, if the
    /// resulting size fits back inside ``baselineCapacity``, shrinks
    /// the backing allocation down too. The shrink is the reason
    /// for the explicit `reallocate(capacity:)` call: ``InputByteBuffer``
    /// grows geometrically (1.5×) when needed but doesn't shrink on
    /// its own, so we have to ask.
    func consume(_ n: Int) {
        input.removeFirst(n)
        if input.count <= Self.baselineCapacity
            && input.capacity > Self.baselineCapacity
        {
            input.reallocate(capacity: Self.baselineCapacity)
        }
    }

    /// Drains whatever stdin has waiting straight into the buffer's
    /// free tail storage, with zero intermediate copies: one `read()`
    /// (through ``readSource``) into the contiguous room
    /// ``InputByteBuffer/append(upTo:from:)`` makes at the back, which
    /// keeps exactly the bytes `read()` says it wrote.
    ///
    /// - Returns: the number of new bytes drained from stdin.
    @discardableResult
    func appendDrain() -> Int {
        // Up to one chunk at a time. The buffer makes that much room
        // first, sliding or growing as it must; subsequent drains can
        // reuse the expanded capacity.
        input.append(upTo: Self.readChunk, from: readSource)
    }

    /// Waits until `descriptor` has bytes to read, or `deadline` passes.
    ///
    /// NOT a bare `poll`, and the difference is the whole point: `poll` returns
    /// `-1`/`EINTR` whenever a signal handler runs during the wait, and it is
    /// one of the calls POSIX explicitly says `SA_RESTART` does *not* restart.
    /// A caller that reads that as "the terminal said nothing" abandons its
    /// probe with time still on the clock — so an `EINTR` resumes the wait
    /// against the SAME deadline, never a fresh timeout, which is what stops a
    /// storm of signals from extending the probe past its budget.
    ///
    /// The asymmetry is why this went unnoticed. On Darwin ``SignalManager``
    /// installs `SIG_IGN` and lets kqueue deliver the signal, so no handler
    /// runs and `poll` is never interrupted; on Linux libdispatch installs and
    /// owns the handler, so dragging the terminal window (or a multiplexer
    /// resizing the pane) during the ~500 ms startup handshake is enough to cut
    /// a probe short. The one that costs most is `queryGraphicsSupport`:
    /// abandoned, it disables image placement for the whole session, silently.
    ///
    /// The sibling ``readSource`` already retries `EINTR` by name; this is that
    /// rule for the wait rather than the read, in one place so the three probes
    /// that need it cannot drift apart.
    ///
    /// `nonisolated` because it touches no terminal state — it is a `poll` and
    /// a clock. Every caller happens to be on the main actor; nothing here
    /// requires it, and a blocking wait has no business claiming isolation it
    /// does not need.
    ///
    /// - Parameters:
    ///   - descriptor: The file descriptor to wait on. Defaults to standard
    ///     input, which is what every probe uses; the parameter exists so the
    ///     retry can be driven over a pipe in a test, the same kind of seam
    ///     ``readSource`` opens for the parser.
    ///   - deadline: When to give up.
    /// - Returns: `true` when the descriptor is readable, `false` on the
    ///   deadline or on any error that is not `EINTR`.
    nonisolated static func waitForInput(
        on descriptor: Int32 = STDIN_FILENO, until deadline: Date
    ) -> Bool {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }
            var target = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&target, 1, Int32(remaining * 1000))
            if ready > 0 { return true }
            // `errno` is thread-local and transient, so it is read here, before
            // anything else can overwrite it.
            guard ready < 0, errno == EINTR else { return false }
        }
    }

    /// Asks the terminal to identify itself, and returns the
    /// `TERM_PROGRAM`-style name of the host if its answers name one.
    ///
    /// The startup half of ``TerminalIdentityQuery`` — see there for what is
    /// asked and why it is safe to ask it. This half is the I/O: one write, then
    /// read until the DSR fence comes back or `timeout` elapses.
    ///
    /// Called only when the environment named no host (see
    /// ``TerminalHost/hostProgram(environment:)``), which is why the cost is
    /// acceptable: locally there is nothing to ask, and the case that pays for
    /// the round trip is the one that is currently rendering incorrectly.
    ///
    /// Bytes that are not replies to the exchange — a keystroke typed during
    /// startup — are put into the input buffer rather than dropped. The window
    /// is one round trip, but "we ate your first keypress" is not a bug worth
    /// having.
    ///
    /// - Parameter timeout: how long to wait for the fence. Only reached by a
    ///   terminal that answers no DSR at all, since the read returns as soon as
    ///   the fence lands; a generous value therefore costs nothing in practice
    ///   and buys tolerance of a slow link.
    /// - Returns: what the terminal answered, and the host's name if those
    ///   answers name one — `nil` being both the common answer and the safe
    ///   one.
    func queryIdentity(timeout: Double = 0.5) -> (TerminalIdentity, String?) {
        // A pipe has no opinion about who it is, and raw mode is what stops the
        // replies being line-buffered and echoed back at the user.
        guard isatty(STDIN_FILENO) == 1, isRawMode else { return (TerminalIdentity(), nil) }

        // The fence as this exchange's own parser records it, so the read ends
        // on exactly the reply the parse below credits.
        let collected = fencedExchange(
            request: TerminalIdentityQuery.request, timeout: timeout,
            sawFence: { TerminalIdentityQuery.parse($0).sawFence })
        let identity = TerminalIdentityQuery.parse(collected)

        // Whatever was typed during the round trip belongs to the input parser.
        if !identity.unconsumed.isEmpty { enqueue(input: identity.unconsumed) }
        return (identity, TerminalHost.nameFromDeviceAttributes(identity))
    }
}

// MARK: - Private Helpers

extension Terminal {
    /// Appends a string's UTF-8 bytes to the frame buffer.
    fileprivate func appendToBuffer(_ string: String) {
        frameBuffer.append(contentsOf: string.utf8)
    }

    /// Writes all `count` bytes at `base` to `STDOUT_FILENO`, in as few syscalls
    /// as possible.
    ///
    /// Retries the unwritten tail on a partial write **and on `EINTR`** — a
    /// signal (SIGWINCH resize, SIGCONT, SIGTSTP) interrupting the blocking
    /// `write` returns `-1`/`EINTR` without having transferred the rest of the
    /// frame. The previous `if result <= 0 { break }` treated that the same as a
    /// hard error and abandoned the remainder, so a signal landing mid-flush
    /// dropped the frame tail (a corrupted/truncated frame) or left the terminal
    /// half-restored mid-teardown. `errno` is read immediately after the failed
    /// `write`, before any other call, since it is thread-local and transient.
    ///
    /// **And on `EAGAIN`, once there is room.** The terminal's file description
    /// is shared with the shell and whatever ran before, and a program that
    /// set it non-blocking and crashed (a Node CLI is the known case) leaves it
    /// so. TUIkit never sets it (a dispatch read source does not either,
    /// checked on macOS 15), but on such a descriptor a frame larger than the
    /// pty's buffer used to stop at the first `EAGAIN`: torn, and, for a frame
    /// that holds the display (``writeFrame(_:omitting:holdsDisplay:through:waitingForRoom:)``),
    /// with its end marker's retry failing the same way, so the terminal went
    /// on holding until the next multi-row frame. Now it waits for room as a
    /// blocking write would, for as long as one would.
    ///
    /// - Parameters:
    ///   - write: `write(2)` on standard output, unless a test hands in
    ///     another that fails on cue.
    ///   - waitForRoom: Waits until the descriptor can take more, after an
    ///     `EAGAIN`: ``waitForRoom(on:until:)`` on standard output, unless a
    ///     test hands in another. `false` gives up on the rest.
    /// - Returns: Whether every byte was written: `false` when a hard error,
    ///   or a write that took nothing, gave up on the rest.
    @discardableResult
    static func writeAll(
        _ base: UnsafePointer<UInt8>, _ count: Int,
        through write: (UnsafePointer<UInt8>, Int) -> Int = writeToStandardOutput,
        waitingForRoom waitForRoom: () -> Bool = { Terminal.waitForRoom() }
    ) -> Bool {
        var written = 0
        while written < count {
            let result = write(base + written, count - written)
            if result < 0 {
                let error = errno
                if error == EINTR { continue }  // interrupted by a signal — retry the rest
                // A non-blocking descriptor that is full — wait, then retry the rest.
                if error == EAGAIN || error == EWOULDBLOCK, waitForRoom() { continue }
                return false                     // real write error — give up on the remainder
            }
            if result == 0 { return false }      // wrote nothing — avoid an infinite spin
            written += result
        }
        return true
    }

    /// `write(2)` to standard output: what ``writeAll(_:_:through:waitingForRoom:)``
    /// writes through unless a test hands it another.
    nonisolated static func writeToStandardOutput(_ base: UnsafePointer<UInt8>, _ count: Int) -> Int {
        Foundation.write(STDOUT_FILENO, base, count)
    }

    /// Waits until `descriptor` can take more bytes, or `deadline` passes:
    /// what a blocking `write` does inside the kernel, for a descriptor left
    /// non-blocking (see ``writeAll(_:_:through:waitingForRoom:)``).
    ///
    /// An `EINTR` resumes the wait against the same deadline, as
    /// ``waitForInput(on:until:)``'s does, for its reasons.
    ///
    /// - Parameters:
    ///   - descriptor: Standard output, unless a test drives a pipe.
    ///   - deadline: When to give up; `nil`, the frame writer's, waits as long
    ///     as a blocking write would.
    /// - Returns: `true` once the descriptor reports room; `false` on the
    ///   deadline, on any error that is not `EINTR`, or when the descriptor
    ///   reports a hang-up or an error instead of room.
    nonisolated static func waitForRoom(on descriptor: Int32 = STDOUT_FILENO, until deadline: Date? = nil) -> Bool {
        while true {
            var timeout: Int32 = -1
            if let deadline {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { return false }
                timeout = Int32(remaining * 1000)
            }
            var target = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&target, 1, timeout)
            if ready > 0 { return target.revents & Int16(POLLOUT) != 0 }
            // `errno` is thread-local and transient, so it is read here, before
            // anything else can overwrite it.
            guard ready < 0, errno == EINTR else { return false }
        }
    }

    /// Writes a finished frame: all of it, or the parts either side of an
    /// `omitted` begin marker that it turned out not to need.
    ///
    /// A frame that holds the display carries its end marker as its last
    /// bytes, so a write that gives up partway would leave the terminal
    /// holding: Ghostty for a second, other hosts unmeasured. So then the end
    /// marker is tried again on its own. Only a hard error gives up now — a
    /// full non-blocking descriptor is waited on (``writeAll(_:_:through:waitingForRoom:)``)
    /// — and one will likely fail again, which costs nothing; a terminal
    /// still reading is let go at once.
    ///
    /// - Parameters:
    ///   - frame: The frame's bytes.
    ///   - omitted: An unused begin marker's bytes, or `nil`.
    ///   - holdsDisplay: Whether the frame began a synchronized update it
    ///     kept.
    ///   - write: `write(2)` on standard output, unless a test hands in
    ///     another.
    ///   - waitForRoom: How a full non-blocking descriptor is waited on:
    ///     ``waitForRoom(on:until:)`` on standard output, unless a test hands
    ///     in another.
    static func writeFrame(
        _ frame: UnsafeBufferPointer<UInt8>, omitting omitted: Range<Int>?, holdsDisplay: Bool,
        through write: (UnsafePointer<UInt8>, Int) -> Int = writeToStandardOutput,
        waitingForRoom waitForRoom: () -> Bool = { Terminal.waitForRoom() }
    ) {
        guard let base = frame.baseAddress else { return }
        let complete =
            if let omitted {
                writeAll(base, omitted.lowerBound, through: write, waitingForRoom: waitForRoom)
                    && writeAll(
                        base + omitted.upperBound, frame.count - omitted.upperBound,
                        through: write, waitingForRoom: waitForRoom)
            } else {
                writeAll(base, frame.count, through: write, waitingForRoom: waitForRoom)
            }
        guard !complete, holdsDisplay else { return }
        Self.synchronizedUpdateEndBytes.withUnsafeBufferPointer { end in
            guard let endBase = end.baseAddress else { return }
            writeAll(endBase, end.count, through: write, waitingForRoom: waitForRoom)
        }
    }

    /// ``synchronizedUpdateEnd``'s bytes, for the write that retries it.
    private static let synchronizedUpdateEndBytes = Array(synchronizedUpdateEnd.utf8)

    /// Writes all buffered bytes to `STDOUT_FILENO`, or to the scripted
    /// terminal a test installed: through ``writeFrame(_:omitting:holdsDisplay:through:waitingForRoom:)``,
    /// whose two parameters these are.
    fileprivate func flushBuffer(omitting omitted: Range<Int>? = nil, holdingDisplay: Bool = false) {
        guard !frameBuffer.isEmpty else { return }
        if let exchangeTransport {
            // One send per part, as one write per part. Never `nil`: a frame
            // is assembled from strings, and a marker is ASCII, so each part
            // is UTF-8.
            let parts = omitted.map { [0..<$0.lowerBound, $0.upperBound..<frameBuffer.count] }
                ?? [0..<frameBuffer.count]
            for part in parts where !part.isEmpty {
                exchangeTransport.send(String(bytes: frameBuffer[part], encoding: .utf8) ?? "")
            }
        } else {
            withWriteGate {
                frameBuffer.withUnsafeBufferPointer { buffer in
                    Self.writeFrame(buffer, omitting: omitted, holdsDisplay: holdingDisplay)
                }
            }
        }
        frameBuffer.removeAll(keepingCapacity: true)
    }

    /// Writes a string directly to `STDOUT_FILENO` without buffering, or to
    /// the scripted terminal a test installed (``exchangeTransport``).
    /// Internal rather than fileprivate so the extensions in other files —
    /// the startup exchanges, the kitty keyboard protocol's push and pop,
    /// ``pinGraphemeClusteringIfNeeded()`` — can reach it. Still nobody's
    /// business outside this type: it bypasses the output buffer.
    func writeImmediate(_ string: String) {
        if let exchangeTransport {
            if !string.isEmpty { exchangeTransport.send(string) }
            return
        }
        // Safe: UTF8 string is valid UInt8 sequence; rebinding preserves memory layout.
        string.utf8CString.withUnsafeBufferPointer { buffer in
            let count = buffer.count - 1
            guard count >= 1, let baseAddress = buffer.baseAddress else { return }
            baseAddress.withMemoryRebound(to: UInt8.self, capacity: count) { pointer in
                withWriteGate { _ = Self.writeAll(pointer, count) }
            }
        }
    }

    /// Runs `body`, a write to standard output, holding ``writeGate``, so the
    /// stall watchdog's pop never lands inside it. wasip1 has no watchdog.
    fileprivate func withWriteGate(_ body: () -> Void) {
        #if canImport(WASILibc)
            body()
        #else
            writeGate.withWriteLock(body)
        #endif
    }
}
