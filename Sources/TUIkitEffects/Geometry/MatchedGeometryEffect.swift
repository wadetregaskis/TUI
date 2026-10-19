//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MatchedGeometryEffect.swift
//
//  `matchedGeometryEffect(id:in:properties:anchor:isSource:)`: views in a
//  group drawn at the geometry of the group's source, and carried from one
//  frame to another under an animation.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

// MARK: - Properties

/// A set of view properties that may be synchronized between views using the
/// `View.matchedGeometryEffect()` function.
@frozen
public struct MatchedGeometryProperties: OptionSet, Sendable {
    /// The raw bits.
    public let rawValue: UInt32

    /// Creates a set from its raw bits.
    @inlinable
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// The view's position, in window coordinates.
    public static let position = Self(rawValue: 1 << 0)

    /// The view's size, in local coordinates.
    public static let size = Self(rawValue: 1 << 1)

    /// Both the `position` and `size` properties.
    public static let frame: Self = [.position, .size]
}

// MARK: - The Modifier

extension View {
    /// Defines a group of views with synchronized geometry using an
    /// identifier and namespace that you provide.
    ///
    /// This method sets the geometry of each view in the group from the
    /// inserted view with `isSource = true` (known as the "source" view),
    /// updating the values marked by `properties`.
    ///
    /// If inserting a view in the same transaction that another view with the
    /// same key is removed, the system will interpolate their frame rectangles
    /// in window space to make it appear that there is a single view moving
    /// from its old position to its new position. The usual transition
    /// mechanisms define how each of the two views is rendered during the
    /// transition (e.g. fade in/out, scale, etc), the `matchedGeometryEffect()`
    /// modifier only arranges for the geometry of the views to be linked, not
    /// their rendering.
    ///
    /// If the number of currently-inserted views in the group with
    /// `isSource = true` is not exactly one results are undefined, due to it
    /// not being clear which is the source view.
    ///
    /// ```swift
    /// @Namespace private var chips
    ///
    /// HStack {
    ///     VStack { ForEach(left) { Chip($0).matchedGeometryEffect(id: $0.id, in: chips) } }
    ///     VStack { ForEach(right) { Chip($0).matchedGeometryEffect(id: $0.id, in: chips) } }
    /// }
    /// // withAnimation { move a chip from `left` to `right` } carries it across.
    /// ```
    ///
    /// ## In a terminal
    ///
    /// Frames are whole cells, and the geometry is the view's frame in the
    /// global space — the screen — as `GeometryProxy.frame(in: .global)`
    /// answers it, found once the frame is drawn and corrected in the same
    /// frame when a view was drawn from where another one turned out not to be
    /// (design study A2's correction, the one a `GeometryReader` makes).
    ///
    /// - **The view keeps its own place in its parent's layout**, as SwiftUI's
    ///   does (measured: a view following a larger source leaves its siblings
    ///   where they were, `Tools/SwiftUIProbes/Matched geometry/mg1.out`). What follows the source is its drawing: its content
    ///   is laid out at the source's size and drawn at the source's place, at
    ///   its own place in the stacking order — over the views before it and
    ///   under the views after it — with only the cells it paints drawn, and
    ///   its clicks where it is drawn (as content drawn past its frame is,
    ///   decisions B-GUIDE-3). Nothing is drawn where it is laid out. While an
    ///   animation carries it, it floats over every view, as `.offset` draws
    ///   one: a terminal's blank cells paint, so in its place in the stacking
    ///   order a view carried toward the views before it would be lost under
    ///   the views after it (Deliberate deviations A8).
    /// - **A follower's `anchor` lands on the source's.** The source shares
    ///   the point of it its own `anchor` names; a follower matching
    ///   `.position` is drawn with the point its `anchor` names there.
    ///   Matching `.size` alone, it stays at its own top-leading corner. A
    ///   content that does not take the size it is offered — a fixed
    ///   `.frame` — is placed as SwiftUI was measured placing it: offset from
    ///   the matched frame by twice the anchor's share of the difference, so a
    ///   centred one sits at the frame's trailing bottom
    ///   (`Tools/SwiftUIProbes/Matched geometry/mg2b.out`).
    /// - **Under an animated change it is carried.** A view inserted as one of
    ///   its group is removed moves from where that one was drawn to where it
    ///   belongs, and a follower whose source changes — its `id` changed, or
    ///   the source was replaced — moves from where it was drawn to its new
    ///   source. The rectangle is interpolated edge by edge, and the view is
    ///   laid out again at each frame's size (refusal review O4, ruled
    ///   2026-10-12); while its size is its own it is only moved, a whole cell
    ///   at a time. SwiftUI scales a follower's drawing where its size
    ///   changes instead of laying it out again (measured); a terminal cannot
    ///   scale a cell (`mg3.out`). A source that its parent moves is not animated by this
    ///   effect: that is the layout's own animation, and its followers follow
    ///   it frame by frame. Under reduce motion the change is drawn at once.
    /// - **A removed view is carried with the inserted one** while its
    ///   removal transition plays, as SwiftUI's is (`mg3.out` A1, A2): the
    ///   picture it last drew — the size it was, since a removed view no longer
    ///   exists to lay out again (Deliberate deviations A3, A8) — is placed in
    ///   the frame the inserted one is drawn at on each frame, as a content of
    ///   its size is placed in a matched frame, a whole cell at a time. A fade
    ///   reaches both as they move.
    ///
    /// - Parameters:
    ///   - id: The identifier, often derived from the identifier of the data
    ///     being displayed by the view.
    ///   - namespace: The namespace in which defines the `id`. New namespaces
    ///     are created by adding an `@Namespace` variable to a ``View`` type
    ///     and reading its value in the view's body method.
    ///   - properties: The properties to copy from the source view.
    ///   - anchor: The relative location in the view used to produce its
    ///     shared position value.
    ///   - isSource: True if the view should be used as the source of geometry
    ///     for other views in the group.
    /// - Returns: A new view that defines an entry in the global database of
    ///   views synchronizing their geometry.
    public func matchedGeometryEffect<ID: Hashable>(
        id: ID, in namespace: Namespace.ID, properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center, isSource: Bool = true
    ) -> some View {
        _MatchedGeometryEffectView(
            key: MatchedGeometryKey(namespace: namespace, id: AnyHashable(id)), anchor: anchor,
            properties: properties, isSource: isSource, content: self)
    }
}

// MARK: - Core

/// Draws its content where its group puts it. See
/// ``View/matchedGeometryEffect(id:in:properties:anchor:isSource:)``.
///
/// A `_*Core` with no public face: like `.offset`, the effect is a modifier on
/// the view it wraps, and what it does — draw the content at a frame found
/// from other views' drawings — is procedural.
struct _MatchedGeometryEffectView<Content: View>: View {
    let key: MatchedGeometryKey
    let anchor: UnitPoint
    let properties: MatchedGeometryProperties
    let isSource: Bool
    let content: Content

    var body: Never {
        fatalError("_MatchedGeometryEffectView renders via Renderable")
    }
}

extension _MatchedGeometryEffectView: Renderable, Layoutable {
    /// The effect never changes the view's place in its parent's layout:
    /// this measures as its content.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !context.isMeasuring, let coordinator = context.geometryCoordinator,
            let storage = context.stateStorage
        else { return TUIkitView.renderToBuffer(content, context: context) }
        let registry = coordinator.matchedGeometry
        var member = MatchedMemberDrawing(effect: self, identity: context.identity, registry: registry)
        // A reader — told where it is predicted to be, held to it, and keeping
        // the carried origin in force for the frames after — only where it may
        // be drawn somewhere else, or a follower draws from where it is: a
        // source at rest with none is only found, as `onGeometryChange` is.
        // Claimed BEFORE the content renders, as a visual effect claims its
        // ask: the marker's id is the ordinal of the claim at this identity.
        let role: GeometryAsk.Role =
            member.needsPlacement || registry.hasFollowers(of: key) ? .reader : .reporter
        guard let ask = context.makeGeometryAsk(role: role) else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        member.registration.marker = ask.id
        // Joined to the group on every frame it draws, and drawn from where
        // the others are: work a served buffer cannot do.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        // Found by the scene root whether or not it asks where it is, so the
        // others can draw from it.
        ask.want(.global)

        // Where the walk stands before the content draws, for a second drawing
        // at another size to start from — taken only where the member may be
        // drawn anywhere but its own place, which a source at rest is not.
        let checkpoint = member.needsPlacement ? RenderWalkCheckpoint(context: context) : nil
        let own = TUIkitView.renderToBuffer(content, context: context)
        member.drew(size: own.cellSize)

        var drawn = own
        if let checkpoint, let origin = ask.observation(in: .global)?.origin {
            let frame = member.frame(at: origin, animations: storage.animations, context: context)
            if frame != member.ownFrame {
                drawn = placed(
                    own, at: frame, member: &member, checkpoint: checkpoint, context: context)
            }
            carryLeaving(of: member, to: frame, departures: storage.departures)
        }
        // Landed, or never carried: the member that left is carried no
        // further, and the store keeps where it was last carried to for as
        // long as its picture is still drawn.
        if !member.isCarried { member.registration.state.leaving = nil }

        if isSource { member.registration.expectedOrigin = ask.expectedOrigin(in: .global) }
        ask.finishRecording(size: own.cellSize)
        if coordinator.register(ask) { drawn.hitTestRegions.append(.geometryMarker(ask.id)) }
        coordinator.matchedGeometry.register(member.registration, in: key)
        return drawn
    }

    /// The content drawn at `frame` — the matched frame, in the global space
    /// — from a footprint the size of its own: moved where the size is its
    /// own, and laid out again at the frame's size where it is not.
    private func placed(
        _ own: FrameBuffer, at frame: CellRect, member: inout MatchedMemberDrawing,
        checkpoint: RenderWalkCheckpoint, context: RenderContext
    ) -> FrameBuffer {
        let ownFrame = member.ownFrame
        var picture = own
        var origin = frame.origin
        if frame.size != ownFrame.size {
            // Drawn again, at the frame's size: the first drawing measured the
            // view's own size for the footprint, and what it registered is put
            // back so the second takes the same ids.
            checkpoint.rewind(context: context)
            picture = TUIkitView.renderToBuffer(
                content, context: context.withAvailableSize(width: frame.width, height: frame.height))
            let offset = MatchedGeometryPlacement.contentOffset(
                in: frame.size, content: picture.cellSize, anchor: anchor,
                matchesPosition: member.matchesPosition)
            origin = CellPoint(x: origin.x + offset.x, y: origin.y + offset.y)
        }
        member.registration.drawn = CellRect(
            x: frame.x - ownFrame.x, y: frame.y - ownFrame.y, width: frame.width, height: frame.height)
        let (dx, dy) = (origin.x - ownFrame.x, origin.y - ownFrame.y)
        guard member.isCarried else {
            return picture.drawnPastSlot(width: ownFrame.width, height: ownFrame.height, offsetX: dx, offsetY: dy)
        }
        return Self.floating(picture, by: dx, dy, from: ownFrame.size)
    }

    /// Tells the departure store how far the member of the group that left as
    /// this one arrived is carried on this frame — the frame it lands on
    /// included: its picture is placed in the frame this one is drawn at, as
    /// a content of its size is placed in a matched frame
    /// (``MatchedGeometryPlacement/contentOffset(in:content:anchor:matchesPosition:)``),
    /// so the two move together as SwiftUI's do (`mg3.out` A1, A2), and the
    /// picture fades where they are (decisions B-O4-1). The picture is the one
    /// it last drew, so it keeps its size: a cell cannot be scaled. Only its
    /// own cells move, found in what left by its marker: what was drawn round
    /// it fades where it was.
    private func carryLeaving(of member: MatchedMemberDrawing, to frame: CellRect, departures: DepartureStore) {
        guard let leaving = member.registration.state.leaving else { return }
        let left = leaving.presented
        let inside = MatchedGeometryPlacement.contentOffset(
            in: frame.size, content: left.size, anchor: anchor, matchesPosition: member.matchesPosition)
        departures.noteCarried(
            leaving.identity, drawnAt: leaving.marker, width: leaving.frame.width, height: leaving.frame.height,
            byX: frame.x + inside.x - left.x, y: frame.y + inside.y - left.y)
    }

    /// `picture` drawn `(dx, dy)` from a footprint of `size`, floating over
    /// everything on the page as `.offset` draws a view (``View/offset(x:y:)``,
    /// Deliberate deviations L6): a view in flight is drawn over the views
    /// after it as well as those before it — at its place in the stacking
    /// order, a terminal's blank cells paint, so a view carried toward the
    /// views before it was lost under every container after it until it
    /// cleared them. Its clicks go with it; its geometry markers stay in the
    /// footprint, where it is laid out, as they do for a view drawn past its
    /// slot. It stays where it is put at the screen's edge rather than sliding
    /// back on.
    private static func floating(_ picture: FrameBuffer, by dx: Int, _ dy: Int, from size: CellSize) -> FrameBuffer {
        var content = picture
        content.hitTestRegions.removeAll(where: \.isGeometryMarker)
        var footprint = FrameBuffer(footprintWidth: size.width, height: size.height)
        footprint.hitTestRegions = picture.hitTestRegions.filter(\.isGeometryMarker)
        footprint.overlays.append(
            OverlayLayer(
                offsetX: dx, offsetY: dy, content: content, level: .popover,
                zIndex: OverlayLayer.displacedDrawingZIndex, clampsToScreen: false, isOpaque: false))
        return footprint
    }
}

// MARK: - One Member's Frame

/// What one member of a group draws from on one frame, and the registration
/// it leaves for the scene root to check.
@MainActor
private struct MatchedMemberDrawing {
    var registration: MatchedRegistration
    /// The source a follower draws from, if its group has one.
    let source: MatchedSource?
    /// Where an animated change this frame starts from, in the global space:
    /// where this member was drawn last frame, or the member that left as it
    /// arrived.
    let startsFrom: CellRect?
    let properties: MatchedGeometryProperties
    let anchor: UnitPoint
    /// The member's own frame, once its origin is known.
    private(set) var ownFrame: CellRect

    init(effect: _MatchedGeometryEffectView<some View>, identity: ViewIdentity, registry: MatchedGeometryRegistry) {
        let key = effect.key
        // The wrapper's own type tells it from another wrapper on the same
        // view, which draws at the same identity (``MatchedMemberID``).
        let owner = ObjectIdentifier(type(of: effect))
        let previous = registry.state(of: MatchedMemberID(identity: identity, owner: owner))
        properties = effect.properties
        anchor = effect.anchor
        ownFrame = CellRect(x: 0, y: 0, width: 0, height: 0)
        let source = effect.isSource ? nil : registry.source(of: key, excluding: identity)
        self.source = source
        registration = MatchedRegistration(
            identity: identity, owner: owner, marker: HitTestRegion.HandlerID(0), isSource: effect.isSource,
            anchor: effect.anchor, size: CellSize(width: 0, height: 0),
            state: MatchedMemberState(
                key: key, followed: source?.identity, epoch: previous?.epoch ?? 0,
                offsets: previous?.offsets ?? .zero))
        registration.state.leaving = previous?.leaving
        registration.followed = source
        if !effect.isSource {
            // A follower is carried when what it follows changes: its id, or
            // the source of its group.
            if let previous, previous.key != key || previous.followed != source?.identity {
                startsFrom = previous.presented
            } else {
                startsFrom = nil
            }
        } else if !registry.wasMember(identity, of: key), let departed = registry.departed(from: key, arriving: identity) {
            // A source arriving as another of its group leaves, which is
            // carried with it.
            startsFrom = departed.presented
            registration.assumedDeparted = departed.identity
            registration.state.leaving = departed
        } else {
            startsFrom = nil
        }
    }

    /// Notes the member's own size, as its content drew at it.
    mutating func drew(size: CellSize) {
        ownFrame = CellRect(x: ownFrame.x, y: ownFrame.y, width: size.width, height: size.height)
        registration.size = size
    }

    /// Whether the member is being carried this frame: an animated change
    /// is moving its drawing. Asked once ``frame(at:animations:context:)`` has
    /// said where it is drawn.
    var isCarried: Bool {
        !registration.state.offsets.isZero
    }

    /// Whether this frame may draw the member anywhere but its own place.
    var needsPlacement: Bool {
        source != nil || startsFrom != nil || !registration.state.offsets.isZero
    }

    /// Whether the member matches its source's position, which places a
    /// content that does not take the matched size.
    var matchesPosition: Bool {
        properties.contains(.position)
    }

    /// The frame to draw the member at, in the global space, with its own top
    /// leading corner at `origin`: its source's geometry, or its own, carried
    /// from where an animated change started.
    mutating func frame(
        at origin: CellPoint, animations: AnimationStore, context: RenderContext
    ) -> CellRect {
        ownFrame = CellRect(x: origin.x, y: origin.y, width: ownFrame.width, height: ownFrame.height)
        let target =
            source.map {
                MatchedGeometryPlacement.frame(following: $0, own: ownFrame, properties: properties, anchor: anchor)
            } ?? ownFrame
        if let startsFrom {
            registration.state.epoch += 1
            registration.state.offsets = MatchedEdgeOffsets(from: startsFrom, to: target)
        }
        guard !registration.state.offsets.isZero else { return target }
        // Under the member's own wrapper type, as its state is kept: two
        // effects on one view run apart.
        let key = AnimationStore.Key(
            identity: registration.identity, owner: registration.owner, slot: registration.state.epoch)
        let now = context.environment.frameNowNanos
        // A change is a first sight at its own epoch: it starts the animation
        // this frame's change runs under, and none at all where the change is
        // not animated, or motion is reduced — then it is drawn at once.
        let phase = animations.arrivalPhase(
            for: key, animation: startsFrom == nil ? nil : Self.animation(in: context), nowNanos: now,
            isMeasuring: false)
        guard animations.isAnimating(at: key, nowNanos: now) else {
            registration.state.offsets = .zero
            return target
        }
        return registration.state.offsets.applied(to: target, remaining: 1 - phase)
    }

    /// The animation this frame's change runs under: the transaction's, where
    /// the frame may animate and motion is not reduced (a matched view moves
    /// in X and Y, owner decision A-D3M-1).
    private static func animation(in context: RenderContext) -> Animation? {
        let environment = context.environment
        guard environment.animationFrame.canAnimate, !environment.accessibilityReduceMotion else { return nil }
        return environment.transaction.effectiveAnimation
    }
}

// MARK: - Placement Arithmetic

/// Where a follower goes, and where a content that does not take the size it
/// is offered sits — SwiftUI's arithmetic, measured
/// (`Tools/SwiftUIProbes/Matched geometry/mg2.out`, `mg2b.out`), in whole
/// cells: each answer is worked out in fractional cells and rounded down once.
enum MatchedGeometryPlacement {
    /// The frame a follower with `anchor` matching `properties` takes from
    /// `source`: the source's size where it matches `.size`, and its own
    /// otherwise; placed with its anchor on the source's anchor point where
    /// it matches `.position`, and at its own top-leading corner otherwise.
    static func frame(
        following source: MatchedSource, own: CellRect, properties: MatchedGeometryProperties, anchor: UnitPoint
    ) -> CellRect {
        let size = properties.contains(.size) ? source.frame.size : own.size
        guard properties.contains(.position) else {
            return CellRect(x: own.x, y: own.y, width: size.width, height: size.height)
        }
        let x =
            Double(source.frame.x) + source.anchor.x * Double(source.frame.width) - anchor.x * Double(size.width)
        let y =
            Double(source.frame.y) + source.anchor.y * Double(source.frame.height) - anchor.y * Double(size.height)
        return CellRect(
            x: Int(x.rounded(.down)), y: Int(y.rounded(.down)), width: size.width, height: size.height)
    }

    /// Where a content of size `content`, laid out in a matched frame of size
    /// `frame`, is drawn from the frame's top-leading corner.
    ///
    /// Matching `.position`, SwiftUI offsets it by twice the anchor's share of
    /// the difference — a centred 10×10 content in a 40×20 frame is drawn at
    /// (30, 10), against the frame's bottom-trailing corner (measured,
    /// macOS 15.8) — and matching `.size` alone, not at all.
    static func contentOffset(
        in frame: CellSize, content: CellSize, anchor: UnitPoint, matchesPosition: Bool
    ) -> CellPoint {
        guard matchesPosition else { return CellPoint(x: 0, y: 0) }
        return CellPoint(
            x: Int((2 * anchor.x * Double(frame.width - content.width)).rounded(.down)),
            y: Int((2 * anchor.y * Double(frame.height - content.height)).rounded(.down)))
    }
}

// MARK: - Seeing Through the Wrapper

/// Names its content so a container asking for a z-index can look through
/// this wrapper. Read-only: it does not conform to ``ContentRewrapping``, so
/// the effect is not handed to each member of multi-view content.
extension _MatchedGeometryEffectView: SingleContentWrapper {
    var wrappedContent: Content { content }
}
