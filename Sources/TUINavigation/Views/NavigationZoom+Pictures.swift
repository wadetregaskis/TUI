//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationZoom+Pictures.swift
//
//  The pictures on a screen a navigation zoom reveals or folds away, scaled
//  and moved from the source's frame to their own rather than cut by the
//  zoom's rectangle: a cell of text cannot be drawn smaller, but a picture the
//  terminal draws can, by a second placement of it at the scale it is drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

/// How a navigation zoom draws the pictures of the screen it reveals or folds
/// away: moved and scaled from the source's frame to the frame they have on
/// that screen, as SwiftUI's zoom takes its destination from the source's
/// frame to its own. A photo zoomed up from its thumbnail starts exactly on
/// the thumbnail and grows into its place on the screen; folded back, it lands
/// exactly on the thumbnail. The rest of the screen is cut by the zoom's
/// rectangle, as before: a cell of text cannot be drawn smaller.
///
/// The pictures move as one: the box they fill together is mapped from the
/// source's frame to itself, edge by edge as the rectangle is
/// (``MatchedEdgeOffsets``), and each picture with it — so a screen's one
/// photo fills the source's frame at the zoom's far end, and two side by side
/// share it as they share the screen. Their frame is always inside the
/// rectangle, which goes from the same source to the whole stack.
///
/// They were scaled by the map from the whole stack to the rectangle until
/// 2026-10-27: a photo under its screen's navigation bar, smaller than the
/// stack, then landed smaller than the thumbnail it folded into, the bar's
/// rule cut across the rest of the rectangle, and the page's own thumbnail
/// replaced it with a pop once the zoom was over.
///
/// The owner, on the Navigation clip's photo folding back: "it should scale
/// and move, whereas it's scaling and *clipping*". A picture is drawn by a
/// second placement of its image (`p=2`) at the scaled size
/// (``TerminalImageStore/scaledPlaceholderRows(of:columns:rows:)``): no
/// pixels are sent, and the image's own placement, which every other cell
/// drawing it names, is untouched.
struct ZoomScaling {
    /// The source's frame, in the stack: where the pictures are at the
    /// zoom's far end — the start of a reveal, the end of a fold.
    let source: CellRect
    /// How much of the way from their own frames to the source's the
    /// pictures are this frame: `1` on the source, `0` in their places.
    let remaining: Double
    /// The store the pictures are the images of.
    let images: TerminalImageStore

    /// A picture found on the zoomed screen: its image, and where its whole
    /// box sits on the screen — where its cell (0, 0) is, whether or not that
    /// cell is drawn.
    struct Picture {
        let id: KittyGraphics.ImageID
        let x: Int
        let y: Int
        let columns: Int
        let rows: Int
    }

    /// The pictures `content` draws, each once, and `content` with their cells
    /// blanked: what the rectangle cuts is the rest of the screen, and the
    /// pictures are drawn again over it, scaled (``drawings(of:within:)``).
    func liftingPictures(out content: inout FrameBuffer) -> [Picture] {
        guard content.lines.contains(where: { $0.unicodeScalars.contains(.terminalImagePlaceholder) }) else {
            return []
        }
        var found: [Picture] = []
        var lines = content.lines
        for (y, line) in lines.enumerated() where line.unicodeScalars.contains(.terminalImagePlaceholder) {
            // The ink in force, which names each picture cell's image.
            var state = SGRState()
            var x = 0
            var out = ""
            out.reserveCapacity(line.utf8.count)
            _ = line.forEachANSISegment { segment in
                switch segment {
                // A rendered line's escape segment, not a colour: the rule
                // matches `.ansi(` wherever it is written.
                // swiftlint:disable:next framework_colour_literal
                case .ansi(let text, _):
                    out += text
                    state.apply(text)
                case .visible(let character):
                    // A pattern reading the ink's channels, not a colour this
                    // draws with.
                    // swiftlint:disable:next framework_colour_literal
                    if case .rgb(let red, let green, let blue)? = state.foregroundColour,
                        let cell = KittyGraphics.placeholderCell(
                            character,
                            foreground: (UInt8(clamping: red), UInt8(clamping: green), UInt8(clamping: blue)))
                    {
                        if !found.contains(where: { $0.id == cell.id }), let box = images.placementBox(of: cell.id) {
                            found.append(
                                Picture(
                                    id: cell.id, x: x - cell.column, y: y - cell.row,
                                    columns: box.columns, rows: box.rows))
                        }
                        out.append(" ")
                    } else {
                        out.append(character)
                    }
                    x += max(1, character.terminalWidth)
                }
                return true
            }
            lines[y] = out
        }
        content = content.replacingLines(lines, width: content.width)
        return found
    }

    /// `pictures` drawn as the zoom maps them this frame — the box they fill
    /// together moved and scaled from the source's frame toward its own, each
    /// picture with it — each cut to `visible`, with the column and row it is
    /// laid at; a picture none of which is visible, or that the store cannot
    /// draw, is left out.
    func drawings(
        of pictures: [Picture], within visible: CellRect
    ) -> [(cells: FrameBuffer, x: Int, y: Int)] {
        guard let first = pictures.first else { return [] }
        var minX = first.x, minY = first.y, maxX = first.x + first.columns, maxY = first.y + first.rows
        for picture in pictures.dropFirst() {
            minX = min(minX, picture.x)
            minY = min(minY, picture.y)
            maxX = max(maxX, picture.x + picture.columns)
            maxY = max(maxY, picture.y + picture.rows)
        }
        let box = CellRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let frame = MatchedEdgeOffsets(from: source, to: box).applied(to: box, remaining: remaining)
        return pictures.compactMap { drawing($0, from: box, into: frame, within: visible) }
    }

    /// `picture`, one of those filling `box`, drawn where the map that takes
    /// `box` to `frame` takes it, at that scale, cut to `visible`.
    private func drawing(
        _ picture: Picture, from box: CellRect, into frame: CellRect, within visible: CellRect
    ) -> (cells: FrameBuffer, x: Int, y: Int)? {
        let scaleX = Double(frame.width) / Double(max(1, box.width))
        let scaleY = Double(frame.height) / Double(max(1, box.height))
        let left = frame.x + Int((Double(picture.x - box.x) * scaleX).rounded())
        let top = frame.y + Int((Double(picture.y - box.y) * scaleY).rounded())
        let columns = max(1, Int((Double(picture.columns) * scaleX).rounded()))
        let rows = max(1, Int((Double(picture.rows) * scaleY).rounded()))
        let shown = (
            left: max(left, visible.x), top: max(top, visible.y),
            right: min(left + columns, visible.maxX), bottom: min(top + rows, visible.maxY))
        guard shown.right > shown.left, shown.bottom > shown.top,
            let cells = images.scaledPlaceholderRows(of: picture.id, columns: columns, rows: rows)
        else { return nil }
        let cut = cells[(shown.top - top)..<(shown.bottom - top)].map {
            $0.ansiAwareSlice(visibleStart: shown.left - left, visibleCount: shown.right - shown.left)
        }
        return (FrameBuffer(lines: cut), shown.left, shown.top)
    }
}
