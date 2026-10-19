//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassEffectContainer.swift
//
//  A view whose glass is drawn together: glass shapes that come near one
//  another, or share a union, are drawn as one.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// A view that combines multiple glass shapes into a single shape — mirrors
/// SwiftUI's `GlassEffectContainer`.
///
/// You use a glass effect container with the ``View/glassEffect(_:in:)``
/// modifier. Each view inside with a glass effect contributes a shape; where
/// shapes come near one another they are drawn as one — a single surface and a
/// single rim round all of them, the shape of the first:
///
/// ```swift
/// GlassEffectContainer(spacing: 2) {
///     HStack(spacing: 1) {
///         Text("Bold").padding(.horizontal).glassEffect()
///         Text("Italic").padding(.horizontal).glassEffect()
///     }
/// }
/// ```
///
/// draws `(Bold   Italic)` — one rim round both — where without the container
/// it draws `(Bold) (Italic)`.
///
/// SwiftUI's shapes start to blend as they approach, more and sooner the
/// larger the spacing. A cell is joined or not, so here two glasses are drawn
/// as one when they touch or overlap, or come fewer than `spacing` cells
/// apart; at the spacing itself — the gap an `HStack` of the same spacing
/// leaves — they stay apart, as SwiftUI's at rest do. Glasses that share a
/// ``View/glassEffectUnion(id:namespace:)`` are drawn as one wherever they
/// are. Only glass of one kind joins: one shape has one surface. Glass
/// arriving under an animation fades in by itself and joins once it has
/// arrived (``GlassEffectTransition``).
///
/// The joined shape is the smallest rectangle round its members, in the first
/// member's shape and glass, drawn behind the container's content. A glass
/// inside a ``ScrollView`` in the container is drawn by itself, since what the
/// container draws is not clipped to the scroll view (decisions B-GLASS-5).
public struct GlassEffectContainer<Content: View>: View {
    /// How close glass shapes come before they are drawn as one, in cells.
    let spacing: Int?

    /// The views whose glass is drawn together.
    let content: Content

    /// Creates a glass effect container with the provided spacing, extracting
    /// glass shapes from the provided content.
    ///
    /// - Parameters:
    ///   - spacing: How close, in cells, two glass shapes come before they are
    ///     drawn as one. `nil`: only shapes that touch or overlap.
    ///   - content: The views whose glass is drawn together.
    public init(spacing: Int? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        _GlassEffectContainerCore(spacing: spacing ?? 0, content: content)
    }
}

/// `StateStorage` property indices for ``_GlassEffectContainerCore``'s record,
/// kept at a child identity of its own (``GlassContainerRecord``), so marking
/// it live keeps no other view's `@State` (decisions A40's finding).
private enum GlassContainerStateIndex {
    /// Who the container found joined (``GlassJoins``).
    static let joins = 0
}

/// The identity a glass container keeps its record at: a child of its own.
private enum GlassContainerRecord {}

/// Who a glass container found joined, the glass of whom it draws: kept from
/// one pass to the next, and from one drawing of its content to the next
/// within a pass.
private final class GlassJoins {
    var joined: Set<ViewIdentity> = []
}

/// ``GlassEffectContainer``'s drawing: its content, told it is in a container,
/// and the joined glass behind it.
///
/// The content draws as it would anywhere, each glass in it drawing itself —
/// but telling the container it is there (``GlassEffectGathering``). The
/// container then finds where each glass ended up, joins them
/// (``GlassGroup/grouping(_:spacing:)``), and draws each joined group as one
/// glass behind the content. A glass leaves its glass to the container when it
/// was joined last pass: the container keeps who was. Where the content draws
/// its glass joined otherwise than it finds it — the pass a group forms, a
/// glass joins one or leaves — the container puts the walk back and draws the
/// content again, now knowing who is joined (``RenderWalkCheckpoint``, as a
/// coordinate space draws its readers again). Glass changes no layout, so the
/// second drawing finds what the first did, and every pass shows the glass
/// joined as it stands.
struct _GlassEffectContainerCore<Content: View>: View {
    let spacing: Int
    let content: Content

    var body: Never { fatalError("_GlassEffectContainerCore renders via Renderable") }
}

extension _GlassEffectContainerCore: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !context.isMeasuring, let record = record(context) else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        // Noted before the content draws, so a walk that drew the glass joined
        // otherwise than it stands can be put back and drawn again.
        let checkpoint = RenderWalkCheckpoint(context: context)
        var walk = drawContent(leavingToContainer: record.joined, context: context)
        if walk.joined != record.joined {
            record.joined = walk.joined
            checkpoint.rollBack(context: context)
            walk = drawContent(leavingToContainer: walk.joined, context: context)
            // Kept whatever the second drawing found: glass changes no layout,
            // so it finds what the first did, and if not, the next pass draws
            // from this.
            record.joined = walk.joined
        }
        var base = walk.base
        let drawn = walk.groups.flatMap(\.drawnByContainer)
        guard !drawn.isEmpty, base.width > 0, base.height > 0 else { return base }
        let layer = Self.layer(drawn, columns: base.width, rows: base.height, context: context)
        base.opacityRegions += base.claimsShowingGlyphs(of: layer)
        return compositeDrawnLayer(layer.buffer(), at: (0, 0), under: base, context: context, modifierType: Self.self)
    }

    /// One drawing of the content: what it drew, the glass in it grouped, and
    /// who of it is joined.
    private struct ContentWalk {
        var base: FrameBuffer
        var groups: [GlassGroup]
        var joined: Set<ViewIdentity>
    }

    /// The content drawn with the glass of `joined` left to the container, and
    /// where its glass ended up.
    private func drawContent(leavingToContainer joined: Set<ViewIdentity>, context: RenderContext) -> ContentWalk {
        let gathering = GlassEffectGathering(spacing: spacing, drawnByContainer: joined, container: context.identity)
        var contentContext = context
        contentContext.environment.glassEffectGathering = gathering
        var base = TUIkitView.renderToBuffer(content, context: contentContext)
        // Where each glass ended up; the markers go, being the container's own.
        var placed: [PlacedGlass] = []
        base.forEachGeometryMarker { id, x, y in
            guard let glass = gathering.effect(marked: id) else { return }
            placed.append(
                PlacedGlass(glass: glass, frame: CellRect(x: x, y: y, width: glass.size.width, height: glass.size.height)))
        }
        base.hitTestRegions.removeAll { gathering.owns($0.handlerID) }
        let groups = GlassGroup.grouping(placed, spacing: spacing)
        let found = Set(groups.filter { $0.members.count > 1 }.flatMap { $0.members.map(\.glass.identity) })
        return ContentWalk(base: base, groups: groups, joined: found)
    }

    /// Who the container found joined, kept at its own child identity and
    /// marked live — `nil` with no state storage, where the content draws as
    /// it would outside a container.
    ///
    /// A ``GlassJoins`` the box holds rather than the value itself: who is
    /// joined is the container's own bookkeeping, settled within the pass it
    /// changes, so writing it asks for no other pass, as a box's value would.
    private func record(_ context: RenderContext) -> GlassJoins? {
        guard let storage = context.stateStorage else { return nil }
        let identity = context.withChildIdentity(erasedType: GlassContainerRecord.self, index: 0).identity
        storage.markActive(identity)
        return storage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: GlassContainerStateIndex.joins),
            default: GlassJoins()
        ).value
    }

    /// `groups` drawn into one layer `columns` × `rows`, each its first
    /// member's glass in its first member's shape, filling the frame round its
    /// members, its rim lifted where the pointer is over any of them — all of
    /// it there: only glass that has arrived joins.
    @MainActor
    private static func layer(_ groups: [GlassGroup], columns: Int, rows: Int, context: RenderContext) -> ShapeCells {
        var layer = ShapeCells(width: columns, height: rows)
        for group in groups {
            guard let first = group.members.first?.glass else { continue }
            let frame = group.frame
            guard frame.width > 0, frame.height > 0 else { continue }
            let cells = GlassCells.drawing(
                first.glass, in: first.shape, columns: frame.width, rows: frame.height,
                hovered: group.members.contains { $0.glass.isHovered }, context: context, owner: nil)
            layer.laying(cells, at: (frame.x, frame.y))
        }
        return layer
    }
}

extension _GlassEffectContainerCore: Layoutable {
    /// The content's size: a container changes nothing about layout.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
