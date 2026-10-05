//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GeometryCoordinator.swift
//
//  Who answers "where is this view?" for the views that ask: the requests a
//  walk registers, what their owners found, and what is reported when the
//  frame ends. Design study A2 (`Documentation/SwiftUI-API-completion-design-
//  A2-geometry.md`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Geometry Coordinator

/// The bookkeeping behind the views that need to know where a view ended up:
/// scroll visibility (`onScrollVisibilityChange`), and the coordinate spaces
/// and anchors that build on the same markers.
///
/// TUIkit renders bottom-up — a container renders a child, then places it — so
/// no view knows where it sits while it is drawn. Each such view stamps a
/// geometry marker (`HitTestRegion.geometryMarker(_:)`) into its buffer and
/// registers here what it wants to know, under the marker's id. The view that
/// owns the answer reads the markers back out of what it drew — a scroll view
/// its content, against its viewport — and records what it found here. What
/// is REPORTED (a callback fired) waits for the frame to end, so a view a
/// frame draws more than once reports once, and reports what was finally
/// drawn.
///
/// One per mouse dispatcher, which already interns the marker ids and is
/// wired wherever a frame is rendered (`MouseEventDispatcher.geometry`).
/// Per-walk state is cleared with the dispatcher's
/// (`MouseEventDispatcher.beginRenderPass()`); what is reported across frames
/// is kept here.
///
/// Unsynchronised, on the dispatcher's terms: it is only touched on the
/// render path and at the end of a frame, both on the main actor.
final class GeometryCoordinator: @unchecked Sendable {
    init() {}

    // MARK: - Scroll Visibility (state; GeometryCoordinator+Visibility.swift)

    /// A view watching how much of it a scroll view shows.
    struct VisibilityObserver {
        let identity: ViewIdentity
        let size: CellSize
        let threshold: Double
        let action: (Bool) -> Void
        /// The fraction of it the nearest scroll view showed — `nil` until a
        /// scroll view measured it, and for good when none encloses it.
        var fraction: Double?
        /// Whether its marker reached the finished frame — what says a view no
        /// scroll view measured was drawn at all, rather than drawn into a
        /// buffer something threw away (a container that renders a subtree
        /// once to size it and again to show it).
        var reachedFrame = false
    }

    /// What an observer was last told, kept across frames: a report is only
    /// made when this changes.
    struct Reported {
        let identity: ViewIdentity
        var isVisible: Bool
        let action: (Bool) -> Void
    }

    /// This walk's observers, by marker id.
    var observers: [HitTestRegion.HandlerID: VisibilityObserver] = [:]

    /// The order the observers registered in this walk, which is the order
    /// they are reported in.
    var observerOrder: [HitTestRegion.HandlerID] = []

    /// How many of ``observers`` no scroll view has measured yet — what a
    /// scroll view asks before it scans what it drew.
    var unmeasuredObservers = 0

    /// What each observer was last told.
    var reported: [HitTestRegion.HandlerID: Reported] = [:]

    /// Clears the walk's registrations — see ``MouseEventDispatcher/beginRenderPass()``.
    func beginWalk() {
        guard !observers.isEmpty else { return }
        observers.removeAll(keepingCapacity: true)
        observerOrder.removeAll(keepingCapacity: true)
        unmeasuredObservers = 0
    }

    // MARK: - Ending the Frame

    /// Settles what the frame owes its geometry views, once it is drawn.
    ///
    /// - Parameters:
    ///   - frame: The frame as it will be shown, every layer composited.
    ///   - isRetained: Whether an identity that drew nothing this frame is
    ///     still in the tree (`StateStorage.retainedSubtrees()`).
    func endFrame(frame: FrameBuffer, isRetained: (ViewIdentity) -> Bool) {
        endVisibilityFrame(frame: frame, isRetained: isRetained)
    }

    /// ``endFrame(frame:isRetained:)``, asking `storage` which identities are
    /// still in the tree — and only if some observer vanished, since building
    /// the index is the cost.
    func endFrame(frame: FrameBuffer, retainedBy storage: StateStorage?) {
        var retained: RetainedSubtreeIndex?
        endFrame(frame: frame) { identity in
            guard let storage else { return false }
            if retained == nil { retained = storage.retainedSubtrees() }
            return retained?.retains(identity) ?? false
        }
    }
}

// MARK: - Reaching It

extension RenderContext {
    /// The geometry coordinator of the frame being rendered, or `nil` where
    /// there is no mouse dispatcher to own one — see ``GeometryCoordinator``.
    var geometryCoordinator: GeometryCoordinator? {
        environment.mouseEventDispatcher?.geometry
    }
}
