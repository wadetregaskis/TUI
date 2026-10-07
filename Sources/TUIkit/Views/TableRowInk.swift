//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowInk.swift
//
//  How a `Table` row states the ink its cells are drawn in: once for every run
//  of cells whose text carries no escapes of its own, not once per cell.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

/// Writes one line of a table row's ink: the selection mark in its colour, then
/// each cell in the cells' ink, stated ONCE for every run of cells whose text
/// carries no escapes of its own and closed once at the run's end (decisions
/// A-SPF-1).
///
/// A row opened every cell with the ink and closed it again — a reset, or SGR 39
/// under a still fill — so an eight-column row spent about 207 bytes of escapes
/// at truecolor on what one introducer and one close say, striped or not, and
/// every one of those bytes was carried up through every container, copied and
/// scanned for width on every frame the table was drawn. The ink may run on
/// across the spacing between two cells because a blank cell shows no ink: what
/// it draws is its FIELD. What this is NOT is a change to what any cell draws:
/// every glyph is in the ink it was in, every field is the field it was, and only
/// the SGR state of the blank cells between them differs — which a blank shows
/// only under an underline, a strike or reverse video, and which the opacity
/// resolution reads as the terminal does, a blank cell's ink being its field
/// (`OpacityBlend.displayedInk(of:defaultForeground:)`), so a translucent ink's
/// claim over the spacing resolves as it did. `TableRowInkTests` compares the two
/// spellings cell by cell through the grid a terminal paints.
///
/// The row's OWN reversal keeps its closes (below). An ANCESTOR's it cannot see:
/// a table nested in a `List` row, or in a view cell of another table's row,
/// that reverses where its palette's highlight cannot be measured shows the
/// spacing between its cells in their ink and its blank marks in the reversal's,
/// where it showed the reversal's and the mark's — its glyphs unchanged
/// (decisions-SPF2 B-SPF2-2).
///
/// It keeps a close per run where the shared ink could show:
/// - after a cell whose text carries escapes of its own (a styled `Text`, a view
///   cell's line) a reset ends the cell's bold or underline before the next one,
///   and the ink is stated again for the cell after it;
/// - under a REVERSAL (``RowBackground/reversed(ink:field:)``, a reversing
///   breath) after every run, the mark's included, as before: under SGR 7 a
///   cell's ink is the colour it is FILLED with, so a blank cell's ink shows, and
///   the spacing must stay in the reversal's own restated pair;
/// - and in a row whose ramp varies along it, which paints cell by cell
///   (`PaintRenderer.band`) and asks this type for nothing but its mark.
struct TableRowInk {
    /// Whose ink is in force at the end of what has been written.
    private enum InForce {
        case nothing, mark, cells
    }

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

    /// Whether a run of plain cells shares one introducer: everywhere but under a
    /// reversal and along a banded row (see the type's comment).
    let shares: Bool

    /// Whether ``close`` is a reset, which ends a cell's own escapes too: where runs
    /// do not share, a cell need not be scanned for them.
    private let closeIsReset: Bool

    private var inForce = InForce.nothing

    /// - Parameters:
    ///   - introducer: The cells' ink introducer, `nil` where there is none.
    ///   - close: What ends a run of the row's ink.
    ///   - shares: Whether runs of plain cells share one introducer.
    init(introducer: String?, close: String, shares: Bool) {
        self.introducer = introducer
        self.close = close
        self.shares = shares
        closeIsReset = close == ANSIRenderer.reset
    }

    /// The ink of a row drawn under `background`: closed by SGR 39 under a still
    /// fill and a reset otherwise, shared everywhere but under a reversal, along
    /// a row whose ramp bands it, and in a table drawn inside a `List` row
    /// (`insideListRow`): a list's cursor row may reverse its content where the
    /// palette's highlight cannot be measured, and a reversal fills the blanks
    /// between cells with whatever ink is in force (decisions B-SPF2-2).
    init(introducer: String?, under background: RowBackground, bandsAcrossRow: Bool, insideListRow: Bool = false) {
        let reverses: Bool
        let close: String
        switch background {
        case .fixed:
            (reverses, close) = (false, ANSIRenderer.defaultForeground)
        case .reversed, .pulsingReversal:
            (reverses, close) = (true, ANSIRenderer.reset)
        case .none, .pulsing:
            (reverses, close) = (false, ANSIRenderer.reset)
        }
        self.init(introducer: introducer, close: close, shares: !reverses && !bandsAcrossRow && !insideListRow)
    }

    /// Writes the selection mark `glyph` in `colour`.
    ///
    /// A blank mark — every unselected row's, in a table with a selection — states
    /// no colour where runs share: a blank shows none. Where they do not (a
    /// reversal, a banded row) it is spelled and closed as it always was:
    /// `ANSIRenderer.colorize(glyph, foreground: colour)`, byte for byte, when
    /// ``close`` is a reset.
    mutating func appendMark(_ glyph: String, in colour: Color, into content: inout String) {
        if shares, glyph == " " {
            content += glyph
            return
        }
        var style = TextStyle()
        style.foregroundColor = colour
        guard let sequence = ANSIRenderer.styleSequence(for: style) else {
            content += glyph
            return
        }
        content += sequence
        content += glyph
        if shares {
            inForce = .mark
        } else {
            content += close
        }
    }

    /// States the cells' ink before a cell whose text is `text`, unless it is in
    /// force already. Where runs share, an empty cell — a wrapped row's line past a
    /// shorter cell's last — states none: its spaces show none.
    mutating func open(before text: String, into content: inout String) {
        guard let introducer, inForce != .cells, !shares || !text.isEmpty else { return }
        content += introducer
        inForce = .cells
    }

    /// Closes the cell just written, whose text is `text`, where it has to be
    /// closed: after every cell where runs do not share, and after a cell whose
    /// text carries escapes of its own wherever they do — with a reset, which a
    /// bold or an underline of the cell's needs, SGR 39 would leave it running into
    /// the next cell.
    ///
    /// Where runs share, every cell's text is scanned for an escape, whatever
    /// ``close`` is: only a cell with escapes of its own ends the run, so the scan
    /// is what tells the two apart — one pass over each cell's bytes, on every
    /// composed row that shares. Where they do not, the text is scanned only when
    /// ``close`` is not a reset already, as it always was.
    mutating func close(after text: String, into content: inout String) {
        guard introducer != nil, inForce == .cells else { return }
        if shares {
            guard text.utf8.contains(0x1B) else { return }
            content += ANSIRenderer.reset
        } else {
            content += closeIsReset || !text.utf8.contains(0x1B) ? close : ANSIRenderer.reset
        }
        inForce = .nothing
    }

    /// Ends the line: closes whatever ink is still in force, so nothing drawn after
    /// the row — a scroll bar, a border — draws in it.
    mutating func finish(into content: inout String) {
        guard inForce != .nothing else { return }
        content += close
        inForce = .nothing
    }
}
