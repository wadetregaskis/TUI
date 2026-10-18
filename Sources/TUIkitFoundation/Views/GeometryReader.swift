//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GeometryReader.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Geometry Proxy

/// The size and coordinate space of the container reading it.
///
/// Handed to a ``GeometryReader``'s content closure so the content can size
/// itself against the space it was actually given, and place itself against
/// the spaces around it: ``frame(in:)`` in its own space, the
/// global one, one a parent named with ``View/coordinateSpace(_:)``, or the
/// nearest scroll view's; ``bounds(of:)`` for the reverse.
///
/// ## How a terminal answers where a view is
///
/// TUIkit draws bottom-up: a container renders a child, then places it, so a
/// reader does not know where it sits while its content is being built — which
/// is when it asks. It is answered with a prediction: the containers above it
/// that know where they will place a child before drawing it (the stacks,
/// `Grid`, a custom `Layout`, a scroll view, `.padding`, borders, `.frame`,
/// overlays, `ZStack`, `.offset`, `.position`) carry the reader's origin down,
/// and what the others add — usually the same every frame — is taken from
/// where the owner of the space found it last frame. The owner (the named
/// view, the scroll view, the scene root) finds it again once it has drawn,
/// and when the answer was wrong — the first frame, or one on which something
/// the prediction does not follow moved it — draws its subtree once more with
/// the right answer, in the same frame. (Design study A2, G4; a reader is
/// greedy, so its own content can never move it, and one more drawing
/// settles it.)
///
/// What reaches the screen is drawn from where the reader really is — in a
/// presented surface (a sheet, a popover) and in a window bar's content
/// (`.toolbar` items) too, since the scene root reads the whole screen with
/// the window's layers composited into it (B-D5G-3), and inside a `Table`
/// cell, which carries no origin down and so is corrected on a reader's first
/// frame (B-D5G-2) — except where no owner finds it once the frame is drawn
/// (decisions D5G): a view under a container that redraws its content's lines
/// into a new buffer without the hit-test regions in them, which carry the
/// markers, is not found, and a reader there is told where the containers
/// above it would place it, and nothing checks it (B-D5G-2).
///
/// ## What this deliberately does not have
///
/// SwiftUI's `GeometryProxy` also carries `safeAreaInsets`. A terminal has no
/// safe area — the whole grid is addressable, and TUIkit's chrome (app header,
/// status bar) has already been subtracted from what a view is offered —
/// so answering it with a constant would be answering a question the caller
/// should not be asking.
///
/// Nor is it `Equatable` or `Sendable`, as SwiftUI's is not (its `Sendable`
/// conformance is explicitly unavailable). A proxy answers from the walk that
/// made it — what the owners of its spaces found, frame by frame — so two
/// proxies have no value to compare, and one sent off the main actor would
/// be read while the render path writes it.
public struct GeometryProxy {
    /// The container's size in cells.
    public let size: CellSize

    /// Where the container asks about the spaces around it, or `nil` for a
    /// proxy that can only answer its own: one made by hand, or in a measure.
    let ask: GeometryAsk?

    package init(width: Int, height: Int, ask: GeometryAsk? = nil) {
        self.size = CellSize(width: width, height: height)
        self.ask = ask
    }

    /// What the container was told about the spaces around it, in the order
    /// it asked — what a reader notes so a move clears what is cached below it.
    var toldAnswers: [GeometryObservation?] { ask?.toldAnswers ?? [] }

    /// The container's frame in the given ``CoordinateSpace`` value — the form
    /// SwiftUI deprecated for the protocol one, internal here: what the public
    /// form answers by (owner's ruling of 2026-10-12, no deprecated SwiftUI
    /// API).
    func frame(in coordinateSpace: CoordinateSpace) -> CellRect {
        let origin: CellPoint
        switch coordinateSpace {
        case .local:
            origin = CellPoint(x: 0, y: 0)
        case .global, .named:
            origin = ask?.observation(in: coordinateSpace)?.origin ?? CellPoint(x: 0, y: 0)
        }
        return CellRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    /// The container's frame in the given coordinate space.
    ///
    /// `.local` is always `(0, 0)` and the size. Every other space answers with
    /// where its owner found the container (see the type's discussion), and a
    /// name no view around the container declared — like `.scrollView` outside
    /// any scroll view — answers in the global space, as SwiftUI's does.
    ///
    /// - Parameter coordinateSpace: `.local`, `.global`, `.named(_:)`,
    ///   `.scrollView` or `.scrollView(axis:)`.
    /// - Returns: The frame, in cells.
    public func frame(in coordinateSpace: some CoordinateSpaceProtocol) -> CellRect {
        frame(in: coordinateSpace.coordinateSpace)
    }

    /// The given coordinate space's bounds rectangle, converted to the local
    /// coordinate space — `nil` when no view around the container declares it
    /// (an unknown name, `.scrollView` outside any scroll view), as SwiftUI's
    /// is.
    ///
    /// - Parameter coordinateSpace: The space whose bounds to convert.
    /// - Returns: The space's rectangle, measured from the container's origin.
    public func bounds(of coordinateSpace: NamedCoordinateSpace) -> CellRect? {
        guard let observation = ask?.observation(in: coordinateSpace.coordinateSpace, needsSize: true),
            let spaceSize = observation.spaceSize
        else { return nil }
        return CellRect(
            x: -observation.origin.x, y: -observation.origin.y,
            width: spaceSize.width, height: spaceSize.height)
    }
}

/// Not `Sendable`: see ``GeometryProxy``. Spelled as SwiftUI spells it, so
/// sending a proxy to another isolation fails to compile rather than racing.
@available(*, unavailable)
extension GeometryProxy: Sendable {}

/// A size in whole terminal cells.
///
/// The counterpart of `CGSize`, spelled in cells for the reason recorded on
/// ``AlignmentID``: this framework's geometry is integral.
public struct CellSize: Hashable, Sendable {
    /// The width in cells.
    ///
    /// A `var` so an animation can substitute it — see the `Animatable`
    /// conformance in `AnimatableGeometry.swift`.
    public var width: Int

    /// The height in rows.
    public var height: Int

    /// Creates a size in whole cells.
    ///
    /// Public because a `CellSize` is not only something a ``GeometryProxy``
    /// hands out: ``View/offset(_:)`` takes one, and a caller comparing against
    /// a proxy's size has to be able to write the value it expects.
    ///
    /// - Parameters:
    ///   - width: The width in cells.
    ///   - height: The height in rows.
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// A rectangle in whole terminal cells — the counterpart of `CGRect`.
public struct CellRect: Hashable, Sendable {
    /// The leading edge, in cells from the coordinate space's origin.
    ///
    /// A `var`, like ``CellSize/width``, so an animation can substitute it.
    public var x: Int

    /// The top edge, in rows from the coordinate space's origin.
    public var y: Int

    /// The width in cells.
    public var width: Int

    /// The height in rows.
    public var height: Int

    /// The trailing edge (exclusive).
    public var maxX: Int { x + width }

    /// The bottom edge (exclusive).
    public var maxY: Int { y + height }

    /// The leading edge: ``x``, under the name `CGRect`'s readers use —
    /// `proxy.frame(in: .named("scroll")).minY` is how SwiftUI code tracks a
    /// scroll offset. There is no `midX`/`midY`: a midpoint floored before it
    /// is subtracted from another is the trap integral geometry sets (see
    /// ``AlignmentID``), so the spelling that invites it is left out.
    public var minX: Int { x }

    /// The top edge: ``y``, under `CGRect`'s name — see ``minX``.
    public var minY: Int { y }

    /// The top-leading corner, as `CGRect.origin` is.
    public var origin: CellPoint { CellPoint(x: x, y: y) }

    /// The width and height, as `CGRect.size` is.
    public var size: CellSize { CellSize(width: width, height: height) }

    /// Creates a rectangle in whole cells.
    ///
    /// Public because a `CellRect` is not only something a ``GeometryProxy``
    /// hands out: ``ShapeStyle/in(_:)`` takes one, and a caller comparing
    /// against a proxy's frame has to be able to write the value it expects.
    ///
    /// - Parameters:
    ///   - x: The leading edge, in cells.
    ///   - y: The top edge, in rows.
    ///   - width: The width in cells.
    ///   - height: The height in rows.
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - Geometry Reader

/// A container that sizes itself to the space offered, and hands that size to
/// its content.
///
/// This is the one thing an app previously could not work around: nothing in
/// TUIkit let a view read the space it was given and branch on it. The layout
/// system computes sizes top-down and the answer never reached the view.
///
/// ```swift
/// GeometryReader { proxy in
///     if proxy.size.width >= 60 {
///         HStack { Sidebar(); Detail() }
///     } else {
///         Detail()          // too narrow for two columns
///     }
/// }
/// ```
///
/// ## Sizing
///
/// As in SwiftUI, a `GeometryReader` **fills** the space proposed to it on both
/// axes rather than hugging its content, and places its content at the top
/// leading corner. That is what makes the reported size meaningful: it is the
/// container's size, not the content's.
///
/// Put one inside a `.frame(...)` when you want it bounded:
///
/// ```swift
/// GeometryReader { proxy in … }
///     .frame(width: 40, height: 10)
/// ```
public struct GeometryReader<Content: View>: View {
    /// Builds the content from the resolved geometry.
    public let content: (GeometryProxy) -> Content

    /// Creates a geometry reader.
    ///
    /// - Parameter content: A closure receiving the reader's resolved geometry.
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {
        self.content = content
    }

    public var body: some View {
        _GeometryReaderCore(content: content)
    }
}

// MARK: - Core

/// Resolves the geometry and renders the content against it.
private struct _GeometryReaderCore<Content: View>: View, Renderable, Layoutable {
    let content: (GeometryProxy) -> Content

    var body: Never { fatalError("_GeometryReaderCore renders via Renderable") }

    /// Fills the proposal on both axes.
    ///
    /// The content is *not* measured. Measuring it would mean building it, which
    /// needs a proxy, which needs the size this call is computing — the
    /// circularity SwiftUI resolves the same way, by making the reader greedy.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize(
            width: context.fillingWidth(proposal: proposal),
            height: proposal.height ?? context.availableHeight,
            isWidthFlexible: true,
            isHeightFlexible: true)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let width = max(0, context.availableWidth)
        let height = max(0, context.availableHeight)
        // What the content asks about the spaces around it goes through this,
        // and is held to by the spaces' owners — see `GeometryProxy`.
        let ask = context.makeGeometryAsk(role: .reader)
        let proxy = GeometryProxy(width: width, height: height, ask: ask)

        var buffer = TUIkitView.renderToBuffer(content(proxy), context: contentContext(noting: proxy, in: context))

        // The reader occupies everything it was offered even when its content
        // does not, so a sibling below starts where the reader ends rather than
        // where its content happens to stop. Rebuilt through `replacingLines`
        // rather than `FrameBuffer(lines:)`, which would silently drop the
        // content's overlays and hit-test regions.
        if buffer.width < width || buffer.lines.count < height {
            var padded = buffer.lines.map { line -> String in
                let shortfall = width - line.strippedLength
                return shortfall > 0 ? line + String.spaces(shortfall) : line
            }
            while padded.count < height {
                padded.append(String.spaces(width))
            }
            buffer = buffer.replacingLines(padded, width: width, uniformWidth: true)
        }

        // A reader that asked about another space stamps where it begins, for
        // that space's owner to find; one that asked about nothing but its own
        // size stamps nothing and costs nothing more.
        if let ask {
            ask.finishRecording(size: CellSize(width: width, height: height))
            if context.geometryCoordinator?.register(ask) == true {
                buffer.hitTestRegions.append(.geometryMarker(ask.id))
            }
        }
        return buffer
    }

    /// The context the content is built in, once the size handed to it is
    /// NOTED at this identity.
    ///
    /// The content is a function of that size, and the size is moved by
    /// layout, which no memo below keys on: a `ForEach` row that prints
    /// `proxy.size.width` is memoized by its element and offered whatever its
    /// own container offers it, so when a sidebar's `@State` narrowed the
    /// reader — a write that clears the sidebar and what contains it, and
    /// nothing inside the reader — the row was served as it was drawn at the
    /// old width. So the size is noted as an environment modifier notes the
    /// value it injects (a timeline notes its entry the same way), and a moved
    /// size drops what the cache holds below it, sizes included, once.
    ///
    /// Noted only by a render that draws. A render made to measure — a plain
    /// button's label is measured that way — can offer another size, and the
    /// note answers the later visits of a pass without comparing; noted there,
    /// it would compare that size with itself from frame to frame and never
    /// see the one drawn move. `sizeThatFits` never builds the content.
    ///
    /// The depth goes up for the content, as a timeline's does, so a reader
    /// whose content is another reader drawn at this identity notes under a
    /// slot of its own.
    ///
    /// Where the reader is is noted the same way, for the same reason: what the
    /// content was told about the spaces around it moves when something above
    /// the reader moves it, which nothing below keys on either. Evaluated after
    /// the content closure — Swift evaluates the arguments in order — so what
    /// the closure asked is known.
    private func contentContext(noting proxy: GeometryProxy, in context: RenderContext) -> RenderContext {
        var contentContext = context
        contentContext.environmentApplicationDepth += 1
        guard !context.isMeasuring, let cache = context.renderCache else { return contentContext }
        var moved = false
        if case .changed = cache.noteAppliedEnvironment(
            proxy.size, identity: context.identity, keyPath: \GeometryProxy.size,
            depth: context.environmentApplicationDepth)
        {
            moved = true
        }
        if let told = proxy.ask?.toldAnswers, !told.isEmpty,
            case .changed = cache.noteAppliedEnvironment(
                told, identity: context.identity, keyPath: \GeometryProxy.toldAnswers,
                depth: context.environmentApplicationDepth)
        {
            moved = true
        }
        if moved { cache.clearAffected(by: context.identity) }
        return contentContext
    }
}
