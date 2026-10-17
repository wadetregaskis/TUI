//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoop+Cursor.swift
//
//  Where a frame leaves the terminal's hidden cursor: on the focused text
//  control's insertion point, so that what an input method composes there —
//  Apple Terminal's pending accent after ⌥E — appears on the caret.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension RenderLoop {
    /// The focused text control's insertion point on screen, in cells from
    /// the top-left, or `nil` where no text control has the focus, it keeps
    /// no insertion point, or the point is off the visible part of its region.
    ///
    /// The control reports the point in its own region's coordinates
    /// (``TextInputFocusHandler/insertionPoint``), so the region carrying its
    /// focus id places it, measured from where the region's coordinates start
    /// (`localOriginX`, `localOriginY`) and kept to what the region shows:
    /// inside a scroll view that has scrolled it partly away, only the cells
    /// still drawn count. The last such region is the control's own, which is
    /// emitted after any container's.
    func insertionPointOnScreen(in regions: [HitTestRegion], width: Int, height: Int) -> CellPoint? {
        guard let focused = focusManager.currentFocused,
            let point = (focused as? any TextInputFocusHandler)?.insertionPoint,
            let region = regions.last(where: { $0.focusID == focused.focusID })
        else { return nil }
        let onScreen = CellPoint(x: region.localOriginX + point.x, y: region.localOriginY + point.y)
        guard region.contains(x: onScreen.x, y: onScreen.y), onScreen.x < width, onScreen.y < height else {
            return nil
        }
        return onScreen
    }

    /// Leaves the terminal's hidden cursor on `point`, the focused text
    /// control's insertion point, after a frame or a replay tick.
    ///
    /// A terminal draws what an input method is composing at its cursor, hidden
    /// or not: Apple Terminal shows the pending accent of ⌥E there, inserted,
    /// pushing the rest of the row right until the next key finishes it. Left
    /// where the frame's last write ended, the accent appeared somewhere on
    /// the row with no connection to the field, and moved what followed it;
    /// parked on the caret it appears where the accented letter will, as
    /// marked text does in any Mac text field. See
    /// `Documentation/Terminals/Terminal compatibility survey.md`, Apple Terminal.app, "Dead keys".
    ///
    /// Moved only when something put it elsewhere — the write — or the point
    /// itself moved, so a frame that writes nothing writes nothing for this
    /// either.
    func parkCursor(at point: CellPoint?, afterWriting wrote: Bool) {
        defer { parkedCursor = point }
        guard let point, wrote || point != parkedCursor else { return }
        terminal.moveCursor(toRow: point.y + 1, column: point.x + 1)
    }
}
