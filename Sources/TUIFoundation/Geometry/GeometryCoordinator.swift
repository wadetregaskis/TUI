//  🖥️ TUI — A Terminal UI framework for Swift
//  GeometryCoordinator.swift
//
//  Who answers "where is this view?" for the views that ask: the requests a
//  walk registers, what their owners found, and what is reported when the
//  frame ends. Design study A2 (`Documentation/Historical/Geometry design study,
//  A2 and A7 (2026-10-04).md`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - Geometry Coordinator

/// The bookkeeping behind the views that need to know where a view ended up:
/// scroll visibility (`onScrollVisibilityChange`), the coordinate spaces
/// (`GeometryProxy.frame(in:)`, `bounds(of:)`, a gesture located in a named
/// space), and the anchors that build on the same markers.
///
/// TUI renders bottom-up — a container renders a child, then places it — so
/// no view knows where it sits while it is drawn. Each such view stamps a
/// geometry marker (`HitTestRegion.geometryMarker(_:)`) into its buffer and
/// registers here what it wants to know, under the marker's id. The view that
/// owns the answer reads the markers back out of what it drew — a scroll view
/// its content, against its viewport; a `coordinateSpace(_:)` view its
/// subtree; the scene root the whole frame — and records what it found here.
///
/// A view whose content is BUILT from an answer (a `GeometryReader`) is
/// answered, while it renders, with what its owner found last frame; the owner
/// checks that against where it finds the view now, and draws its subtree
/// once more when they differ (G1 of the design study: the correction). What
/// is REPORTED — a callback fired — waits for the frame to end, so a view a
/// frame draws more than once reports once, and reports what was finally
/// drawn.
///
/// One per mouse dispatcher, which already interns the marker ids and is
/// wired wherever a frame is rendered (`MouseEventDispatcher.geometry`).
/// Per-walk state is cleared with the dispatcher's
/// (`MouseEventDispatcher.beginRenderPass()`); what is kept across frames is
/// kept here, and pruned with the views it belongs to.
///
/// Unsynchronised, on the dispatcher's terms: it is only touched on the
/// render path and at the end of a frame, both on the main actor.
package final class GeometryCoordinator {
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

    // MARK: - Coordinate Spaces (state; GeometryCoordinator+Spaces.swift)

    /// What owners found for one view, kept across frames: what the view is
    /// told while it renders next.
    struct KeptObservations {
        let identity: ViewIdentity
        /// Whether the view asked as a reader (``GeometryAsk/Role/reader``)
        /// when it last asked — the one role a prediction is made for.
        var isReader: Bool
        var bySpace: [CoordinateSpace: GeometryObservation] = [:]
        /// What the view was predicted to be at in each space when it was
        /// found there — absent where no prediction was made. The difference
        /// is the residual the next frame's prediction is corrected by
        /// (``GeometryAsk``).
        var predicted: [CoordinateSpace: CellPoint] = [:]
        /// Whether the view asked this walk — a view that did not is pruned
        /// unless a lazy container still holds it (``endSpacesFrame(isRetained:)``).
        var askedThisWalk = true
    }

    /// This walk's asks, by marker id.
    var asks: [HitTestRegion.HandlerID: GeometryAsk] = [:]

    /// The order they registered in, which is the order reports are made in.
    var askOrder: [HitTestRegion.HandlerID] = []

    /// How many (ask, space) pairs no owner has answered yet, by space — what
    /// an owner asks before it scans what it drew.
    var unanswered: [CoordinateSpace: Int] = [:]

    /// The total of ``unanswered``: what the scene root asks.
    var unansweredTotal = 0

    /// What owners found, across frames, by marker id.
    var kept: [HitTestRegion.HandlerID: KeptObservations] = [:]

    /// Whether a reader is among the views ``kept`` holds — set when one
    /// registers, and settled at the end of each frame from what is kept
    /// (``endSpacesFrame(isRetained:)``). What decides whether a carried
    /// origin is worth starting (`hasReaders`).
    var keepsReaders = false

    /// Spaces a view asked about after its render — from an action, at the end
    /// of a frame — which it is found in from its next render on.
    var lateAsks: [HitTestRegion.HandlerID: [CoordinateSpace]] = [:]

    /// What each reporter (`onGeometryChange` asking another space) does once
    /// the frame is done, by marker id.
    var reporters: [HitTestRegion.HandlerID: (GeometryProxy) -> Void] = [:]

    /// How often owners have drawn their subtrees again — see
    /// ``GeometryCorrections``.
    private(set) var corrections = GeometryCorrections()

    // MARK: - Anchors (state; GeometryCoordinator+Anchors.swift)

    /// The anchored views this walk drew, by marker id, and their sizes.
    var anchorSiteSizes: [HitTestRegion.HandlerID: CellSize] = [:]

    /// The innermost preference layer being built, while it is.
    var anchorScope: AnchorLayerScope?

    // MARK: - Owners (state; GeometryCoordinator+Owners.swift)

    /// The innermost owner of a space whose subtree is being drawn, while it
    /// is: what a reader's prediction measures its carried origin against.
    var ownerScope: GeometryOwnerScope?

    /// Where each anchored view was in the global space when the last frame
    /// was drawn — what an anchor read outside its layer resolves against.
    var globalAnchorSites: [HitTestRegion.HandlerID: (origin: CellPoint, size: CellSize)] = [:]

    // MARK: - Matched Geometry (MatchedGeometryRegistry.swift)

    /// The groups `matchedGeometryEffect` joins views into, which the scene
    /// root checks once it has found them (``resolveRemaining(in:size:)``).
    package let matchedGeometry = MatchedGeometryRegistry()

    /// Clears the walk's registrations — see ``MouseEventDispatcher/beginRenderPass()``.
    func beginWalk() {
        if !observers.isEmpty {
            observers.removeAll(keepingCapacity: true)
            observerOrder.removeAll(keepingCapacity: true)
            unmeasuredObservers = 0
        }
        if !asks.isEmpty {
            asks.removeAll(keepingCapacity: true)
            askOrder.removeAll(keepingCapacity: true)
            unanswered.removeAll(keepingCapacity: true)
            unansweredTotal = 0
            reporters.removeAll(keepingCapacity: true)
        }
        if !anchorSiteSizes.isEmpty { anchorSiteSizes.removeAll(keepingCapacity: true) }
        anchorScope = nil
        ownerScope = nil
        matchedGeometry.beginWalk()
    }

    /// Counts a correction an owner of `kind` made.
    package func noteCorrection(_ kind: GeometryOwnerKind) {
        corrections.note(kind)
    }

    /// Counts a reader found still wrong after its owner's correction — which
    /// one correction cannot leave if readers are greedy (the design study's
    /// one-pass convergence), so a non-zero count is a bug to look for.
    package func noteResidual() {
        corrections.residual += 1
    }

    // MARK: - Ending the Frame

    /// Settles what the frame owes its geometry views, once it is drawn: the
    /// reporters' callbacks, the visibility reports, and the pruning of what is
    /// kept for views that have gone.
    ///
    /// - Parameters:
    ///   - frame: The frame as it will be shown, every layer composited.
    ///   - isRetained: Whether an identity that drew nothing this frame is
    ///     still in the tree (`StateStorage.retainedSubtrees()`).
    func endFrame(frame: FrameBuffer, isRetained: (ViewIdentity) -> Bool) {
        endAnchorFrame(frame: frame)
        endSpacesFrame(isRetained: isRetained)
        endVisibilityFrame(frame: frame, isRetained: isRetained)
        matchedGeometry.endFrame()
    }

    /// ``endFrame(frame:isRetained:)``, asking `storage` which identities are
    /// still in the tree — and only if some view vanished, since building the
    /// index is the cost.
    package func endFrame(frame: FrameBuffer, retainedBy storage: StateStorage?) {
        var retained: RetainedSubtreeIndex?
        endFrame(frame: frame) { identity in
            guard let storage else { return false }
            if retained == nil { retained = storage.retainedSubtrees() }
            return retained?.retains(identity) ?? false
        }
    }
}

// MARK: - Corrections

/// Which kind of view owned a coordinate space a reader asked about.
package enum GeometryOwnerKind {
    /// A ``View/coordinateSpace(_:)`` view.
    case named
    /// A scroll view, for `.scrollView` and `.scrollView(axis:)`.
    case scrollView
    /// The scene root, for `.global` and every name nothing declared.
    case root
    /// An `overlayPreferenceValue` / `backgroundPreferenceValue` layer,
    /// resolving anchors relative to a reader inside it.
    case layer
}

/// How many times each kind of owner drew its subtree again because a reader
/// in it had drawn from an answer that turned out wrong — the acceptance
/// metric of the design study's prediction rungs (the Stress `geometry`
/// scenario prints it per frame).
package struct GeometryCorrections: Equatable, Sendable {
    package var named = 0
    package var scrollView = 0
    package var root = 0
    package var layer = 0
    /// Readers still wrong after a correction: should stay zero.
    package var residual = 0

    package init() {}

    mutating func note(_ kind: GeometryOwnerKind) {
        switch kind {
        case .named: named += 1
        case .scrollView: scrollView += 1
        case .root: root += 1
        case .layer: layer += 1
        }
    }

    /// Every correction, whatever owned it.
    package var total: Int { named + scrollView + root + layer }
}

// MARK: - Reaching It

extension RenderContext {
    /// The geometry coordinator of the frame being rendered, or `nil` where
    /// there is no mouse dispatcher to own one — see ``GeometryCoordinator``.
    package var geometryCoordinator: GeometryCoordinator? {
        environment.mouseEventDispatcher?.geometry
    }
}
