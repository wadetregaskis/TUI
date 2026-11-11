//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusManagerGeometricArrows.swift
//
//  Arrow keys that move the focus to the nearest control in their direction,
//  on screen or scrolled out of sight, rather than to the next or previous in
//  Tab order: an experiment,
//  on with `TUI_ARROW_FOCUS=geometric`, or for the rest of the run with the
//  View menu's or the settings panel's Arrows Follow Layout. See `Documentation/Input and focus/
//  Geometric arrow focus.md` for the design and what keeping both modes costs.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// How the arrow keys a focused control leaves unused move the focus between
/// controls.
package enum ArrowFocus: Sendable, Equatable {
    /// To the next (→, ↓) or previous (←, ↑) control in Tab order. The default.
    case tabOrder

    /// To the nearest control in the arrow's direction, on screen or scrolled
    /// out of sight; in Tab order only to a control geometry cannot place.
    case geometric

    /// What the user asked for: `.geometric` with `TUI_ARROW_FOCUS=geometric`
    /// in `environment`, `.tabOrder` with `tab`, and `nil` with any other
    /// value or none, where what the person kept in the settings panel
    /// decides. Only the app runner asks, as it does for
    /// `TUI_CURSOR_FOLLOWS_FOCUS`.
    package static func requested(environment: [String: String]) -> Self? {
        switch environment["TUI_ARROW_FOCUS"] {
        case "geometric": .geometric
        case "tab": .tabOrder
        default: nil
        }
    }
}

private struct ArrowFocusKey: EnvironmentKey {
    static let defaultValue = ArrowFocus.tabOrder
}

extension EnvironmentValues {
    /// How the arrow keys move the focus: the user's `TUI_ARROW_FOCUS`,
    /// written at the root of each frame, replaced by the person's choice in
    /// the View menu or the settings panel (`ViewPreferenceOverrides`), which
    /// lasts the run. The render loop hands it to the focus manager once the
    /// scene's statements are in (``FocusManager/arrowFocus``).
    package var arrowFocus: ArrowFocus {
        get { self[ArrowFocusKey.self] }
        set { self[ArrowFocusKey.self] = newValue }
    }
}

/// The focus manager's arrow state: the mode, and the frame the geometric
/// arrows go by.
struct ArrowFocusState {
    var mode: ArrowFocus = .tabOrder

    /// The hit-test regions of the last frame drawn, in screen coordinates,
    /// where the geometric arrows find each control's frame by its focus id:
    /// the cells it drew, and the corners a scroll view left where it clipped
    /// it (``Swift/Array/appendFocusFrameCorners(of:clippedTo:rows:)``). Posted
    /// by the render loop only while ``mode`` is `.geometric`.
    var laidOutRegions: [HitTestRegion] = []
}

extension FocusManager {
    /// How the arrow keys a focused control leaves unused move the focus: in
    /// Tab order, or to the nearest control in the arrow's direction.
    package var arrowFocus: ArrowFocus {
        get { arrows.mode }
        set { arrows.mode = newValue }
    }

    /// The regions the geometric arrows go by: see ``ArrowFocusState/laidOutRegions``.
    package var laidOutRegions: [HitTestRegion] {
        get { arrows.laidOutRegions }
        set { arrows.laidOutRegions = newValue }
    }

    /// An arrow the focused control left unused: Up and Left to the previous
    /// control in the active section, Down and Right to the next, without
    /// wrapping — or, under `TUI_ARROW_FOCUS=geometric`, to the nearest control
    /// in the arrow's direction, and in Tab order only where geometry cannot
    /// decide (``GeometricMove/undecided``).
    ///
    /// - Returns: Whether `key` is an arrow, which is then handled whether or
    ///   not the focus could move.
    func moveFocus(byArrow key: Key) -> Bool {
        let forward: Bool
        switch key {
        case .up, .left: forward = false
        case .down, .right: forward = true
        default: return false
        }
        guard moveFocusGeometrically(for: key) == .undecided else { return true }
        if forward { focusNextInSection() } else { focusPreviousInSection() }
        return true
    }

    /// What the geometric arrows made of an arrow.
    private enum GeometricMove {
        /// The focus moved to the nearest control that way.
        case moved
        /// Nothing lies that way, and the Tab-order neighbour lies some other
        /// way: the focus stays, as it does at the end of a row or a column.
        /// Going on in Tab order there would wrap — → at a row's end to the
        /// next row's start, ↓ at a column's foot to the next column's top —
        /// which the owner ruled out.
        case stopped
        /// Geometry cannot say: Tab-order mode, nothing focused, the focused
        /// control not laid out, or nothing that way while the Tab-order
        /// neighbour has no frame (a custom `Focusable` that draws none, one
        /// cut by a clip that is not a scroll view's), so it could lie that
        /// way. The arrow goes on in Tab order.
        case undecided
    }

    /// Moves the focus to the nearest focusable control in `key`'s direction in
    /// the active section, when ``arrowFocus`` is `.geometric`.
    ///
    /// The candidates are the section's controls the last frame laid out —
    /// drew, or drew and a scroll view then clipped out of sight — whose
    /// frames lie wholly beyond the focused control's edge in that direction —
    /// below its bottom for ↓, and so on. Of those, one that overlaps the
    /// focused control on the other axis (its *beam*: the columns it spans for
    /// ↑ and ↓, the rows for ← and →) beats one that does not, however far;
    /// then the nearer wins; then the earlier in Tab order, so the choice never
    /// depends on anything but the layout.
    ///
    /// The active section is all it looks in, as the Tab-order arrows are: a
    /// sheet's, an alert's or a popover's section keeps the arrows inside it.
    ///
    /// Focusing a control out of sight is all it does: the scroll views around
    /// it reveal it on the frame that follows, as they do a control Tab
    /// reached, the innermost first.
    ///
    /// With no candidate, the Tab-order neighbour that way decides: one with a
    /// frame lies some other way, so the focus stays (``GeometricMove/stopped``);
    /// one without could lie anywhere, so the caller goes on in Tab order.
    private func moveFocusGeometrically(for key: Key) -> GeometricMove {
        guard arrows.mode == .geometric, let section = activeSection, let currentID = currentFocusedID
        else { return .undecided }
        let frames = Self.focusFrames(in: arrows.laidOutRegions)
        guard let origin = frames[currentID] else { return .undecided }
        var best: (control: Focusable, rank: ArrowRank)?
        for (order, control) in section.focusables.enumerated()
        where control.focusID != currentID && control.canBeFocused {
            guard let frame = frames[control.focusID],
                let rank = ArrowRank(from: origin, to: frame, key: key, order: order)
            else { continue }
            if best.map({ rank < $0.rank }) ?? true { best = (control, rank) }
        }
        if let best {
            focus(best.control)
            return .moved
        }
        let ring = section.focusables
        let forward = key == .down || key == .right
        guard let anchor = ring.firstIndex(where: { $0.focusID == currentID }),
            let neighbour = Self.nearestFocusable(in: ring, from: anchor, forward ? .forward : .backward, wrap: false),
            frames[neighbour.focusID] == nil
        else { return .stopped }
        return .undecided
    }

    /// Each focus id's frame in screen coordinates: the smallest rectangle
    /// holding every non-empty region the frame drew for it, and every corner
    /// a scroll view left where it clipped it, so a control half or wholly out
    /// of sight is its whole frame, where it lies off the viewport's edge. A
    /// control drawn in pieces — a wrapped label, a border's rule — is one
    /// frame.
    private static func focusFrames(in regions: [HitTestRegion]) -> [String: CellFrame] {
        var frames: [String: CellFrame] = [:]
        for region in regions where (region.width > 0 && region.height > 0) || region.isGeometryMarker {
            guard let focusID = region.focusID else { continue }
            let frame = CellFrame(
                minX: region.offsetX, minY: region.offsetY,
                maxX: region.offsetX + region.width, maxY: region.offsetY + region.height)
            frames[focusID] = frames[focusID].map { $0.union(frame) } ?? frame
        }
        return frames
    }
}

/// A rectangle of cells, its max edges exclusive.
private struct CellFrame {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int

    func union(_ other: Self) -> Self {
        Self(
            minX: min(minX, other.minX), minY: min(minY, other.minY),
            maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY))
    }
}

/// How good a candidate is for an arrow: lower is better.
private struct ArrowRank: Comparable {
    /// Whether the candidate lies outside the focused control's beam.
    let outsideBeam: Bool
    /// The squared distance between the two frames' nearest edges, a row
    /// counting as ``rowAspect`` columns.
    let distance: Int
    /// The candidate's place in Tab order.
    let order: Int

    /// A terminal cell is about twice as tall as it is wide, so a row away is
    /// as far as two columns away.
    private static let rowAspect = 2

    /// `nil` unless `frame` lies wholly beyond `origin`'s edge in `key`'s
    /// direction (touching counts), or `key` is not an arrow.
    init?(from origin: CellFrame, to frame: CellFrame, key: Key, order: Int) {
        // How far beyond the edge, along the arrow, and how far apart across
        // it (0 inside the beam), in cells; and whether the spans across it
        // cross, not merely touch.
        let along: Int
        let across: Int
        let overlaps: Bool
        switch key {
        case .down, .up:
            along = key == .down ? frame.minY - origin.maxY : origin.minY - frame.maxY
            across = max(0, frame.minX - origin.maxX, origin.minX - frame.maxX)
            overlaps = frame.minX < origin.maxX && origin.minX < frame.maxX
        case .right, .left:
            along = key == .right ? frame.minX - origin.maxX : origin.minX - frame.maxX
            across = max(0, frame.minY - origin.maxY, origin.minY - frame.maxY)
            overlaps = frame.minY < origin.maxY && origin.minY < frame.maxY
        default:
            return nil
        }
        guard along >= 0 else { return nil }
        let vertical = key == .down || key == .up
        let dy: Int = (vertical ? along : across) * Self.rowAspect
        let dx: Int = vertical ? across : along
        outsideBeam = !overlaps
        distance = dy * dy + dx * dx
        self.order = order
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.outsideBeam != rhs.outsideBeam { return !lhs.outsideBeam }
        if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
        return lhs.order < rhs.order
    }
}
