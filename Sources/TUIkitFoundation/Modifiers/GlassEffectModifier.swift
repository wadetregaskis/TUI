//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassEffectModifier.swift
//
//  `glassEffect(_:in:)`: a glass behind a view — a material's translucent
//  surface in a shape, its rim drawn in the appearance's lines.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Applies a glass effect to this view — mirrors SwiftUI's
    /// `glassEffect(_:in:)`.
    ///
    /// The glass is a shape anchored behind this view, filling its frame: a
    /// material's translucent surface (``Glass``), with a rim — the shape's
    /// outline in a highlight — in the lines of the ``Appearance`` in force.
    /// Layout is untouched, as in SwiftUI, and the rim sits in the frame's
    /// outermost cells, behind the view, showing through its blank ones; so a
    /// glass round a label wants the label padded, as SwiftUI's examples pad
    /// it:
    ///
    /// ```swift
    /// Label("Flag", systemImage: "flag.fill")
    ///     .padding()
    ///     .glassEffect()
    /// ```
    ///
    /// draws
    ///
    /// ```
    /// ╭────────╮
    /// │ ⚑ Flag │
    /// ╰────────╯
    /// ```
    ///
    /// over a surface that tints whatever is behind it. One row tall the rim is
    /// the shape's ends, `( … )`. Under `.heavy` or `.doubleLine` it is those
    /// lines; under `.braille`, a dotted outline of the shape; under `.block`, a
    /// band of the rim's colour round the surface; under `.blank`, none. A
    /// shape outside the rectangle family — a circle, a path of your own — is
    /// rimmed by its rasterized border (`strokeBorder(lineWidth: 1)`), or in
    /// dots under `.braille`.
    ///
    /// No blur: a cell has nothing below it to blur, so what is behind shows
    /// through tinted, glyphs and all (Deliberate deviations C11). ``Glass/identity``
    /// draws nothing.
    ///
    /// You typically use this modifier with a ``GlassEffectContainer``, which
    /// draws the glass of views near one another as one shape.
    ///
    /// - Parameters:
    ///   - glass: The glass. ``Glass/regular`` unless given.
    ///   - shape: The shape the glass takes. A capsule
    ///     (``DefaultGlassEffectShape``) unless given.
    /// - Returns: The view, on glass.
    public func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View {
        _GlassEffect(content: self, shape: shape, glass: glass)
    }
}

/// `StateStorage` property indices for ``_GlassEffect``'s record (a static on
/// a generic type cannot be stored, so this lives at file scope).
///
/// The record is kept at a child identity of the glass's own
/// (``GlassHoverRecord``), not at the identity it draws its content at: marking
/// that one live would keep the `@State` of whatever else is drawn there
/// (`StateStorage.StateKey`'s table, and decisions A40's finding).
private enum GlassEffectStateIndex {
    /// Whether the pointer is over interactive glass.
    static let isHovered = 0
}

/// The identity interactive glass keeps its record at: a child of its own.
private enum GlassHoverRecord {}

/// ``View/glassEffect(_:in:)``'s view: the content, with its glass drawn
/// behind it.
///
/// The glass's cells — the surface filling the shape, the rim over it — are
/// drawn by ``GlassCells`` the size the content came back, and the content is
/// composited over them, as over any background. Where the rim or the surface
/// draws a glyph — a line, a cap, a corner quadrant — and the content's cell
/// shows nothing, the content's cell is claimed at a field of 0 so the glyph
/// shows through (``FrameBuffer/claimsShowingGlyphs(of:)``), which is what puts
/// the rim in a padded view's padding.
struct _GlassEffect<Content: View, S: Shape>: View {
    let content: Content
    let shape: S
    let glass: Glass

    var body: Never { fatalError("_GlassEffect renders via Renderable") }
}

extension _GlassEffect: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !glass.isIdentity else { return TUIkitView.renderToBuffer(content, context: context) }
        let hover = hoverBox(context)
        let hovered = hover?.value ?? false
        var base = TUIkitView.renderToBuffer(content, context: contentContext(context))
        guard base.width > 0, base.height > 0 else { return base }
        // In a container, a glass the container drew last pass as one of a
        // joined group leaves its glass to the container again.
        let gathering = context.isMeasuring ? nil : context.environment.glassEffectGathering
        let drawsItself = gathering?.drawnByContainer.contains(context.identity) != true
        let presence = arrival(in: gathering, context: context)
        var buffer = base
        if drawsItself {
            let layer = GlassCells.drawing(
                glass, in: shape, columns: base.width, rows: base.height, hovered: hovered, presence: presence,
                context: context, owner: Self.self)
            base.opacityRegions += base.claimsShowingGlyphs(of: layer)
            buffer = compositeDrawnLayer(layer.buffer(), at: (0, 0), under: base, context: context, modifierType: Self.self)
        }
        if let gathering {
            tell(gathering, about: &buffer, drewItself: drawsItself, hovered: hovered, presence: presence, context: context)
        }
        if let hover { observeHover(into: hover, buffer: &buffer, context: context) }
        return buffer
    }

    /// How far this glass has arrived, 0 to 1: in a container, glass arriving
    /// under an animation fades in (`glassEffectTransition(_:)`); anywhere
    /// else it comes with its view, whose own transition it shares.
    private func arrival(in gathering: GlassEffectGathering?, context: RenderContext) -> Double {
        guard gathering != nil, let storage = context.stateStorage else { return 1 }
        return context.environment.glassArrival(at: context.identity, storage: storage)
    }

    /// Tells the ``GlassEffectContainer`` this glass is in what it is, and
    /// stamps the marker it finds it by.
    ///
    /// A render side effect a cached buffer cannot repeat — the container
    /// learns of its glass only from glass that draws — so the memos keep none
    /// of a subtree that does it.
    private func tell(
        _ gathering: GlassEffectGathering, about buffer: inout FrameBuffer, drewItself: Bool, hovered: Bool,
        presence: Double, context: RenderContext
    ) {
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        let marker = gathering.gather(
            GatheredGlass(
                identity: context.identity, glass: glass,
                shape: resolvedShape(shape, in: context, columns: buffer.width, rows: buffer.height),
                size: CellSize(width: buffer.width, height: buffer.height),
                union: context.environment.glassEffectUnion, isHovered: hovered, presence: presence,
                drewItself: drewItself))
        buffer.hitTestRegions.append(.geometryMarker(marker))
    }

    /// The context the content is drawn in: on tinted glass, with the tinted
    /// surface as what its ink lands on (``EnvironmentValues/enclosingSurface``),
    /// so a control inside floors its contrast against the glass and a field
    /// steps off it. Noted with the render cache as an applied environment
    /// value, so a memoized subtree that drew on another tint is dropped.
    fileprivate func contentContext(_ context: RenderContext) -> RenderContext {
        guard let surface = glass.tintedSurface(in: context.environment) else { return context }
        var copy = context
        copy.environment.surfaceBackground = surface
        copy.environmentApplicationDepth += 1
        if let cache = context.renderCache,
            case .changed = cache.noteAppliedEnvironment(
                surface, identity: context.identity, keyPath: \EnvironmentValues.surfaceBackground,
                depth: copy.environmentApplicationDepth)
        {
            // A surface is ink's ground; the sizes below it stay.
            cache.clearAffected(by: context.identity, keepingSizes: true)
        }
        return copy
    }

    /// Where interactive glass keeps whether the pointer is over it — `nil` for
    /// glass that is not interactive, and in a disabled subtree, where nothing
    /// answers the pointer.
    private func hoverBox(_ context: RenderContext) -> StateBox<Bool>? {
        guard glass.isInteractive, context.environment.isEnabled, let storage = context.stateStorage else { return nil }
        let identity = context.withChildIdentity(erasedType: GlassHoverRecord.self, index: 0).identity
        if !context.isMeasuring { storage.markActive(identity) }
        return storage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: GlassEffectStateIndex.isHovered),
            default: false)
    }

    /// Watches the pointer over `buffer` for interactive glass: a hover
    /// OBSERVER, which hears the pointer come and go without taking the hover
    /// from a control inside, nor any click.
    private func observeHover(into box: StateBox<Bool>, buffer: inout FrameBuffer, context: RenderContext) {
        guard !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher else { return }
        dispatcher.requestFeature(.motion, in: context)
        let handlerID = dispatcher.registerHoverObserver(in: context) { event in
            switch event.phase {
            case .entered:
                if !box.value { box.value = true }
                return true
            case .exited:
                if box.value { box.value = false }
                return true
            default:
                return false
            }
        }
        buffer.hitTestRegions.append(
            HitTestRegion(offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height, handlerID: handlerID))
    }
}

extension _GlassEffect: Layoutable {
    /// The content's size: glass changes nothing about layout.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: glass.isIdentity ? context : contentContext(context))
    }
}
