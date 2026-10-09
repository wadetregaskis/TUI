//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DividerDrag.swift
//
//  A one-cell rule the user drags to move a boundary — a split view's divider
//  between two panes, and the grabber on a detented sheet's top edge between
//  the sheet and the page: the rule as drawn, and the pointer's gesture on it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

/// The rule a divider is drawn as: a line one cell thick.
package enum DividerRule {
    /// A rule `length` cells long, drawn in `colour`, between panes laid out
    /// along `axis`: a column of `│` between side-by-side panes, a row of `─`
    /// between stacked ones.
    package static func buffer(across axis: Axis, length: Int, colour: Color) -> FrameBuffer {
        let glyph = axis == .horizontal ? "│" : "─"
        let painted = ANSIRenderer.colorize(glyph, foreground: colour.opaqueSpelling)
        return axis == .horizontal
            ? FrameBuffer(lines: Array(repeating: painted, count: max(0, length)))
            : FrameBuffer(lines: [String(repeating: painted, count: max(0, length))])
    }
}

/// A press on a divider and the drag that follows it.
///
/// The press takes the base the gesture moves from — the panes' sizes, the
/// sheet's height — and every later event of the gesture moves the divider by
/// the distance travelled since the press. Measured from the PRESS, not from
/// the last event: a drag is localised to the region that captured it, and
/// that region is the one-cell rule the press landed on, so the coordinate
/// along the divider's axis IS the signed distance moved.
///
/// A struct kept in the divider's handler, which outlives the frame.
package struct DividerDrag<Base> {
    /// What the current gesture moves from, or `nil` when none is under way.
    private(set) var base: Base?

    /// No gesture under way. Spelled out because the implicit initializer is
    /// internal, and the split views (TUIkitNavigation) and the sheet's
    /// grabber (TUIkitPresentation) make these.
    package init() {}

    /// Handles a left-button press, drag or release on the divider, reporting
    /// whether it took the event.
    ///
    /// - Parameters:
    ///   - event: The event, localised to the divider's region.
    ///   - axis: The axis the divider moves along: `.vertical` for a rule
    ///     dragged up and down.
    ///   - press: Called on the press. Focuses the divider and answers what the
    ///     gesture moves from.
    ///   - move: Called on every drag and on the release with the distance
    ///     moved since the press (down or right is positive) and the base.
    package mutating func handle(
        _ event: MouseEvent, along axis: Axis, press: () -> Base, move: (_ delta: Int, _ base: Base) -> Void
    ) -> Bool {
        guard event.button == .left else { return false }
        switch event.phase {
        case .pressed:
            base = press()
            return true
        case .dragged, .released:
            if let base { move(axis == .horizontal ? event.x : event.y, base) }
            if event.phase == .released { base = nil }
            return true
        default:
            return false
        }
    }
}
