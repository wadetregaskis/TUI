//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+OverlayRowPieces.swift
//
//  A composited row in the pieces it is made of: what of the base goes before
//  the overlay's line, and what after. `Opacity as composition.md` §117.
//
//  Created by Wade Tregaskis
//  License: MIT

/// One row of a composite of a painted overlay, in the pieces it is made of: the
/// base's cells before the overlay's column, the overlay's line, and the base's
/// cells after it, each with the escapes that put the row's styling right at the
/// seam.
///
/// The pieces either side are the base's alone. They read the base's line, the
/// overlay's column and how wide its line is, and nothing of the line itself: a
/// painted overlay states every field it needs, so it is inserted as it is
/// (``FrameBuffer/composited(with:at:overlayIsPainted:terminalForeground:)``). That
/// is what lets a caller keep them while the overlay's line changes and the base's
/// does not, as a scrolling list in a sheet does over the page veiled below it.
package struct OverlayRowPieces: Sendable, Equatable {
    /// The row up to the overlay's line; the whole row, padded to its width, where
    /// no line of the overlay is on it.
    package var head: String
    /// The row after the overlay's line; `nil` where no line of the overlay is on it.
    package var tail: String?

    /// The row, with `overlayLine` between the pieces: the line the overlay draws on
    /// it, as wide as the pieces were cut for. Ignored where the overlay is not on
    /// the row.
    package func joined(around overlayLine: String) -> String {
        guard let tail else { return head }
        var row = ""
        row.reserveCapacity(head.utf8.count + overlayLine.utf8.count + tail.utf8.count)
        row += head
        row += overlayLine
        row += tail
        return row
    }
}

extension FrameBuffer {
    /// The pieces of a row of a painted overlay's composite, from the base's line
    /// on it already padded to the composite's width: the line itself where the
    /// overlay has no line on the row (`overlayWidth` `nil`), else the base cut
    /// round an `overlayWidth`-wide line at `column`, which must not be negative.
    static func paintedOverlayPieces(
        base: String, atColumn column: Int, overlayWidth: Int?, terminalForeground: () -> SGRState.Colour?
    ) -> OverlayRowPieces {
        guard let overlayWidth else { return OverlayRowPieces(head: base, tail: nil) }
        let split = base.ansiOverlaySplit(
            prefixColumns: column, suffixDropColumns: column + overlayWidth, terminalForeground: terminalForeground)
        let seams = seams(of: split, atColumn: column)
        return OverlayRowPieces(head: seams.head, tail: seams.tail)
    }

    /// What of a split base goes either side of the overlay inserted at `column`:
    /// the prefix and the reset ahead of the overlay, and the reset after it, the
    /// styling restored for the suffix and the suffix.
    ///
    /// - Parameter minimumTotalWidth: The column the row must reach at least, past
    ///   everything the base had: see ``insertOverlay(split:overlay:atColumn:minimumTotalWidth:overlayIsPainted:)``.
    static func seams(
        of split: ANSIOverlaySplit, atColumn column: Int, minimumTotalWidth: Int = 0
    ) -> (head: String, tail: String) {
        let afterOverlayColumn = split.suffixDropColumns

        // Either split point can land in the MIDDLE of a wide character
        // (emoji, CJK): the split drops the straddling character whole, so
        // the prefix comes back short and the suffix starts late. Pad each
        // shortfall with spaces (a wide glyph can't be half-drawn — the gap is
        // the standard treatment), otherwise every base row with a straddling
        // wide character composites the overlay one cell left and pulls the
        // rest of the row in behind it — ragged pop-up borders next to emoji.
        let prefix = split.prefixWidth < column
            ? split.prefix + String.spaces(column - split.prefixWidth)
            : split.prefix
        var suffix = split.suffix
        let expectedSuffixWidth = max(0, split.totalWidth - afterOverlayColumn)
        let suffixShortfall = expectedSuffixWidth - split.suffixWidth
        if suffixShortfall > 0 {
            suffix = String.spaces(suffixShortfall) + suffix
        }
        // A caller that wants the line to reach a column past everything the
        // base had (a run's end, when its frame is narrower than the run) gets
        // the extra cells as plain spaces AFTER the suffix — where a pad of the
        // base before the split would have put them.
        let trailing = minimumTotalWidth - max(split.totalWidth, afterOverlayColumn)
        if trailing > 0 {
            suffix += String.spaces(trailing)
        }

        // Restore the styling ACTIVE at the suffix's start column (not the line's
        // leading state). A uniform background set up at the leading is still in
        // force there, so it's preserved; but inline text decorations the prefix
        // turned on and then RESET (e.g. an underlined `DemoSection` header
        // followed by plain padding) are NOT carried onto the suffix — the bug
        // where the cell just past a composited overlay inherited the underline.
        // The split nets the escapes before the column, so an open+reset pair
        // leaves nothing while a persistent background (and its lone trailing BG
        // code) nets to the background.
        //
        // Reading that state off the PADDED base rather than the unpadded
        // original is not a shortcut: padding only ever appends plain spaces
        // after every escape the line has, so the set of SGRs before any column
        // is the same in both. (It used to be passed in separately, which cost a
        // whole extra scan to reach the same answer.)
        var head = prefix
        head += ansiReset
        var tail = ansiReset
        tail += split.styleBeforeSuffix
        tail += suffix
        return (head, tail)
    }
}
