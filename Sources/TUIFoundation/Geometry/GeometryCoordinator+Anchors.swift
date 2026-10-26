//  🖥️ TUI — A Terminal UI framework for Swift
//  GeometryCoordinator+Anchors.swift
//
//  Anchors: the views that make them, the preference layers that resolve
//  them against their base, and where they were last frame for a reader
//  anywhere else.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - Layer Scope

/// A preference layer being built (`overlayPreferenceValue`,
/// `backgroundPreferenceValue`): where the anchors its base made are in the
/// base's cells, and the space its readers are found in.
///
/// The base renders first, so its anchored views' markers are already in its
/// buffer, in the base's — and so the layer's — coordinates when the layer is
/// built: a reader in the layer resolves an anchor against where the anchored
/// view really is in the same frame, with no correction (design study A2, probe
/// L1). What remains is where the READER is in the layer, which its owner (the
/// layer) predicts from the carried origin and finds once it has composited,
/// as any named space's owner does.
final class AnchorLayerScope {
    /// The space a reader in the layer is found in: the base's frame.
    let space: CoordinateSpace

    /// Where each anchored view of the base is, in the base's cells, and its
    /// size.
    let sites: [HitTestRegion.HandlerID: (origin: CellPoint, size: CellSize)]

    /// The layer being built around this one, if any.
    let parent: AnchorLayerScope?

    init(
        space: CoordinateSpace, sites: [HitTestRegion.HandlerID: (origin: CellPoint, size: CellSize)],
        parent: AnchorLayerScope?
    ) {
        self.space = space
        self.sites = sites
        self.parent = parent
    }
}

/// The name of a preference layer's space: the layer's identity, so what was
/// found for a reader in it is kept from one frame to the next.
struct AnchorLayerSpaceName: Hashable {
    let layer: ViewIdentity
}

// MARK: - Sites

extension GeometryCoordinator {
    /// Registers the view whose marker is `id` as an anchored view of `size`
    /// for this walk.
    func registerAnchorSite(id: HitTestRegion.HandlerID, size: CellSize) {
        anchorSiteSizes[id] = size
    }

    /// Whether this walk has drawn an anchored view yet — what a preference
    /// layer asks before it looks for anchors in its base, so a layer over a
    /// base with none costs one check.
    var hasAnchorSites: Bool { !anchorSiteSizes.isEmpty }

    /// The scope of a preference layer about to be built over (or under)
    /// `base`, the buffer its base drew: the anchors made there, and where they
    /// are — or `nil` when the base made none, and a reader in the layer has
    /// nothing to resolve against it.
    ///
    /// - Parameters:
    ///   - base: What the layer's base drew.
    ///   - identity: The identity the layer is drawn at, which names its space.
    func anchorLayer(over base: FrameBuffer, layer identity: ViewIdentity) -> AnchorLayerScope? {
        guard !anchorSiteSizes.isEmpty else { return nil }
        var sites: [HitTestRegion.HandlerID: (origin: CellPoint, size: CellSize)] = [:]
        base.forEachGeometryMarker { id, x, y in
            guard let size = anchorSiteSizes[id] else { return }
            sites[id] = (CellPoint(x: x, y: y), size)
        }
        guard !sites.isEmpty else { return nil }
        return AnchorLayerScope(
            space: .named(AnchorLayerSpaceName(layer: identity)), sites: sites, parent: anchorScope)
    }

    /// Opens `scope` while its layer is built: readers made until
    /// ``leaveAnchorLayer(_:)`` resolve anchors against it.
    func enterAnchorLayer(_ scope: AnchorLayerScope) {
        anchorScope = scope
    }

    /// Closes `scope`, once its layer has rendered.
    func leaveAnchorLayer(_ scope: AnchorLayerScope) {
        anchorScope = scope.parent
    }

    /// Where the anchored view whose marker is `id` was in the global space
    /// when the last frame was drawn — for an anchor read outside the layer
    /// its base built.
    func globalAnchorSite(_ id: HitTestRegion.HandlerID) -> (origin: CellPoint, size: CellSize)? {
        globalAnchorSites[id]
    }

    /// Notes where this frame's anchored views ended up, in the frame as it
    /// will be shown.
    func endAnchorFrame(frame: FrameBuffer) {
        guard !anchorSiteSizes.isEmpty || !globalAnchorSites.isEmpty else { return }
        var found: [HitTestRegion.HandlerID: (origin: CellPoint, size: CellSize)] = [:]
        if !anchorSiteSizes.isEmpty {
            frame.forEachGeometryMarker { id, x, y in
                guard let size = anchorSiteSizes[id] else { return }
                found[id] = (CellPoint(x: x, y: y), size)
            }
        }
        globalAnchorSites = found
    }
}

// MARK: - Making One

extension RenderContext {
    /// The marker id an anchored view rendering here stamps, interned so an
    /// anchor made from it names the same view frame after frame — `nil` in a
    /// measure, and where no coordinator is wired.
    func anchorSiteID() -> HitTestRegion.HandlerID? {
        guard !isMeasuring, let dispatcher = environment.mouseEventDispatcher else { return nil }
        return dispatcher.geometryMarkerID(in: self)
    }
}
