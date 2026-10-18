//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScreenSelection+Frame.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

// MARK: - The frame

extension ScreenSelection {
    /// Takes in the frame's page, before the layers over it are composited:
    /// keeps its lines for the next selection, and, while there is one,
    /// follows it and draws its highlight.
    ///
    /// - A resize clears the selection: the cells it named are gone. Only the
    ///   width says so; the content area's height also moves with the status
    ///   bar's rows, which is no reason to lose a selection.
    /// - A selection being made follows the screen, as a terminal's does.
    /// - A finished one keeps its text, and its highlight goes when the cells
    ///   under it no longer read that text. Where the content area is where
    ///   the highlight was last drawn, the cells themselves changed — a log
    ///   scrolled on, a spinner turned — and it is gone for good: a highlight
    ///   that came back whenever they read the text again blinked over a
    ///   cycling line, its keys with it, and an equal line scrolling into
    ///   place revived a selection long gone. Such a selection is dropped,
    ///   so no later frame pays to read its cells, unless its own menu is
    ///   open over it. Where the content area moved —
    ///   a status-bar tooltip's row, a copy's line, taking a row from a
    ///   centred page — the page moved under it, and it comes back, keys and
    ///   all, when the area is back and the cells read the text again.
    /// - A presentation over the page — a sheet, an alert, an open menu —
    ///   clears it too: what is under a modal's backdrop is not the user's to
    ///   copy, and its keys are the presentation's. The selection's own menu
    ///   is the exception.
    ///
    /// `top` is the screen row the page is drawn from, below the window's top
    /// bar.
    @MainActor
    func takeFrame(
        _ buffer: FrameBuffer, width: Int, palette: any Palette, top: Int = 0,
        underPresentation: Bool = false
    ) -> FrameBuffer {
        let resized = width != frameWidth
        frameLines = buffer.lines
        frameWidth = width
        frameTop = top
        guard var selection = current else { return buffer }
        if resized || (underPresentation && menuAnchor == nil) {
            clear()
            return buffer
        }
        // Gone for good, its menu still open over it (below): nothing to
        // follow, and no cells to read again.
        guard selection.isMaking || selection.shownIn != nil else { return buffer }
        let drawn = Self.text(of: selection, in: frameLines)
        let area = contentArea
        if selection.isMaking {
            selection.text = drawn
            selection.shownIn = area
        } else if let shownIn = selection.shownIn {
            if drawn == selection.text, selection.isHighlighted || area == shownIn {
                selection.isHighlighted = true
                selection.shownIn = area
            } else {
                selection.isHighlighted = false
                // The page did not move: the cells changed under it. Gone for
                // good, so dropped, and no later frame reads its cells — unless
                // its own menu is open over it, whose Copy copies what was
                // selected; then it is kept, unread, until the menu goes.
                if area == shownIn {
                    guard menuAnchor != nil else {
                        clear()
                        return buffer
                    }
                    selection.shownIn = nil
                }
            }
        }
        current = selection
        guard selection.isHighlighted else { return buffer }
        return Self.highlighting(selection, in: buffer, palette: palette, pictures: buffer.hitTestRegions.pictureRects)
    }
}

// MARK: - Drawing the highlight

extension ScreenSelection {
    /// `buffer` with `selection`'s cells drawn in the selection colours of the
    /// text inputs (``FieldTextLayout/selectionColors(palette:background:ink:)``), reverse video
    /// where the palette leaves the colours to the terminal.
    ///
    /// Except a picture's cells (`pictures`, read off the frame's
    /// `HitTestRegion.pictureCorners`): their glyphs and colours ARE the
    /// picture — a solid style's pixels are spaces on their colour, a fine
    /// style's two pixels a half block's two colours — so the selection
    /// colour is laid over them, translucent, rather than drawn in their place,
    /// which left a flat field of selection colour where a picture was, or
    /// half blocks scattered over one.
    ///
    /// Composited as a painted layer over the page, so the cells
    /// under it give up what they claimed there: an opacity region stops
    /// fading them, and an animated run stops redrawing them, as under a menu.
    @MainActor
    static func highlighting(
        _ selection: Selection, in buffer: FrameBuffer, palette: any Palette, pictures: [CellRect] = []
    ) -> FrameBuffer {
        let colors = Self.selectionColors(palette: palette, background: nil)
            .resolved(with: palette)
        var style = TextStyle()
        style.foregroundColor = colors.isReversed ? colors.background : colors.foreground
        style.backgroundColor = colors.isReversed ? colors.foreground : colors.background
        style.isInverted = colors.isReversed
        let introducer = ANSIRenderer.styleSequence(for: style)

        var cache: [Int: [Character?]] = [:]
        func cellsOf(_ row: Int) -> [Character?] {
            if let cached = cache[row] { return cached }
            let cells = row >= 0 && row < buffer.lines.count ? Self.cells(of: buffer.lines[row]) : []
            cache[row] = cells
            return cells
        }
        let (start, end) = ends(of: selection, cells: cellsOf)
        var resolved = selection
        (resolved.anchor, resolved.head) = (start, end)
        resolved.unit = .character

        // Rows with the same columns go in one layer: a stream selection is at
        // most three, a rectangle one.
        var result = buffer
        var band: (columns: Range<Int>, top: Int, lines: [String])?
        func flush() {
            guard let finished = band else { return }
            result = result.compositedResolvingOpacity(
                with: FrameBuffer(lines: finished.lines), at: (x: finished.columns.lowerBound, y: finished.top),
                palette: palette, overlayIsPainted: true)
            band = nil
        }
        /// The selected text of `columns`, in the selection's colours.
        func highlighted(_ columns: Range<Int>, of cells: [Character?]) -> String {
            var text = ""
            for column in columns {
                if column < cells.count {
                    if let character = cells[column] { text.append(character) }
                } else {
                    text.append(" ")
                }
            }
            return ANSIRenderer.wrap(text, in: introducer)
        }
        for row in start.y...max(start.y, end.y) where row < buffer.lines.count {
            let cells = cellsOf(row)
            guard let columns = Self.columns(of: resolved, onRow: row, cells: cells) else {
                flush()
                continue
            }
            // A picture's cells on this row are tinted, and the text either
            // side of them highlighted as text, each a layer of its own.
            if !pictures.isEmpty {
                let (text, tinted) = Self.splitting(columns, onRow: row, by: pictures)
                if !tinted.isEmpty {
                    flush()
                    for segment in text {
                        result = result.compositedResolvingOpacity(
                            with: FrameBuffer(lines: [highlighted(segment, of: cells)]),
                            at: (x: segment.lowerBound, y: row), palette: palette, overlayIsPainted: true)
                    }
                    for span in tinted {
                        result = Self.tinting(span, onRow: row, of: result, colour: style.backgroundColor, palette: palette)
                    }
                    continue
                }
            }
            let line = highlighted(columns, of: cells)
            if let open = band, open.columns == columns, open.top + open.lines.count == row {
                band?.lines.append(line)
            } else {
                flush()
                band = (columns, row, [line])
            }
        }
        flush()
        return result
    }

    /// The share of the selection colour laid over a picture's cells: under
    /// half, so the picture's own glyphs still draw (`Opacity as composition`,
    /// the glyph contest), and enough to read as selected.
    static let pictureTint = 0.45

    /// `columns` of `row` split into what a picture covers and what it does
    /// not: the text segments, left to right, and the picture spans.
    static func splitting(
        _ columns: Range<Int>, onRow row: Int, by pictures: [CellRect]
    ) -> (text: [Range<Int>], tinted: [Range<Int>]) {
        let tinted = pictures
            .filter { (picture: CellRect) in (picture.y..<(picture.y + picture.height)).contains(row) }
            .map { columns.clamped(to: $0.x..<($0.x + $0.width)) }
            .filter { !$0.isEmpty }
            .sorted { $0.lowerBound < $1.lowerBound }
        guard !tinted.isEmpty else { return ([columns], []) }
        var text: [Range<Int>] = []
        var from = columns.lowerBound
        for span in tinted {
            if span.lowerBound > from { text.append(from..<span.lowerBound) }
            from = max(from, span.upperBound)
        }
        if from < columns.upperBound { text.append(from..<columns.upperBound) }
        return (text, tinted)
    }

    /// `buffer` with the selection colour laid over `span` of `row`, at
    /// ``pictureTint``: the cells keep their glyphs, and their colours move
    /// toward the selection's.
    @MainActor
    static func tinting(
        _ span: Range<Int>, onRow row: Int, of buffer: FrameBuffer, colour: Color?, palette: any Palette
    ) -> FrameBuffer {
        guard let colour, !span.isEmpty else { return buffer }
        var layer = FrameBuffer(lines: [
            ANSIRenderer.colorize(String.spaces(span.count), background: colour.opaqueSpelling)
        ])
        layer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: span.count, height: 1, opacity: pictureTint)
        ]
        return buffer.compositedResolvingOpacity(
            with: layer, at: (x: span.lowerBound, y: row), palette: palette, overlayIsPainted: true)
    }
}
