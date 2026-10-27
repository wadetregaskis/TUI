//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationZoom+Pictures.swift
//
//  The pictures on a screen a navigation zoom reveals or folds away, scaled
//  and moved with the zoom's rectangle rather than cut by it: a cell of text
//  cannot be drawn smaller, but a picture the terminal draws can, by a
//  second placement of it at the rectangle's scale.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

/// How a navigation zoom draws the pictures of the screen it reveals or folds
/// away: each scaled and moved by the map that takes the whole stack to the
/// zoom's rectangle this frame, so a photo zoomed up from its thumbnail grows
/// from the thumbnail's size and place, and folds back into it, as SwiftUI's
/// zoom scales its screen. The rest of the screen is cut by the rectangle, as
/// before: a cell of text cannot be drawn smaller.
///
/// The owner, on the Navigation clip's photo folding back: "it should scale
/// and move, whereas it's scaling and *clipping*". A picture is drawn by a
/// second placement of its image (`p=2`) at the scaled size
/// (``TerminalImageStore/scaledPlaceholderRows(of:columns:rows:)``): no
/// pixels are sent, and the image's own placement, which every other cell
/// drawing it names, is untouched.
struct ZoomScaling {
    /// The whole stack, which the rectangle grows to and shrinks from.
    let whole: CellRect
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
    /// pictures are drawn again over it, scaled (``drawing(_:into:within:)``).
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

    /// `picture` drawn as the zoom maps it into `rect` this frame — its box
    /// scaled as the whole stack is to the rectangle, and moved with it — cut
    /// to `visible`, with the column and row it is laid at; or `nil` where
    /// none of it is visible, or the store cannot draw it.
    func drawing(
        _ picture: Picture, into rect: CellRect, within visible: CellRect
    ) -> (cells: FrameBuffer, x: Int, y: Int)? {
        let scaleX = Double(rect.width) / Double(max(1, whole.width))
        let scaleY = Double(rect.height) / Double(max(1, whole.height))
        let left = rect.x + Int((Double(picture.x - whole.x) * scaleX).rounded())
        let top = rect.y + Int((Double(picture.y - whole.y) * scaleY).rounded())
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
