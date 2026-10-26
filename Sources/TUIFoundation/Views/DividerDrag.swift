//  🖥️ TUI — A Terminal UI framework for Swift
//  DividerDrag.swift
//
//  A one-cell rule the user drags to move a boundary — a split view's divider
//  between two panes, and the grabber on a detented sheet's top edge between
//  the sheet and the page: the rule as drawn, and the pointer's gesture on it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

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

    /// ``buffer(across:length:colour:)`` with a grip at its middle: three `◦`
    /// in the rule's colour, as a `NavigationSplitView`'s resizable divider
    /// draws them — the cue that the rule is there to be dragged. None on a
    /// rule too short to keep some of itself either side, and none at
    /// `skipping`, a cell its owner draws something else in.
    package static func buffer(
        across axis: Axis, length: Int, colour: Color, gripSkipping skipped: Int?
    ) -> FrameBuffer {
        guard length >= 5 else { return buffer(across: axis, length: length, colour: colour) }
        let glyph = axis == .horizontal ? "│" : "─"
        let centre = length / 2
        let grip = Set([centre - 1, centre, centre + 1].filter { $0 != skipped })
        let cells = (0..<length).map { index in
            ANSIRenderer.colorize(grip.contains(index) ? "◦" : glyph, foreground: colour.opaqueSpelling)
        }
        return axis == .horizontal ? FrameBuffer(lines: cells) : FrameBuffer(lines: [cells.joined()])
    }
}

/// What a key does to a divider: the one reading of the keyboard that every
/// resizable divider shares, so a `NavigationSplitView` column divider and an
/// `HSplitView` / `VSplitView` divider answer the same keys.
package enum DividerKeyMove: Equatable {
    /// Moves the divider this many cells — negative toward the start (left or
    /// up), positive toward the end.
    case by(Int)
    /// Moves the divider as far toward the start as its bounds allow.
    case toStart
    /// Moves the divider as far toward the end as its bounds allow.
    case toEnd

    /// A distance no divider can travel: moving by it (or its negative) goes as
    /// far as the divider's bounds allow, and a quarter of `Int.max` keeps the
    /// sum with any size from overflowing.
    package static let farthest = Int.max / 4

    /// What `event` does to a divider that moves along `axis`, or `nil` for a
    /// key a divider has no use for: the two arrows along the axis (one cell,
    /// five with Shift), Home for the start and End for the end.
    package static func of(_ event: KeyEvent, along axis: Axis) -> Self? {
        let step = event.shift ? 5 : 1
        switch (axis, event.key) {
        case (.horizontal, .left), (.vertical, .up): return .by(-step)
        case (.horizontal, .right), (.vertical, .down): return .by(step)
        case (_, .home): return .toStart
        case (_, .end): return .toEnd
        default: return nil
        }
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
    /// internal, and the split views (TUINavigation) and the sheet's
    /// grabber (TUIPresentation) make these.
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
