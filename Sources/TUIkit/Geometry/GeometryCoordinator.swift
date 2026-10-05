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

    // MARK: - Scroll Visibility

    /// A view watching how much of it a scroll view shows.
    private struct VisibilityObserver {
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
    private struct Reported {
        let identity: ViewIdentity
        var isVisible: Bool
        let action: (Bool) -> Void
    }

    /// This walk's observers, by marker id.
    private var observers: [HitTestRegion.HandlerID: VisibilityObserver] = [:]

    /// The order the observers registered in this walk, which is the order
    /// they are reported in.
    private var observerOrder: [HitTestRegion.HandlerID] = []

    /// How many of ``observers`` no scroll view has measured yet — what a
    /// scroll view asks before it scans what it drew.
    private var unmeasuredObservers = 0

    /// What each observer was last told.
    private var reported: [HitTestRegion.HandlerID: Reported] = [:]

    /// Whether a scroll view drawing now has an observer to measure.
    var hasUnmeasuredVisibilityObservers: Bool { unmeasuredObservers > 0 }

    /// Clears the walk's registrations — see ``MouseEventDispatcher/beginRenderPass()``.
    func beginWalk() {
        guard !observers.isEmpty else { return }
        observers.removeAll(keepingCapacity: true)
        observerOrder.removeAll(keepingCapacity: true)
        unmeasuredObservers = 0
    }

    /// Registers the view whose marker is `id` as watching its visibility.
    ///
    /// Registered again by a view drawn again in the same walk — a subtree a
    /// container renders twice — which replaces the first registration and
    /// whatever was measured for it: the second drawing is the one shown.
    func registerVisibilityObserver(
        id: HitTestRegion.HandlerID, identity: ViewIdentity, size: CellSize, threshold: Double,
        action: @escaping (Bool) -> Void
    ) {
        if let existing = observers[id] {
            if existing.fraction != nil { unmeasuredObservers += 1 }
        } else {
            observerOrder.append(id)
            unmeasuredObservers += 1
        }
        observers[id] = VisibilityObserver(
            identity: identity, size: size, threshold: threshold, action: action)
    }

    /// Measures every observer `drawn` carries that no scroll view nearer to it
    /// has measured, against a viewport of `viewport` in `drawn`'s coordinates.
    ///
    /// Called by a scroll view on what it drew, once its offset is final:
    /// inner scroll views draw first, so the nearest one measures an observer
    /// and every one further out finds it measured.
    func measureVisibility(in drawn: FrameBuffer, viewport: CellRect) {
        drawn.forEachGeometryMarker { id, x, y in
            guard var observer = observers[id], observer.fraction == nil else { return }
            observer.fraction = Self.fraction(
                of: CellRect(x: x, y: y, width: observer.size.width, height: observer.size.height),
                shownIn: viewport)
            observers[id] = observer
            unmeasuredObservers -= 1
        }
    }

    /// How much of `rect` `viewport` shows, from 0 to 1. A view with no area
    /// is shown whole or not at all, by whether its origin is inside.
    static func fraction(of rect: CellRect, shownIn viewport: CellRect) -> Double {
        let area = rect.width * rect.height
        guard area > 0 else {
            let inside =
                rect.x >= viewport.x && rect.x < viewport.maxX && rect.y >= viewport.y
                && rect.y < viewport.maxY
            return inside ? 1 : 0
        }
        let width = max(0, min(rect.maxX, viewport.maxX) - max(rect.x, viewport.x))
        let height = max(0, min(rect.maxY, viewport.maxY) - max(rect.y, viewport.y))
        return Double(width * height) / Double(area)
    }

    // MARK: - Ending the Frame

    /// Reports what this frame changed, once the frame is drawn.
    ///
    /// An observer reports when it first appears — shown or not — and then
    /// each time its fraction crosses its threshold (a fraction AT the
    /// threshold counts as shown, as SwiftUI's does). One no scroll view
    /// measured is reported shown: SwiftUI reports a view in no scroll view
    /// visible wherever it is (measured, macOS 15).
    ///
    /// An observer that drew last frame and not this one has either left the
    /// window of a lazy container — still in the tree, its state kept, and
    /// certainly not on screen — or left the tree. The first is reported hidden
    /// if it was shown; the second is not reported at all, as SwiftUI reports
    /// nothing for a removed view (measured).
    ///
    /// A registration whose marker no scroll view measured and the finished
    /// frame does not carry was not drawn — its buffer was thrown away — and
    /// counts as no registration at all.
    ///
    /// - Parameters:
    ///   - frame: The frame as it will be shown, every layer composited.
    ///   - isRetained: Whether an identity that drew nothing this frame is
    ///     still in the tree (`StateStorage.retainedSubtrees()`).
    func endFrame(frame: FrameBuffer, isRetained: (ViewIdentity) -> Bool) {
        guard !observers.isEmpty || !reported.isEmpty else { return }
        if unmeasuredObservers > 0 {
            frame.forEachGeometryMarker { id, _, _ in observers[id]?.reachedFrame = true }
        }
        var reports: [(action: (Bool) -> Void, isVisible: Bool)] = []
        var drawn: Set<HitTestRegion.HandlerID> = []
        for id in observerOrder {
            guard let observer = observers[id], observer.fraction != nil || observer.reachedFrame else {
                continue
            }
            drawn.insert(id)
            let isVisible = observer.fraction.map { $0 >= observer.threshold } ?? true
            let previous = reported[id]?.isVisible
            reported[id] = Reported(
                identity: observer.identity, isVisible: isVisible, action: observer.action)
            if previous != isVisible { reports.append((observer.action, isVisible)) }
        }
        if reported.count > drawn.count {
            var removed: [HitTestRegion.HandlerID] = []
            for (id, last) in reported where !drawn.contains(id) {
                guard isRetained(last.identity) else {
                    removed.append(id)
                    continue
                }
                if last.isVisible {
                    reported[id]?.isVisible = false
                    reports.append((last.action, false))
                }
            }
            for id in removed { reported.removeValue(forKey: id) }
        }
        // After the books are settled: an action may write state, and nothing
        // here should be half-updated when it does.
        for report in reports { report.action(report.isVisible) }
    }
}

extension GeometryCoordinator {
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

    /// Measures the scroll visibility observers in `drawn` against `viewport`,
    /// for a scroll container whose offset is final — a `ScrollView`, a `List`.
    ///
    /// One environment read and a count when no observer is waiting, which is
    /// every frame of an app that has none.
    func measureScrollVisibility(in drawn: FrameBuffer, viewport: CellRect) {
        guard !isMeasuring, let geometry = geometryCoordinator,
            geometry.hasUnmeasuredVisibilityObservers
        else { return }
        geometry.measureVisibility(in: drawn, viewport: viewport)
    }
}
