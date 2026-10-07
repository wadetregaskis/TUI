//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowInk.swift
//
//  How a `Table` row states the ink its cells are drawn in, and closes it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

/// Writes one line of a table row's ink: the selection mark in its colour, then
/// each cell in the cells' ink, each run of ink stated before it and closed after
/// it.
///
/// One type for the single-line and the multi-line row, which spelled the same
/// rule twice (`_TableCore.renderRowUncached` and `renderMultiLineRow`).
struct TableRowInk {
    /// The cells' ink introducer, or `nil` where the row states none: no colour at
    /// this depth, or a ramp that paints the cells itself.
    let introducer: String?

    /// What ends a run of the row's own ink: SGR 39 under a still fill (a stripe,
    /// a selected row's tint), which leaves the fill in force so its paint states
    /// it once; a reset under anything else. A still fill is painted over the
    /// finished line as a PERSISTENT background, stated again after every reset in
    /// the line (`ANSIRenderer.restating`); a reversal keeps the reset because SGR
    /// 39 under SGR 7 would change the colour a cell is filled with.
    let close: String

    /// Whether ``close`` is a reset, which ends a cell's own escapes too, so a
    /// cell need not be scanned for them.
    private let closeIsReset: Bool

    /// - Parameters:
    ///   - introducer: The cells' ink introducer, `nil` where there is none.
    ///   - close: What ends a run of the row's ink.
    init(introducer: String?, close: String) {
        self.introducer = introducer
        self.close = close
        closeIsReset = close == ANSIRenderer.reset
    }

    /// The ink of a row drawn under `background`: closed by SGR 39 under a still
    /// fill and a reset otherwise.
    init(introducer: String?, under background: RowBackground) {
        guard case .fixed = background else {
            self.init(introducer: introducer, close: ANSIRenderer.reset)
            return
        }
        self.init(introducer: introducer, close: ANSIRenderer.defaultForeground)
    }

    /// Writes the selection mark `glyph` in `colour`, closed by ``close`` —
    /// `ANSIRenderer.colorize(glyph, foreground: colour)`, byte for byte, when
    /// ``close`` is a reset.
    mutating func appendMark(_ glyph: String, in colour: Color, into content: inout String) {
        var style = TextStyle()
        style.foregroundColor = colour
        guard let sequence = ANSIRenderer.styleSequence(for: style) else {
            content += glyph
            return
        }
        content += sequence
        content += glyph
        content += close
    }

    /// States the cells' ink before a cell whose text is `text`.
    mutating func open(before text: String, into content: inout String) {
        guard let introducer else { return }
        content += introducer
    }

    /// Closes the cell just written, whose text is `text`: with ``close``, unless
    /// the text carries escapes of its own (a styled `Text`, a view's line), which a
    /// reset has to end — SGR 39 would leave a bold or an underline of the cell's
    /// running into the next one. Asks nothing of the text where ``close`` is a
    /// reset already: the answer is a reset whatever the text holds, and walking
    /// its bytes would be a scan per composed cell that cannot change it.
    mutating func close(after text: String, into content: inout String) {
        guard introducer != nil else { return }
        content += closeIsReset || !text.utf8.contains(0x1B) ? close : ANSIRenderer.reset
    }

    /// Ends the line. Every run of ink is closed where it ends, so nothing is left
    /// in force for what is drawn after the row — a scroll bar, a border.
    mutating func finish(into content: inout String) {}
}
