//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationZoom.swift
//
//  The zoom navigation transition, as a NavigationStack draws it: a reveal of
//  the pushed screen through a rectangle growing from its source's frame, and
//  the same rectangle shrinking back into the source when it is popped.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitStyling
import TUIkitView

/// What a ``NavigationStack`` keeps from frame to frame to zoom a screen in
/// and out (``ZoomNavigationTransition``).
struct NavigationZoomState {
    /// A zoom being drawn.
    struct Running {
        /// Revealing a pushed screen, or folding a popped one back away.
        enum Direction {
            case reveal, conceal
        }

        let direction: Direction
        /// The source's group.
        let key: MatchedGeometryKey
        /// The source's frame in the global space: where it was found as the
        /// zoom started, and where it is found as it runs.
        var source: CellRect
        /// The picture that holds still while the other is uncovered or
        /// covered: the screen pushed over, or the screen popped.
        let still: FrameBuffer
        /// The source's background, drawn in the rectangle.
        let background: Color?
        /// Its slot in the animation store.
        let epoch: Int
    }

    /// Each transition source's configuration, as it last drew.
    var configurations: [MatchedGeometryKey: _ResolvedMatchedTransitionSourceConfiguration] = [:]
    /// The depth the stack drew last.
    var depth = 0
    /// The zoom each depth's screen declared while it was on top.
    var declared: [Int: MatchedGeometryKey] = [:]
    /// Where each depth's source was, in the global space, when it was pushed:
    /// what it starts to fold back into when nothing has found the source
    /// since — a source on a root the screen covered, which the root drew
    /// off-screen and no one found.
    var sources: [Int: CellRect] = [:]
    /// What the stack drew last, unzoomed: what a zoom starting now holds
    /// still.
    var picture: FrameBuffer?
    var running: Running?
    var epoch = 0

    /// Whether the stack must know where it is this frame: it is zooming, or
    /// may start to, the path having changed.
    func needsOrigin(depth: Int) -> Bool {
        running != nil || depth != self.depth
    }
}

/// The type a zoom's progress is kept under in the animation store.
private enum NavigationZoomAnimation {}

extension NavigationCoordinator {
    /// Notes the configuration of the transition source of `key`, as it draws.
    func noteTransitionSource(_ key: MatchedGeometryKey, configuration: _ResolvedMatchedTransitionSourceConfiguration) {
        zoom.configurations[key] = configuration
    }

    /// `buffer` — what the stack draws at `depth` this frame — zoomed, if a
    /// zoom is running or the path's change starts one.
    ///
    /// - Parameters:
    ///   - buffer: The stack's drawing, unzoomed.
    ///   - depth: How many screens are pushed.
    ///   - declared: The zoom the screen on top declared, if any.
    ///   - origin: The stack's top-leading corner in the global space, if
    ///     known — asked only while a zoom is drawn.
    ///   - context: The stack's context.
    /// - Returns: The drawing to show.
    func zoomed(
        _ buffer: FrameBuffer, depth: Int, declared: MatchedGeometryKey?, origin: () -> CellPoint?,
        context: RenderContext
    ) -> FrameBuffer {
        guard !context.isMeasuring, let storage = context.stateStorage else { return buffer }
        let started = startZoom(depth: depth, declared: declared, context: context)
        zoom.picture = buffer
        guard var running = zoom.running else { return buffer }
        // Where the source is found now, as it runs: a screen popped back to
        // a root that moved its source while covering it started to fold
        // into where the source was pushed from, which nothing found since.
        // Its first frame is the whole stack, so the rectangle it folds into
        // is where the root finds the source from its second frame on.
        if let found = context.geometryCoordinator?.matchedGeometry.source(
            of: running.key, excluding: context.identity)?.frame, found != running.source
        {
            running.source = found
            zoom.running = running
        }
        let key = AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(NavigationZoomAnimation.self), slot: running.epoch)
        let now = context.environment.frameNowNanos
        let phase = storage.animations.arrivalPhase(
            for: key, animation: started ? Self.zoomAnimation(context) : nil, nowNanos: now, isMeasuring: false)
        guard storage.animations.isAnimating(at: key, nowNanos: now) else {
            zoom.running = nil
            return buffer
        }
        // Drawn this frame from where the stack's owner predicts it; a wrong
        // prediction is corrected by the root, as a reader's is.
        guard let origin = origin() else { return buffer }
        let source = CellRect(
            x: running.source.x - origin.x, y: running.source.y - origin.y,
            width: running.source.width, height: running.source.height)
        let whole = CellRect(
            x: 0, y: 0, width: max(buffer.width, running.still.width), height: max(buffer.height, running.still.height))
        let present = running.direction == .reveal ? phase : 1 - phase
        let rect = MatchedEdgeOffsets(from: source, to: whole).applied(to: whole, remaining: 1 - present)
        let fill = running.background.map { colour in
            TUIkitView.renderToBuffer(
                colour,
                context: context.withChildIdentity(erasedType: NavigationZoomAnimation.self, index: 0)
                    .withAvailableSize(width: max(0, rect.width), height: max(0, rect.height)))
        }
        switch running.direction {
        case .reveal:
            return Self.revealing(buffer, through: rect, over: running.still, fill: fill)
        case .conceal:
            return Self.revealing(running.still, through: rect, over: buffer, fill: fill, keepsBase: true)
        }
    }

    /// Starts a zoom if the path's change calls for one: a push of a screen
    /// that declared one whose source was found, or a pop of a screen that
    /// did. Answers whether one started.
    private func startZoom(depth: Int, declared: MatchedGeometryKey?, context: RenderContext) -> Bool {
        let previousDepth = zoom.depth
        zoom.depth = depth
        zoom.declared[depth] = declared
        defer {
            if depth < previousDepth {
                zoom.declared = zoom.declared.filter { $0.key <= depth }
                zoom.sources = zoom.sources.filter { $0.key <= depth }
            }
        }
        guard depth != previousDepth, let still = zoom.picture else { return false }
        let pushed = depth > previousDepth
        guard let key = pushed ? declared : zoom.declared[previousDepth] else { return false }
        let found = context.geometryCoordinator?.matchedGeometry.source(of: key, excluding: context.identity)?.frame
        guard let source = found ?? (pushed ? nil : zoom.sources[previousDepth]) else { return false }
        if pushed { zoom.sources[depth] = source }
        zoom.epoch += 1
        zoom.running = NavigationZoomState.Running(
            direction: pushed ? .reveal : .conceal, key: key, source: source, still: still,
            background: zoom.configurations[key]?.background, epoch: zoom.epoch)
        return true
    }

    /// How a zoom the path's change starts plays: the change's animation, or
    /// the default one where it brought none — a push animates in SwiftUI
    /// whatever the code asked for — and not at all where the transaction
    /// disables animations, the frame cannot animate, or motion is reduced (a
    /// zoom moves in X and Y, owner decision A-D3M-1).
    private static func zoomAnimation(_ context: RenderContext) -> Animation? {
        let environment = context.environment
        let transaction = environment.transaction
        guard environment.animationFrame.canAnimate, !environment.accessibilityReduceMotion,
            !transaction.disablesAnimations
        else { return nil }
        return transaction.animation ?? .default
    }

    /// `top` uncovered through `rect` over `base`, with `fill` behind it: the
    /// cells of `top` inside the rectangle, its hit regions and runs cut with
    /// them, over `base`'s lines. The base is a picture — its regions, runs and
    /// layers left behind — unless `keepsBase`, where it is the live drawing.
    ///
    /// The result is as large as the larger of the two: a root that hugs its
    /// rows is shorter than a pushed screen, which fills the stack, and the
    /// screen folding back into it is drawn whole until the rectangle has
    /// left the rows the root does not have. The stack takes the root's size
    /// once the zoom is over, as it would have at once without one.
    static func revealing(
        _ top: FrameBuffer, through rect: CellRect, over base: FrameBuffer, fill: FrameBuffer?,
        keepsBase: Bool = false
    ) -> FrameBuffer {
        let size = CellSize(width: max(top.width, base.width), height: max(top.height, base.height))
        var result = keepsBase ? padded(base, to: size) : picture(base, fittedTo: size)
        if let fill, rect.width > 0, rect.height > 0 {
            result = result.composited(with: FrameBuffer(lines: fill.lines), at: (rect.x, rect.y))
        }
        let layer = OverlayLayer(offsetX: 0, offsetY: 0, content: keepsBase ? picture(top, fittedTo: size) : top)
        let visible = CellRect(
            x: max(0, rect.x), y: max(0, rect.y),
            width: min(rect.maxX, size.width) - max(0, rect.x), height: min(rect.maxY, size.height) - max(0, rect.y))
        guard visible.width > 0, visible.height > 0,
            let part = layer.cropped(x: visible.x, y: visible.y, width: visible.width, height: visible.height)
        else { return result }
        return result.composited(with: part.content, at: (part.offsetX, part.offsetY))
    }

    /// `buffer`, its payloads with it, padded with blank cells to `size`.
    private static func padded(_ buffer: FrameBuffer, to size: CellSize) -> FrameBuffer {
        guard buffer.width < size.width || buffer.height < size.height else { return buffer }
        let blank = String(repeating: " ", count: max(0, size.width))
        let lines = (0..<size.height).map { row in
            row < buffer.lines.count ? buffer.lines[row].padToVisibleWidth(size.width) : blank
        }
        return buffer.replacingLines(lines, width: size.width, uniformWidth: true)
    }

    /// `buffer`'s lines alone — a picture, its regions, runs and layers left
    /// behind — cut or padded to `size`.
    private static func picture(_ buffer: FrameBuffer, fittedTo size: CellSize) -> FrameBuffer {
        let blank = String(repeating: " ", count: max(0, size.width))
        let lines = (0..<max(0, size.height)).map { row in
            row < buffer.lines.count
                ? buffer.lines[row].ansiAwareSlice(visibleStart: 0, visibleCount: size.width)
                    .padToVisibleWidth(size.width)
                : blank
        }
        return FrameBuffer(lines: lines)
    }
}
