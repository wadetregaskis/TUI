//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalAmbiguousWidthQuery.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Asking whether ambiguous characters are drawn wide

/// The startup probe that learns whether the terminal draws East Asian
/// Ambiguous characters two cells wide, and the parser for its answer.
///
/// ## Why it is asked
///
/// Box drawing, arrows, `●`, Greek, Cyrillic and much of accented Latin-1
/// are East Asian Ambiguous: their width is a terminal SETTING, not a property
/// of the character. Every measured host draws them one cell with its default
/// settings, and TUI claims one (`Documentation/Terminals/Terminal
/// compatibility survey.md`, "Key symbols"). Where a host is set to draw them
/// wide, a row written whole is shifted but coherent; a span written by the
/// cell diff (``ANSICellDiff/spans(_:)``) goes to the column TUI counted,
/// which is left of where the row was drawn, and leaves the old glyphs beside
/// the new ones until the row is next written whole. With a wide answer the
/// frame writer writes whole rows only, for the session
/// (`FrameDiffWriter.writesSpans`).
///
/// Ideally the widths themselves would follow the host, so that a border
/// claimed two cells where it advances two; that is out of scope here, and
/// the layout stays as wrong there as it was. The probe stops the spans making
/// it worse frame by frame.
///
/// ## Why every host
///
/// The setting is not iTerm2's alone. iTerm2 ("Ambiguous characters are
/// double-width"), Apple Terminal ("Unicode East Asian Ambiguous characters
/// are wide") and GNOME Terminal ("Ambiguous-width characters: Wide") are
/// hosts TUI supports and each has one, and so do WezTerm, xterm
/// (`cjkWidth`) and mintty. tmux has none, but answers the cursor report from
/// its own grid, which is the grid TUI's columns address. Asking only the
/// hosts known to have the setting would also miss every host reached over
/// ssh before it is named. Asking costs nothing a person can see or wait for:
/// it rides the startup colour exchange (``Terminal/askColors(isTmux:timeout:askingKeyboardFlags:probingAmbiguousWidth:)``),
/// which every host is asked and every measured host answers, so it adds
/// ``request``'s bytes and no round trip.
///
/// ## Shape
///
/// Saves the cursor, moves to row 2, column 1 of the alternate screen (blank,
/// and repainted whole by the first frame), writes two Ambiguous characters
/// concealed (SGR 8), asks for a cursor report, erases what it wrote and
/// restores the cursor: all in the one write, before the first frame, with the
/// cursor hidden. The report says how far the two advanced: column 3 for one
/// cell each, 4 or 5 where either is drawn wide.
///
/// Row 2, because a cursor report for row 1, `CSI 1;m R`, is the shape of a
/// modified F3 (`KeyEvent.parse`), so it could not be told from a key typed
/// during the exchange, and one arriving after the exchange gave up would be
/// typed. The exchange is asked only of a terminal at least two rows high,
/// so no report of this probe is for row 1. The report is read with
/// ``TerminalGraphicsQuery/cursorReports(in:)``, which counts no row-1 report
/// for the same reason.
///
/// Which hosts answer a cursor report truthfully: every measured one
/// answered it (it fenced the startup exchanges until 2026-10-05). The one
/// recorded disagreement between a cursor report and the paint, Apple
/// Terminal's internal column, is for composed emoji clusters, not for a
/// single Ambiguous scalar, which it advanced one in agreement with its paint.
/// A host that answers none leaves the writer as it was.
enum TerminalAmbiguousWidthQuery {

    /// The row the probe writes on, 1-based: the second, so its report is not
    /// a key's shape.
    static let row = 2

    /// The characters written: a box-drawing line (`─`, U+2500), the border
    /// class, and a black circle (`●`, U+25CF), a radio button's bullet. Both
    /// East Asian Ambiguous.
    static let probe = "\u{2500}\u{25CF}"

    /// Where the cursor ends when both advance one cell: column 3.
    private static let narrowColumn = 1 + 2

    /// The bytes the probe adds to the startup colour exchange, ahead of its
    /// queries: DECSC, CUP to row 2, the probe concealed, a cursor-report
    /// request, CUP back, an erase to the end of the line, DECRC.
    ///
    /// DECSC and DECRC (`ESC 7`, `ESC 8`) rather than `CSI s`/`CSI u`, as the
    /// graphics handshake saves the cursor (``TerminalGraphicsQuery/request``):
    /// one meaning on every VT100 descendant, and the conceal is put back with
    /// the rest of the pen.
    static let request =
        "\u{1B}7\u{1B}[\(row);1H\u{1B}[8m" + probe + "\u{1B}[6n\u{1B}[\(row);1H\u{1B}[K\u{1B}8"

    /// What the reply in `bytes` says: `true` where either character was drawn
    /// wide, `false` where both were drawn one cell, and `nil` where no report
    /// for the probe's row came back, or one that fits neither (a terminal
    /// too narrow for the probe pins the cursor at its last column).
    ///
    /// The last such report, not the first: the only other cursor report a
    /// startup exchange asks for is the graphics handshake's, which runs
    /// before this one, and one of those arriving late would arrive first.
    static func drawsWide(in bytes: [UInt8]) -> Bool? {
        guard let report = TerminalGraphicsQuery.cursorReports(in: bytes).last(where: { $0[0] == row })
        else { return nil }
        switch report[1] {
        case narrowColumn: return false
        case (narrowColumn + 1)...(narrowColumn + 2): return true
        default: return nil
        }
    }

    /// Whether one complete escape sequence is this probe's reply: a cursor
    /// report off row 1, which no key sends.
    static func isReply(_ sequence: ArraySlice<UInt8>) -> Bool {
        TerminalGraphicsQuery.cursorReports(in: Array(sequence)).count == 1
    }
}
