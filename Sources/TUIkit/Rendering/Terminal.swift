//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Terminal.swift
//
//  Created by LAYERED.work
//  License: MIT

import DequeModule
import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#elseif canImport(WASILibc)
    import WASILibc
#endif

/// Platform-specific type for `termios` flag fields.
///
/// Darwin uses `UInt` (64-bit), Linux uses `tcflag_t` (`UInt32`).
/// This typealias ensures flag bitmask operations compile on both.
#if os(Linux)
    private typealias TermFlag = UInt32
#else
    private typealias TermFlag = UInt
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
    /// ``UniqueDeque`` is a noncopyable ring buffer with O(1)
    /// removeFirst and an "append into uninitialised storage via
    /// `OutputSpan`" API — together those let us `read()` straight
    /// into the deque's backing buffer with zero intermediate
    /// copies, and consume bytes off the front without paying any
    /// shuffling cost. Capacity grows geometrically when needed
    /// and ``consume(_:)`` shrinks it back to ``baselineCapacity``
    /// once a transient large paste has been fully consumed.
    ///
    /// This and the parser state below it are module-internal rather than
    /// private, and NOT because anything outside wants them: the parser that
    /// owns them lives in `Terminal+Input.swift` (and the reply walk in
    /// `Terminal+Replies.swift`), split out because this file had reached its
    /// length limit, and an extension cannot hold stored properties. Nothing
    /// outside this module can see `Terminal` at all.
    var input: UniqueDeque<UInt8> = .init(
        minimumCapacity: Terminal.baselineCapacity)

    /// Initial — and steady-state minimum — capacity for ``input``.
    /// Sized to comfortably hold a frame's worth of bursty mouse
    /// events without ever needing to grow.
    static let baselineCapacity = 4096

    /// True while we're between the bracketed-paste start (`ESC[200~`)
    /// and end (`ESC[201~`) markers. Paste content is accumulated
    /// across as many `readEvent()` calls as it takes for the end
    /// marker to arrive — no blocking, no `usleep`. The run loop
    /// stays responsive even for very large pastes.
    var inPasteMode: Bool = false {
        didSet { pasteScanCursor = 0 }
    }

    /// How many leading bytes of ``input`` have already been checked and ruled
    /// out as the START of the bracketed-paste end marker.
    ///
    /// Meaningful only while ``inPasteMode``, which is why its `didSet` clears
    /// this: a cursor into a buffer that belongs to a finished paste is
    /// nonsense, and leaving a stale one behind would skip past the next
    /// paste's marker. Nothing is consumed from the front while a paste is
    /// open, so an index taken on one pass still means the same byte on the
    /// next.
    var pasteScanCursor: Int = 0

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
    var queuedInputs: Deque<TerminalInput> = []

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
    #endif

    /// Whether frame buffering is active.
    ///
    /// When `true`, ``write(_:)`` appends to ``frameBuffer`` instead of
    /// writing to `STDOUT_FILENO` immediately.
    private var isBuffering = false

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

    /// Creates a new terminal instance.
    ///
    /// - Parameter environment: Where `TUIKIT_SYNCHRONIZED_OUTPUT` is read
    ///   from: the process's own, unless a test poses another.
    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        frameBuffer.reserveCapacity(16_384)
        synchronizesOutput = Self.synchronizedOutputAllowed(environment: environment)
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
    /// - Signals like Ctrl+C are not automatically processed
    func enableRawMode() {
        guard !isRawMode else { return }

        // A scripted terminal (``exchangeTransport``) has no line discipline,
        // and the one on stdin then belongs to whatever runs the tests.
        #if !canImport(WASILibc)
            if exchangeTransport == nil {
                var raw = termios()
                tcgetattr(STDIN_FILENO, &raw)
                originalTermios = raw

                raw.c_lflag &= ~TermFlag(ECHO | ICANON | ISIG | IEXTEN)
                raw.c_iflag &= ~TermFlag(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
                raw.c_oflag &= ~TermFlag(OPOST)
                raw.c_cflag |= TermFlag(CS8)

                // Safe: termios.c_cc is a fixed-size array; rebinding to cc_t is valid.
                withUnsafeMutablePointer(to: &raw.c_cc) { pointer in
                    pointer.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { buffer in
                        buffer[Int(VMIN)] = 0
                        buffer[Int(VTIME)] = 0
                    }
                }

                tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
            }
        #endif
        isRawMode = true

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

        // Mouse tracking is now managed dynamically by
        // ``applyMouseSupport(_:)`` — see ``MouseSupport`` for the
        // selection of tracking modes. We always end up enabling SGR
        // extended position reporting (?1006h) when any mouse feature
        // is requested.
    }

    /// Disables raw mode and restores normal terminal operation.
    func disableRawMode() {
        guard isRawMode else { return }

        // A frame's hold on the display let go, should a failed write have
        // left one open; then what the shell is handed is shown at once.
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
            if var original = originalTermios {
                tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            }
        #endif
        isRawMode = false
        // Torn down in order: a signal from here on owes the terminal nothing.
        if exchangeTransport == nil { FatalSignalTerminalRestore.disarm() }
    }

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
    var outputModesOff: String {
        synchronizesOutput ? Self.synchronizedUpdateEnd : ""
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

    /// Owes the terminal ``signalDebt``, and the shell's termios, should the
    /// process die of a signal now; see ``FatalSignalTerminalRestore``. Called
    /// whenever the debt changes while raw mode is on: raw mode itself, a push
    /// or pop of the kitty flags, a pin.
    ///
    /// A scripted terminal is a test's, and the process's signal handlers are
    /// not its to install.
    func armSignalRestore() {
        #if !canImport(WASILibc)
            guard isRawMode, exchangeTransport == nil else { return }
            FatalSignalTerminalRestore.arm(owing: signalDebt, restoring: originalTermios)
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
    }

    /// Exits the alternate screen buffer.
    func exitAlternateScreen() {
        write(ANSIRenderer.exitAlternateScreen)
    }

    /// Removes `n` bytes from the front of the buffer and, if the
    /// resulting size fits back inside ``baselineCapacity``, shrinks
    /// the backing allocation down too. The shrink is the reason
    /// for the explicit `reallocate(capacity:)` call: ``UniqueDeque``
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

    /// Drains whatever stdin has waiting straight into the deque's
    /// uninitialised tail storage, with zero intermediate copies.
    ///
    /// Implementation:
    /// - ``UniqueDeque/append(addingCount:initializingWith:)`` hands
    ///   us an `OutputSpan<UInt8>` covering contiguous free space
    ///   at the back of the ring buffer.
    /// - `withUnsafeMutableBufferPointer` exposes that span as a
    ///   raw `UnsafeMutableBufferPointer`, which we pass straight to
    ///   `read(STDIN_FILENO, …)`.
    /// - We set the span's `written` count to whatever `read()`
    ///   returned; the deque keeps exactly those bytes initialised.
    ///
    /// In the (rare) case that the ring buffer's contiguous tail is
    /// smaller than our requested chunk, the deque calls our closure
    /// a second time for the wrapped portion — `read()` is called
    /// again for that span, which costs at most one extra syscall.
    ///
    /// - Returns: the number of new bytes drained from stdin.
    @discardableResult
    func appendDrain() -> Int {
        var added = 0
        // Request up to one baseline chunk at a time. The deque
        // grows behind the scenes if we don't already have that much
        // free; subsequent drains can reuse the expanded capacity.
        input.append(addingCount: Self.baselineCapacity) { (span: inout OutputSpan<UInt8>) in
            span.withUnsafeMutableBufferPointer { buffer, written in
                let n = readSource(buffer)
                if n > 0 {
                    written = n
                    added += n
                } else {
                    written = 0
                }
            }
        }
        return added
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
    /// - Parameter write: `write(2)` on standard output, unless a test hands
    ///   in another that fails on cue.
    /// - Returns: Whether every byte was written: `false` when a hard error,
    ///   or a write that took nothing, gave up on the rest.
    @discardableResult
    static func writeAll(
        _ base: UnsafePointer<UInt8>, _ count: Int,
        through write: (UnsafePointer<UInt8>, Int) -> Int = writeToStandardOutput
    ) -> Bool {
        var written = 0
        while written < count {
            let result = write(base + written, count - written)
            if result < 0 {
                if errno == EINTR { continue }  // interrupted by a signal — retry the rest
                return false                     // real write error — give up on the remainder
            }
            if result == 0 { return false }      // wrote nothing — avoid an infinite spin
            written += result
        }
        return true
    }

    /// `write(2)` to standard output: what ``writeAll(_:_:through:)`` writes
    /// through unless a test hands it another.
    nonisolated static func writeToStandardOutput(_ base: UnsafePointer<UInt8>, _ count: Int) -> Int {
        Foundation.write(STDOUT_FILENO, base, count)
    }

    /// Writes a finished frame: all of it, or the parts either side of an
    /// `omitted` begin marker that it turned out not to need.
    ///
    /// A frame that holds the display carries its end marker as its last
    /// bytes, so a write that gives up partway would leave the terminal
    /// holding: Ghostty for a second, other hosts unmeasured. So then the end
    /// marker is tried again on its own. A write that failed hard will likely
    /// fail again, and that costs nothing; a terminal still reading is let go
    /// at once.
    ///
    /// - Parameters:
    ///   - frame: The frame's bytes.
    ///   - omitted: An unused begin marker's bytes, or `nil`.
    ///   - holdsDisplay: Whether the frame began a synchronized update it
    ///     kept.
    ///   - write: `write(2)` on standard output, unless a test hands in
    ///     another.
    static func writeFrame(
        _ frame: UnsafeBufferPointer<UInt8>, omitting omitted: Range<Int>?, holdsDisplay: Bool,
        through write: (UnsafePointer<UInt8>, Int) -> Int = writeToStandardOutput
    ) {
        guard let base = frame.baseAddress else { return }
        let complete =
            if let omitted {
                writeAll(base, omitted.lowerBound, through: write)
                    && writeAll(base + omitted.upperBound, frame.count - omitted.upperBound, through: write)
            } else {
                writeAll(base, frame.count, through: write)
            }
        guard !complete, holdsDisplay else { return }
        Self.synchronizedUpdateEndBytes.withUnsafeBufferPointer { end in
            guard let endBase = end.baseAddress else { return }
            writeAll(endBase, end.count, through: write)
        }
    }

    /// ``synchronizedUpdateEnd``'s bytes, for the write that retries it.
    private static let synchronizedUpdateEndBytes = Array(synchronizedUpdateEnd.utf8)

    /// Writes all buffered bytes to `STDOUT_FILENO`, or to the scripted
    /// terminal a test installed: through ``writeFrame(_:omitting:holdsDisplay:through:)``,
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
            frameBuffer.withUnsafeBufferPointer { buffer in
                Self.writeFrame(buffer, omitting: omitted, holdsDisplay: holdingDisplay)
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
                _ = Self.writeAll(pointer, count)
            }
        }
    }
}
