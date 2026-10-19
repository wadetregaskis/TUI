//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassEffectGathering.swift
//
//  What a `GlassEffectContainer` learns from the glass inside it as its
//  content draws: where each glass is, and which of them join into one shape.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// One glass inside a ``GlassEffectContainer``, as it told the container while
/// it drew.
struct GatheredGlass {
    /// The glass view's identity — what the container remembers it by between
    /// passes.
    let identity: ViewIdentity
    /// Its glass.
    let glass: Glass
    /// Its shape, as drawn: one standing for another already resolved.
    let shape: any Shape
    /// The size it drew at.
    let size: CellSize
    /// The union it belongs to (`glassEffectUnion(id:namespace:)`), or `nil`.
    let union: GlassNamespacedID?
    /// Whether the pointer is over it, where it is interactive.
    let isHovered: Bool
    /// Whether it drew its own glass this pass, rather than leaving it to the
    /// container.
    let drewItself: Bool
}

/// The container's side of the glass inside it, for one pass.
///
/// A glass in a container draws itself as any glass does, and tells the
/// container it is there: it stamps a geometry marker (`HitTestRegion.geometryMarker(_:)`)
/// at its top-left and registers what it is. Once the content has drawn, the
/// container finds each marker in what it drew — where that glass ended up —
/// and joins the glass that touch, overlap, come closer than the container's
/// spacing, or share a union. A glass that was in a joined group last pass
/// draws no glass of its own this pass (``drawnByContainer``): the container
/// draws the group as one shape behind the content.
@MainActor
final class GlassEffectGathering {
    /// How close two glasses come before they are drawn as one: fewer than
    /// this many cells apart (and touching, whatever it is).
    let spacing: Int

    /// The glasses the container drew last pass, as members of a joined
    /// group: each draws no glass of its own this pass.
    let drawnByContainer: Set<ViewIdentity>

    /// What each glass inside said, in the order they drew.
    private(set) var effects: [GatheredGlass] = []

    /// The high bits of this container's markers: the geometry bit, a bit of
    /// glass's own, and the container's identity hashed, so a marker a nested
    /// container left in a displaced layer is never taken for one of these.
    private let markerBase: UInt64

    init(spacing: Int, drawnByContainer: Set<ViewIdentity>, container: ViewIdentity) {
        self.spacing = spacing
        self.drawnByContainer = drawnByContainer
        markerBase =
            HitTestRegion.HandlerID.geometryMarkerBit | Self.glassMarkerBit
            | (UInt64(truncatingIfNeeded: container.hashValue) & 0xFFFF_FFFF) << 20
    }

    /// The bit every glass container's marker carries.
    ///
    /// Clear of the dispatcher's mint, which counts up from the geometry bit
    /// and would have to mint 2⁶¹ markers to reach it, and of the picture
    /// markers (`HitTestRegion.HandlerID.pictureTopLeft`), whose bits 52–60
    /// are set where these are clear.
    private static let glassMarkerBit: UInt64 = 1 << 61

    /// Registers `glass` and returns the marker to stamp at its top-left.
    func gather(_ glass: GatheredGlass) -> HitTestRegion.HandlerID {
        effects.append(glass)
        return HitTestRegion.HandlerID(markerBase | UInt64(effects.count - 1))
    }

    /// Whether `id` is one of this container's markers.
    func owns(_ id: HitTestRegion.HandlerID) -> Bool {
        id.raw & ~UInt64(0xF_FFFF) == markerBase
    }

    /// The glass `id` marks.
    func effect(marked id: HitTestRegion.HandlerID) -> GatheredGlass? {
        guard owns(id) else { return nil }
        let index = Int(id.raw & 0xF_FFFF)
        return effects.indices.contains(index) ? effects[index] : nil
    }
}

// MARK: - Joining

/// A glass where its container found it.
struct PlacedGlass {
    let glass: GatheredGlass
    let frame: CellRect
}

/// Glasses drawn as one shape: its members, and the frame that bounds them.
struct GlassGroup {
    var members: [PlacedGlass]

    /// The smallest rectangle holding every member.
    var frame: CellRect {
        guard let first = members.first?.frame else { return CellRect(x: 0, y: 0, width: 0, height: 0) }
        var (minX, minY) = (first.x, first.y)
        var (maxX, maxY) = (first.x + first.width, first.y + first.height)
        for member in members.dropFirst() {
            minX = min(minX, member.frame.x)
            minY = min(minY, member.frame.y)
            maxX = max(maxX, member.frame.x + member.frame.width)
            maxY = max(maxY, member.frame.y + member.frame.height)
        }
        return CellRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Whether every member drew its own glass and none needs the container:
    /// a glass alone, drawn as glass outside a container is.
    var drewItself: Bool { members.count == 1 && members[0].glass.drewItself }

    /// Groups `placed`, each glass with every other it joins, transitively.
    ///
    /// Two glasses join when they are the same glass and either share a union
    /// (and a kind of shape, as SwiftUI's union asks) or lie fewer than
    /// `spacing` cells apart — always when they touch or overlap. Glass of two
    /// kinds stays apart: one shape has one surface. ``Glass/identity`` joins
    /// nothing.
    static func grouping(_ placed: [PlacedGlass], spacing: Int) -> [Self] {
        var parent = Array(placed.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index { index = parent[index] }
            return index
        }
        for first in placed.indices {
            for second in placed.indices where second > first && joins(placed[first], placed[second], spacing: spacing) {
                parent[root(second)] = root(first)
            }
        }
        var groups: [Int: Self] = [:]
        var order: [Int] = []
        for index in placed.indices {
            let key = root(index)
            if groups[key] == nil { order.append(key) }
            groups[key, default: Self(members: [])].members.append(placed[index])
        }
        return order.compactMap { groups[$0] }
    }

    /// Whether `first` and `second` are drawn as one.
    private static func joins(_ first: PlacedGlass, _ second: PlacedGlass, spacing: Int) -> Bool {
        let (a, b) = (first.glass, second.glass)
        guard a.glass == b.glass, !a.glass.isIdentity else { return false }
        if let union = a.union, union == b.union,
            ObjectIdentifier(type(of: a.shape)) == ObjectIdentifier(type(of: b.shape))
        {
            return true
        }
        return gap(first.frame, second.frame) < max(spacing, 1)
    }

    /// How many cells lie between two frames: across or down, whichever is
    /// further; 0 where they touch, and less where they overlap.
    private static func gap(_ a: CellRect, _ b: CellRect) -> Int {
        let across = max(b.x - (a.x + a.width), a.x - (b.x + b.width))
        let down = max(b.y - (a.y + a.height), a.y - (b.y + b.height))
        return max(across, down)
    }
}

// MARK: - The environment

private struct GlassEffectGatheringKey: EnvironmentKey {
    static let defaultValue: GlassEffectGathering? = nil
}

extension EnvironmentValues {
    /// The ``GlassEffectContainer`` the glass in this subtree tells where it
    /// is, or `nil` outside one — and inside a ``ScrollView`` within one: what
    /// the container draws is not clipped to the scroll view's viewport, so a
    /// glass in there is drawn by itself.
    var glassEffectGathering: GlassEffectGathering? {
        get { self[GlassEffectGatheringKey.self] }
        set { self[GlassEffectGatheringKey.self] = newValue }
    }
}
