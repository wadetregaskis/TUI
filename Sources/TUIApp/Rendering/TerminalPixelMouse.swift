//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalPixelMouse.swift
//
//  SGR-Pixels (`?1016`): asking for it, and working out whole cells from what
//  it reports.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUITerminalHost

/// The terminal's mouse reports in pixels rather than cells, asked for while
/// something on screen wants the pointer's location within a cell
/// (``MouseSupport/subCellLocations``) and given back when nothing does.
///
/// It is not on all the time because it is not free. A pixel report no longer
/// says which cell was clicked: the whole cell, and so every hit test, is worked
/// out from a cell size. And a pointer moved across one cell sends a report for
/// every step of the mouse rather than one (`pixel_mouse_probe.py`: 64 reports
/// against 12). An app with no such view pays for neither.
///
/// ## Asked, never assumed
///
/// DECRQM says whether the terminal has the mode, as asked of a host known to
/// answer it (``Host/of(program:environment:)``), since Apple Terminal prints
/// the question. Nothing is held up for the answer: replies arrive in the input
/// stream and this moves on when they do, so a terminal that never answers
/// simply goes on reporting cells.
///
/// **The reply to the mode's own query is also the fence.** A report in the pipe
/// when `?1016h` is written is in cells, the one after it in pixels, and nothing
/// in either says which. The query is written straight after the change, so its
/// reply lands in the stream exactly between the two, and the reports before it
/// are read one way and those after it the other. That is what makes it safe to
/// turn on and off mid-session.
///
/// ## A wrong cell size must not misplace a click
///
/// - The cell size is the host's measured answer, or for a host nobody has
///   measured, one two independent answers agree on (``CellSource``).
///   `TIOCGWINSZ` is never it: Ghostty 1.4's includes its padding, and iTerm2's is
///   in device pixels where its reports are in points.
/// - A press can only land inside the window, so a press reported beyond the grid
///   proves the size wrong: it is dropped, and the mode given back for the rest of
///   the session (``convert(_:)``).
///
/// Everything else in the framework hit-tests the whole cell this leaves in
/// ``MouseEvent/x`` and ``MouseEvent/y``; only what reports a location to the app
/// reads the fraction. See "SGR-Pixels mouse" in
/// `Documentation/Terminals/Terminal compatibility survey.md`.
struct PixelMouseNegotiation {
    /// What is known of a host's pixel reports.
    struct Host: Equatable {
        /// Whether a report counts pixels from 0, where xterm's does from 1.
        var countsFromZero = false

        /// Where the cell size comes from.
        var cellSource: CellSource

        /// iTerm2 answers DECRQM `?1016` "permanently reset" whatever it is doing
        /// (3.7.6, measured), and does report pixels. Its `?1006` is the same
        /// setting and does move, so that is the mode to ask whether it took.
        var answersThroughSGRMode = false

        /// The mode whose reply says which reports are coming.
        var fenceMode: Int { answersThroughSGRMode ? 1006 : 1016 }

        /// What ``fenceMode`` answers while pixels are on.
        var stateWithPixelsOn: TerminalModeQuery.State { answersThroughSGRMode ? .reset : .set }

        /// The host a program is, or `nil` where it must not be asked: Apple
        /// Terminal prints DECRQM, Warp ignores it and has no `?1016` (measured),
        /// tmux would answer for itself, and a terminal nothing names may be one
        /// that prints it too.
        static func of(program: TerminalClient.Program, environment: [String: String]) -> Self? {
            guard environment["TUI_PIXEL_MOUSE"] != "0" else { return nil }
            switch program {
            case .ghostty:
                return Self(countsFromZero: true, cellSource: .cellReply)
            case .iTerm2:
                return Self(cellSource: .cellReply, answersThroughSGRMode: true)
            case .xtermJS:
                return Self(countsFromZero: true, cellSource: .areaOverGrid)
            case .unidentified:
                let named =
                    TerminalClient.namesClipboardWritingTerminal(environment) || environment["XTERM_VERSION"] != nil
                return named ? Self(cellSource: .agreement) : nil
            case .appleTerminal, .warp, .gnomeTerminal, .tmux:
                return nil
            }
        }
    }

    /// Where a host's cell size comes from.
    enum CellSource: Equatable {
        /// `CSI 16 t`, alone: measured against real clicks (Ghostty, iTerm2). Its
        /// `CSI 14 t` may be something else: iTerm2's is the window's.
        case cellReply

        /// `CSI 14 t` over the grid, whose cell is fractional and whose `16 t`
        /// rounds it: read from xterm.js's source, and checked against the
        /// rounded answer.
        case areaOverGrid

        /// `CSI 16 t`, if the grid's worth of it is `CSI 14 t` to within a cell.
        /// For a host nobody here has measured: two answers in one unit.
        case agreement
    }

    enum Phase: Equatable {
        /// Nothing asked yet.
        case idle
        /// Asked whether it has the mode and how big a cell is.
        case asked
        /// It cannot be had, for the rest of the session.
        case unavailable
        /// It can be had, and is off.
        case off
        /// Set; reports are still read as cells until the fence's reply.
        case turningOn
        /// Reports are in pixels.
        case on
        /// Reset; reports are still read as pixels until the fence's reply.
        case turningOff
    }

    /// A cell's size in the unit of a report.
    struct CellSize: Equatable {
        var width: Double
        var height: Double
    }

    /// How far beyond the grid a press may land and still be believed, in cells:
    /// a window's margins report past the last whole cell (iTerm2 0.2 of a row
    /// under it, Ghostty 0.5, measured).
    static let offGridTolerance = 2

    private(set) var host: Host?
    private(set) var phase = Phase.idle
    private var wanted = false
    private var cellReply: (width: Int, height: Int)?
    private var areaReply: (width: Int, height: Int)?
    private var grid = (width: 0, height: 0)
    private var cellReading: TerminalCellPixels?

    /// Whether replies may be on their way, for the input loop to ask of a CSI.
    var isListening: Bool { phase != .idle && phase != .unavailable }

    /// Whether the reports arriving now are in pixels.
    var readsPixels: Bool { phase == .on || phase == .turningOff }

    /// Whether the terminal has been told pixels, so that a `?1006h` re-sent with
    /// a tracking change must be followed by `?1016h`: the two are one setting and
    /// the last one wins (measured on Ghostty and iTerm2).
    var holdsPixels: Bool { phase == .turningOn || phase == .on }

    /// The cell's size in the unit of a report, or `nil` if it cannot be trusted.
    var cellSize: CellSize? {
        guard let host, let cellReply, cellReply.width > 0, cellReply.height > 0 else { return nil }
        let cell = CellSize(width: Double(cellReply.width), height: Double(cellReply.height))
        switch host.cellSource {
        case .cellReply:
            return cell
        case .areaOverGrid:
            guard let areaReply, grid.width > 0, grid.height > 0 else { return nil }
            let width = Double(areaReply.width) / Double(grid.width)
            let height = Double(areaReply.height) / Double(grid.height)
            guard Int(width.rounded()) == cellReply.width, Int(height.rounded()) == cellReply.height else { return nil }
            return CellSize(width: width, height: height)
        case .agreement:
            guard let areaReply,
                abs(areaReply.width - cellReply.width * grid.width) < cellReply.width,
                abs(areaReply.height - cellReply.height * grid.height) < cellReply.height
            else { return nil }
            return cell
        }
    }

    // MARK: - Driving it

    /// One frame's view of what is wanted.
    ///
    /// - Parameters:
    ///   - wanted: Whether anything on screen wants locations within a cell.
    ///   - tracking: Whether the terminal is reporting the mouse at all.
    ///   - grid: The terminal's size in cells.
    ///   - cellReading: The cell as `TIOCGWINSZ` has it: not believed as a size,
    ///     but a change in it is a font change, as a change in the grid may be.
    ///   - host: The host, worked out the first time something wants it.
    /// - Returns: What to write to the terminal.
    mutating func update(
        wanted: Bool, tracking: Bool = true, grid: (width: Int, height: Int), cellReading: TerminalCellPixels?,
        host findHost: @autoclosure () -> Host?
    ) -> String {
        self.wanted = wanted
        // Tracking is off, a suspend usually, so no report is coming to be fenced
        // from. And no question goes with it: the shell may be reading by the time
        // the answer comes.
        if !tracking, holdsPixels {
            phase = .off
            return "\u{1B}[?1016l"
        }
        let moved = grid != self.grid || cellReading != self.cellReading
        self.grid = grid
        self.cellReading = cellReading
        switch phase {
        case .idle:
            guard wanted else { return "" }
            host = findHost()
            guard host != nil else {
                phase = .unavailable
                return ""
            }
            phase = .asked
            return Self.geometryQuestions + Self.modeQuestion(1016)
        case .off:
            guard wanted else { return "" }
            return (moved ? Self.geometryQuestions : "") + turnOn()
        case .on:
            guard wanted else { return turnOff() }
            return moved ? Self.geometryQuestions : ""
        case .asked, .turningOn, .turningOff, .unavailable:
            return ""
        }
    }

    /// One complete sequence from the input stream, while ``isListening``.
    ///
    /// - Returns: What to write to the terminal, or `nil` if this was no reply of
    ///   concern here, for the input loop to carry on with.
    mutating func hear(_ sequence: [UInt8]) -> String? {
        guard sequence.count > 3, sequence[0] == 0x1B, sequence[1] == 0x5B else { return nil }
        if sequence[sequence.count - 1] == 0x74 /* t */ {
            return hearGeometry(sequence) ? "" : nil
        }
        guard TerminalModeQuery.isReply(sequence[...]) else { return nil }
        if let state = TerminalModeQuery.parse(sequence, mode: 1016) { return hear(mode: 1016, state: state) }
        if let state = TerminalModeQuery.parse(sequence, mode: 1006) { return hear(mode: 1006, state: state) }
        return nil
    }

    private mutating func hearGeometry(_ sequence: [UInt8]) -> Bool {
        let fields = sequence[2..<(sequence.count - 1)].split(separator: 0x3B, omittingEmptySubsequences: false)
        guard fields.count == 3, let kind = ASCIIDecimal.value(of: fields[0]),
            let height = ASCIIDecimal.value(of: fields[1]), let width = ASCIIDecimal.value(of: fields[2])
        else { return false }
        switch kind {
        case 6: cellReply = (width, height)
        case 4: areaReply = (width, height)
        default: return false
        }
        return true
    }

    private mutating func hear(mode: Int, state: TerminalModeQuery.State) -> String {
        guard let host else { return "" }
        switch phase {
        case .asked where mode == 1016:
            guard state.isSupported || host.answersThroughSGRMode, cellSize != nil else {
                phase = .unavailable
                return ""
            }
            phase = .off
            return wanted ? turnOn() : ""
        case .turningOn where mode == host.fenceMode:
            // Told to and it didn't: an iTerm2 too old to have it, say.
            phase = state == host.stateWithPixelsOn ? .on : .unavailable
            return ""
        case .turningOff where mode == host.fenceMode:
            guard state != host.stateWithPixelsOn else { return "" }
            phase = distrusted ? .unavailable : .off
            return ""
        default:
            return ""
        }
    }

    private var distrusted = false

    private mutating func turnOn() -> String {
        guard let host else { return "" }
        phase = .turningOn
        return "\u{1B}[?1016h" + Self.modeQuestion(host.fenceMode)
    }

    /// Back to cell reports. `?1016l` alone leaves the legacy encoding behind,
    /// whatever `?1006` was before (measured on Ghostty and iTerm2), hence `?1006h`.
    private mutating func turnOff() -> String {
        guard let host else { return "" }
        phase = .turningOff
        return "\u{1B}[?1016l\u{1B}[?1006h" + Self.modeQuestion(host.fenceMode)
    }

    /// The terminal's modes were reset (a suspend) and it is in cells again.
    /// Nothing is owed: a mode reply arriving now finds ``Phase/off``.
    mutating func noteModesReset() {
        switch phase {
        case .turningOn, .on, .turningOff: phase = .off
        case .asked: phase = .idle
        case .idle, .off, .unavailable: break
        }
    }

    // MARK: - Converting

    /// Works out the whole cell, and how far across it, from a report that
    /// ``MouseEvent/parseSGR(_:)`` read as if it were in cells: its `x` and `y`
    /// are the report's numbers, less one, held at zero.
    ///
    /// A report beyond the grid is held to the grid's last cell, where a terminal
    /// that reports cells holds it, a drag past the window being a real thing.
    /// A press is not, and says the cell size is wrong.
    ///
    /// - Returns: The event, or `nil` for a press that proved the size wrong; and
    ///   what to write to the terminal.
    mutating func convert(_ event: MouseEvent) -> (event: MouseEvent?, write: String) {
        guard let host, let cell = cellSize, grid.width > 0, grid.height > 0 else { return (event, "") }
        let shift = host.countsFromZero ? 1 : 0
        let across = Double(event.x + shift) / cell.width
        let down = Double(event.y + shift) / cell.height
        if event.phase == .pressed,
            Int(across) >= grid.width + Self.offGridTolerance || Int(down) >= grid.height + Self.offGridTolerance
        {
            guard phase == .on else { return (nil, "") }
            distrusted = true
            return (nil, turnOff())
        }
        let (column, fractionX) = Self.place(across, within: grid.width)
        let (row, fractionY) = Self.place(down, within: grid.height)
        return (event.movedTo(x: column, y: row, subcellX: fractionX, subcellY: fractionY), "")
    }

    /// A position in cells as a whole cell and a fraction, held to `count` cells.
    private static func place(_ position: Double, within count: Int) -> (cell: Int, fraction: Double) {
        let whole = Int(position)
        guard whole < count else { return (count - 1, 0.999) }
        return (whole, position - Double(whole))
    }

    // MARK: - Questions

    /// The cell's size and the text area's: asked before any mode question so that
    /// their replies are in by the time its reply says what to do with them.
    static let geometryQuestions = "\u{1B}[16t\u{1B}[14t"

    /// DECRQM, unfenced: the reply is handled when it comes, and silence is only
    /// more cell reports.
    static func modeQuestion(_ mode: Int) -> String { "\u{1B}[?\(mode)$p" }
}
