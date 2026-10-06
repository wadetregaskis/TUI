//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GeometryCoordinator+Owners.swift
//
//  The owners of coordinate spaces as the walk passes through them: where
//  each one's own origin was carried to, so a reader below can be told where
//  it is relative to it before anything is drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Owner Scope

/// A view that owns coordinate spaces, while its subtree is being drawn: the
/// spaces, and where its own top-left was carried to
/// (`RenderContext.geometryOriginX`).
///
/// A reader's prediction for a space is its own carried origin less the
/// owner's (``GeometryAsk``), so the two must be in one frame of reference —
/// which they are when the reader is in the owner's subtree, the only place
/// the owner is on the chain. The scene root has no scope: past every scope,
/// `.global` and each name nothing declared are measured from the frame of
/// reference's origin — which is the root's only when the root started it, so
/// a reader whose origin an owner below the root started
/// (``startsReference``) has no prediction for those spaces. (Measured from
/// the owner instead, the prediction would be off by the owner's place on the
/// screen; the residual would carry that, until the frame the root started
/// carrying an origin itself, when it would be wrong once.)
///
/// A linked chain, not a stack, so an ask can keep the chain as it stood when
/// its view rendered (a proxy may be asked again later in the walk, after
/// other owners have come and gone).
final class GeometryOwnerScope {
    /// The spaces this owner answers for.
    let spaces: [CoordinateSpace]

    /// Where the owner's top-left was carried to.
    let origin: CellPoint

    /// The space's size as far as is known before it is drawn — what
    /// `bounds(of:)` is told the first time it asks: the owner's proposal for
    /// a named space, the viewport for a scroll view.
    let size: CellSize?

    /// For a scroll view, the axis a scroll transition naming none follows —
    /// see ``GeometryObservation/scrollAxis``.
    let scrollAxis: Axis?

    /// Whether this owner started the carried origin its content measures
    /// from, nothing above it carrying one — so no space owned further out
    /// can be measured in the same frame of reference.
    let startsReference: Bool

    /// The owner around this one, if any.
    let parent: GeometryOwnerScope?

    init(
        spaces: [CoordinateSpace], origin: CellPoint, size: CellSize?, scrollAxis: Axis?, startsReference: Bool,
        parent: GeometryOwnerScope?
    ) {
        self.spaces = spaces
        self.origin = origin
        self.size = size
        self.scrollAxis = scrollAxis
        self.startsReference = startsReference
        self.parent = parent
    }
}

extension GeometryCoordinator {
    /// Opens an owner of `spaces` whose content renders in `contentContext`
    /// — `context` carrying an origin (`RenderContext.carryingGeometryOrigin()`)
    /// — for readers made until ``leaveOwner(_:)`` to be measured against.
    ///
    /// - Parameters:
    ///   - spaces: The spaces the owner answers for.
    ///   - context: The owner's own context, which says whether anything above
    ///     carried an origin.
    ///   - contentContext: The context its content renders in, whose carried
    ///     origin is the owner's own.
    ///   - size: The space's size as far as is known before it is drawn.
    ///   - scrollAxis: For a scroll view, its axis (``GeometryObservation/scrollAxis``).
    /// - Returns: The scope, to close.
    func enterOwner(
        of spaces: [CoordinateSpace], from context: RenderContext, in contentContext: RenderContext,
        size: CellSize?, scrollAxis: Axis? = nil
    ) -> GeometryOwnerScope {
        let origin = contentContext.geometryOrigin ?? (0, 0)
        let scope = GeometryOwnerScope(
            spaces: spaces, origin: CellPoint(x: origin.x, y: origin.y), size: size, scrollAxis: scrollAxis,
            startsReference: !context.carriesGeometryOrigin, parent: ownerScope)
        ownerScope = scope
        return scope
    }

    /// Reopens `scope` — for an owner drawing its subtree a second time.
    func reenterOwner(_ scope: GeometryOwnerScope) {
        ownerScope = scope
    }

    /// Closes `scope`, once its owner's content has rendered.
    func leaveOwner(_ scope: GeometryOwnerScope) {
        ownerScope = scope.parent
    }

    /// Whether a reader — a view whose content is built from where it is
    /// (``GeometryAsk/Role/reader``) — is among the views asking, so the
    /// scene root starts a carried origin to predict for it
    /// (``RenderContext/carryingGeometryRootOrigin()``).
    ///
    /// Readers only: an `onGeometryChange` reporter is asked again once the
    /// frame is done, and a pointer converts at event time, and neither is
    /// told a prediction (`GeometryAsk.origin` is `nil` for them). Counting
    /// them made one such view anywhere carry an origin through the whole
    /// tree on every frame, and every container below compute the
    /// placements that feed it, for nothing.
    var hasReaders: Bool { keepsReaders }

    /// Whether a `coordinateSpace(_:)` declaration with nothing above it
    /// carrying an origin should start one for its content: while there are
    /// readers to predict for, and while no view has asked anything yet — so
    /// a reader's first frame under a declaration is predicted, as it is
    /// drawn before anything is known — but not once the only views asking
    /// are pointers and reporters, which never read a prediction.
    var declarationsCarryOrigin: Bool { keepsReaders || kept.isEmpty }
}

// MARK: - The Root

extension RenderContext {
    /// This context as the scene root hands it to the scene: carrying a
    /// geometry origin at `(0, 0)` — the global space's — when the frame's
    /// coordinator has readers to predict for, and unchanged otherwise, so a
    /// tree that asks nothing pays nothing (`RenderContext.geometryOriginX`).
    package func carryingGeometryRootOrigin() -> Self {
        guard let geometry = geometryCoordinator, geometry.hasReaders else { return self }
        return carryingGeometryOrigin()
    }
}
