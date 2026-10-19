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
/// member's shape and glass. Each member draws its own part of it, where its
/// own glass would be, so what is applied to a member — a background, a
/// colour effect — acts on its part as on its glass alone; what lies between
/// the members is drawn over a background inside the container, and under
/// anything drawn there. A glass
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
    /// Who the container found joined, and how (``GlassJoins``).
    static let joins = 0
}

/// The identity a glass container keeps its record at: a child of its own.
private enum GlassContainerRecord {}

/// The part of a joined shape each glass a container found joined draws:
/// kept from one pass to the next, and from one drawing of its content to the
/// next within a pass.
private final class GlassJoins {
    var pieces: [ViewIdentity: GlassPiece] = [:]
}

/// ``GlassEffectContainer``'s drawing: its content, told it is in a container,
/// and what lies between the glass it joins.
///
/// The content draws as it would anywhere, each glass in it drawing itself —
/// but telling the container it is there (``GlassEffectGathering``). The
/// container then finds where each glass ended up and joins them
/// (``GlassGroup/grouping(_:spacing:)``). A glass it found joined draws its
/// part of the joined shape (``GlassPiece``) where its own glass would be, so
/// whatever lies between it and the container acts on that part as on any
/// glass; the container draws only the cells of the shape that no glass
/// covers — what lies between them — as in front of what is behind them:
/// over a background inside it, under anything drawn there.
///
/// A glass draws the part the container found last pass. Where the content
/// draws its glass otherwise than the container finds it — the pass a group
/// forms, a glass joins one, leaves, moves or changes size — the container
/// puts the walk back and draws the content again, now knowing each part
/// (``RenderWalkCheckpoint``, as a coordinate space draws its readers again).
/// Glass changes no layout, so the second drawing finds what the first did,
/// and every pass shows the glass joined as it stands.
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
        var walk = drawContent(drawing: record.pieces, context: context)
        if !walk.drewAsFound {
            record.pieces = walk.found
            checkpoint.rollBack(context: context)
            walk = drawContent(drawing: walk.found, context: context)
            // Kept whatever the second drawing found: glass changes no layout,
            // so it finds what the first did, and if not, the next pass draws
            // from this.
            record.pieces = walk.found
        }
        let base = walk.base
        let joined = walk.groups.filter { $0.members.count > 1 && $0.drewItsPieces(walk.found) }
        guard !joined.isEmpty, base.width > 0, base.height > 0 else { return base }
        let layer = Self.between(joined, placed: walk.placed, columns: base.width, rows: base.height, context: context)
        // What lies between the members is glass, in front of what is behind
        // them as each member's part is: over a background inside the
        // container, and under anything drawn there.
        let (over, under) = Self.parted(layer, by: base)
        var composite = base
        if let under {
            composite = compositeDrawnLayer(
                under.buffer(), at: (0, 0), under: composite, context: context, modifierType: Self.self)
        }
        if let over {
            composite = compositeDrawnLayer(
                over.buffer(), at: (0, 0), over: composite, context: context, modifierType: Self.self)
        }
        return composite
    }

    /// `layer` parted by what `base` draws where it lies: the cells over one
    /// that draws no glyph — a background, or nothing — which are drawn over
    /// it, and the cells under a glyph, which are drawn under it; `nil` for a
    /// part with none.
    private static func parted(_ layer: ShapeCells, by base: FrameBuffer) -> (over: ShapeCells?, under: ShapeCells?) {
        var over = ShapeCells(width: layer.width, height: layer.height)
        var under = over
        var (anyOver, anyUnder) = (false, false)
        for (row, line) in base.lines.prefix(layer.height).enumerated() {
            let blank = line.columnsDrawingNoGlyph(width: layer.width)
            for column in 0..<layer.width where !layer[column, row].isEmpty {
                if blank[column] {
                    over[column, row] = layer[column, row]
                    anyOver = true
                } else {
                    under[column, row] = layer[column, row]
                    anyUnder = true
                }
            }
        }
        return (anyOver ? over : nil, anyUnder ? under : nil)
    }

    /// One drawing of the content: what it drew, where its glass ended up and
    /// how it joins, and the part of a joined shape each glass is to draw.
    private struct ContentWalk {
        var base: FrameBuffer
        var placed: [PlacedGlass]
        var groups: [GlassGroup]
        var found: [ViewIdentity: GlassPiece]

        /// Whether every glass drew what the container found it to draw: its
        /// part of the shape it joins, or its own glass where it joins none.
        var drewAsFound: Bool { placed.allSatisfy { $0.glass.piece == found[$0.glass.identity] } }
    }

    /// The content drawn with each glass in `pieces` drawing its part of a
    /// joined shape, and where its glass ended up.
    private func drawContent(drawing pieces: [ViewIdentity: GlassPiece], context: RenderContext) -> ContentWalk {
        let gathering = GlassEffectGathering(spacing: spacing, pieces: pieces, container: context.identity)
        var contentContext = context
        contentContext.environment.glassEffectGathering = gathering
        var base = TUIkitView.renderToBuffer(content, context: contentContext)
        // Where each glass ended up; the markers go, being the container's own.
        var placed: [PlacedGlass] = []
        base.forEachGeometryMarker { id, x, y in
            if let glass = gathering.placed(marked: id, x: x, y: y) { placed.append(glass) }
        }
        base.hitTestRegions.removeAll { gathering.owns($0.handlerID) }
        let groups = GlassGroup.grouping(placed, spacing: spacing)
        var found: [ViewIdentity: GlassPiece] = [:]
        for group in groups {
            for (identity, piece) in group.pieces { found[identity] = piece }
        }
        return ContentWalk(base: base, placed: placed, groups: groups, found: found)
    }

    /// The part of a joined shape each glass the container found joined draws,
    /// kept at its own child identity and marked live — `nil` with no state
    /// storage, where the content draws as it would outside a container.
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

    /// What lies between the members of `groups`, drawn into one layer
    /// `columns` × `rows`: each group's joined shape — its first member's
    /// glass in its first member's shape, filling the frame round its
    /// members, its rim lifted where the pointer is over any of them — less
    /// every cell a glass in `placed` covers, which that glass draws itself.
    /// All of it there: only glass that has arrived joins.
    @MainActor
    private static func between(
        _ groups: [GlassGroup], placed: [PlacedGlass], columns: Int, rows: Int, context: RenderContext
    ) -> ShapeCells {
        var layer = ShapeCells(width: columns, height: rows)
        for group in groups {
            guard let leader = group.leader?.glass else { continue }
            let frame = group.frame
            guard frame.width > 0, frame.height > 0 else { continue }
            var cells = GlassCells.drawing(
                leader.glass, in: leader.shape, columns: frame.width, rows: frame.height,
                hovered: group.members.contains { $0.glass.isHovered }, context: context, owner: nil)
            for glass in placed {
                cells.clearing(
                    CellRect(
                        x: glass.frame.x - frame.x, y: glass.frame.y - frame.y, width: glass.frame.width,
                        height: glass.frame.height))
            }
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
