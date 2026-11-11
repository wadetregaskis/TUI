//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderLoop+Cursor.swift
//
//  Where a frame leaves the terminal's hidden cursor: on the focused text
//  control's insertion point, so that what an input method composes there —
//  Apple Terminal's pending accent after ⌥E — appears on the caret. And, in
//  the proof of concept `TUI_TEXT_CURSOR_FOLLOWS_FOCUS` turns on, on any focused
//  control, shown or not (`Documentation/Input and focus/Text cursor follows focus
//  (proof of concept).md`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// Whether the terminal's own text cursor (not the mouse pointer) follows the
/// focus: the proof of concept `TUI_TEXT_CURSOR_FOLLOWS_FOCUS` turns on, off
/// by default.
enum TextCursorFollowsFocus: Equatable {
    /// On the focused control, and shown: `1` or `show`.
    case shown

    /// On the focused control, and kept hidden, for whatever tracks a hidden
    /// cursor's place: `hidden`.
    case hidden

    /// What `environment` asks for, or `nil` for the cursor hidden and parked
    /// on a text control's insertion point alone, as without the variable.
    static func requested(environment: [String: String]) -> Self? {
        switch environment["TUI_TEXT_CURSOR_FOLLOWS_FOCUS"] {
        case "1", "show": .shown
        case "hidden": .hidden
        default: nil
        }
    }
}

extension RenderLoop {
    /// Where a frame leaves the terminal's cursor: the focused text control's
    /// insertion point (``insertionPointOnScreen(in:width:height:)``), and,
    /// while the cursor follows the focus (``textCursorFollowsFocus``), any other
    /// focused control's first cell on screen — the top-left of the first
    /// region carrying its focus id, which for a `List` or a `Table` is the
    /// cursor row's (the one an enclosing `ScrollView` reveals).
    func cursorTarget(in regions: [HitTestRegion], width: Int, height: Int) -> CellPoint? {
        if let caret = insertionPointOnScreen(in: regions, width: width, height: height) { return caret }
        guard textCursorFollowsFocus != nil, let focusID = focusManager.currentFocusedID,
            let region = regions.first(where: { $0.focusID == focusID && $0.width > 0 && $0.height > 0 })
        else { return nil }
        let corner = CellPoint(x: region.offsetX, y: region.offsetY)
        guard corner.x >= 0, corner.y >= 0, corner.x < width, corner.y < height else { return nil }
        return corner
    }

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
            let region = regions.last(where: { $0.focusID == focused.focusID && !$0.isGeometryMarker })
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
    ///
    /// While the cursor follows the focus and is shown (``TextCursorFollowsFocus/shown``),
    /// each move is followed by showing it, and a frame with nothing focused on
    /// screen hides it again. Shown at every move rather than once, because a
    /// resume from a suspend hides it behind the loop's back
    /// (`AppRunner.retakeTerminal`); the repaint after one moves it here again.
    func parkCursor(at point: CellPoint?, afterWriting wrote: Bool) {
        defer { parkedCursor = point }
        let shows = textCursorFollowsFocus == .shown
        guard let point else {
            if shows, showsCursor {
                terminal.hideCursor()
                showsCursor = false
            }
            return
        }
        guard wrote || point != parkedCursor else { return }
        terminal.moveCursor(toRow: point.y + 1, column: point.x + 1)
        if shows {
            terminal.showCursor()
            showsCursor = true
        }
    }
}
