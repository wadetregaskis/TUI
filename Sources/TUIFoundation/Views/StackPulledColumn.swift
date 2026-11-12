//  🖥️ TUI — A Terminal UI framework for Swift
//  StackPulledColumn.swift
//
//  SCROLL-FIT's pull (design B-SCROLLFIT-11, 12, 14), for a column whose
//  children include a pulled view — a windowed lazy stack anywhere below it,
//  or another such column: `VStack { title; LazyVStack(10k) }`, two lazy
//  stacks stacked, a lazy stack of sections each with a lazy stack of its
//  own. The column keeps its position as an anchor on one child, routes the
//  request there, and fills outward from it: down from the child's end, up
//  from its top, a pulled child handed a request of its own that says where
//  its top or end falls in the viewport, every other child drawn whole. So no
//  row of a pulled child off screen is built, and nothing needs the content's
//  total height to draw: each child reached is placed against the one before
//  it, by what that one drew.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - The column the engine walks

/// One pulled frame's children, as the walk (`ScrollColumnFill.swift`) sees
/// them: measured as it reaches them, a pulled child's pitch its last known
/// end where it holds the anchor, its measure's estimate elsewhere.
@MainActor
private final class PulledColumnFrame {
    let children: ChildViewCollection
    let spacing: Int
    let state: StackWindowState
    let anchor: ScrollContentAnchor
    let proposal: ProposedViewSize
    let context: RenderContext

    /// Extents better known than a measure says them: the anchored child's,
    /// when it is pulled — its end, in its own lines, as it last drew.
    var knownHeights: [Int: Int] = [:]
    private var heights: [Int: Int] = [:]
    private var widths: [Int: Int] = [:]
    private var pulledRows: [Int: Bool] = [:]
    private var built: [Int: ChildView] = [:]
    private(set) var sawSpacer = false
    /// The requests this frame handed its pulled children, by identity.
    var handed: [ViewIdentity: ScrollContentWindow] = [:]

    init(
        children: ChildViewCollection, spacing: Int, state: StackWindowState, anchor: ScrollContentAnchor,
        proposal: ProposedViewSize, context: RenderContext
    ) {
        self.children = children
        self.spacing = spacing
        self.state = state
        self.anchor = anchor
        self.proposal = proposal
        self.context = context
    }

    func child(at ordinal: Int) -> ChildView {
        if let child = built[ordinal] { return child }
        let child = children[ordinal]
        built[ordinal] = child
        return child
    }

    /// Row `ordinal`'s height: measured, once a frame. The measure is also
    /// what files a pulled view (`PullConsumers`), so it comes before
    /// ``isPulled(_:)`` asks.
    func height(of ordinal: Int) -> Int {
        if let known = knownHeights[ordinal] { return known }
        if let height = heights[ordinal] { return height }
        let child = child(at: ordinal)
        if child.isSpacer { sawSpacer = true }
        let size = child.measure(proposal: proposal, context: context)
        // A row only measured never renders, and nothing else marks it: kept
        // alive across the pass's prune, as the anchored walk keeps its own.
        context.renderCache?.markActive(child.identity(under: context))
        heights[ordinal] = size.height
        widths[ordinal] = size.width
        state.recordMeasuredPitch(max(1, size.height) + (ordinal < children.count - 1 ? spacing : 0))
        return size.height
    }

    func measuredWidth(of ordinal: Int) -> Int {
        _ = height(of: ordinal)
        return widths[ordinal] ?? 0
    }

    /// The lines between row `ordinal` and the next: the column's spacing,
    /// after a row that drew some, as a column charges it.
    func gap(after ordinal: Int) -> Int {
        ordinal < children.count - 1 && height(of: ordinal) > 0 ? spacing : 0
    }

    func pitch(of ordinal: Int) -> Int { height(of: ordinal) + gap(after: ordinal) }

    /// Whether a pulled view sits below row `ordinal`, so that it is handed a
    /// request rather than drawn whole.
    func isPulled(_ ordinal: Int) -> Bool {
        if let pulled = pulledRows[ordinal] { return pulled }
        _ = height(of: ordinal)
        let identity = child(at: ordinal).identity(under: context)
        let pulled = context.renderCache?.pullConsumers.holdsConsumer(below: identity) ?? false
        pulledRows[ordinal] = pulled
        return pulled
    }
}

extension PulledColumnFrame: ScrollFillColumn {
    var rowCount: Int { children.count }
    /// Up to the windowing threshold the walk measures its way across a jump
    /// too: a column of a few rows, one of them a pulled stack thousands of
    /// lines tall, prices a row at an average no row is near — three one-line
    /// headers over 800 rows put a jump of 398 lines into the second header.
    var walksJumps: Bool { children.count <= _VStackCore<EmptyView>.anchoredWindowThreshold }
    func key(at ordinal: Int) -> String? { children.key(at: ordinal) }
    func firstOrdinal(forKey key: String) -> Int? { children.firstOrdinal(forKey: key) }
    var ladder: [String: Int] { state.rowOrdinalMemo }
    var estimatedPitch: Int { state.estimatedPitch(spacing: spacing) }
}

// MARK: - What the fill draws

/// One child as the fill drew it, in the column's lines.
private struct PulledPiece {
    let ordinal: Int
    /// The column line the buffer's first line falls on.
    let top: Int
    let buffer: FrameBuffer
    /// The column lines of the child's first line and past its last, when the
    /// buffer holds them: a child drawn whole always; a pulled child when its
    /// band reached its first or last row.
    let firstLine: Int?
    let endLine: Int?
    /// A pulled child's reply: where the viewport's top fell in its lines,
    /// where it ends in them, and the column line its line 0 falls on.
    let position: Int?
    let end: Int?
    let zero: Int?
}

/// Where a child is to be drawn.
private enum PulledPlace {
    /// Its top at this column line.
    case top(Int)
    /// Its end (past its last line) at this column line.
    case end(Int)
    /// It holds the anchor: the viewport's top `within` lines below its top,
    /// counted as `edge` says, for a pulled child; for a whole one, from its
    /// top.
    case anchored(within: Int, edge: PullEdge)
}

// MARK: - The pulled render

@MainActor extension _VStackCore {
    /// The window this stack places its children against as a pulled column
    /// (the file header), or `nil` when it does not: no window reaches it, or
    /// none of its children is pulled, as its own measure found
    /// (`notePulled`).
    func pulledColumnWindow(context: RenderContext) -> ScrollContentWindow? {
        guard !context.isMeasuring, let window = consumableScrollWindow(context: context), window.reply != nil,
            context.renderCache?.pullConsumers.kind(of: context.identity) == .pullsChildren
        else { return nil }
        return window
    }

    /// Files this stack as pulled, or withdraws it, once its measure has
    /// measured `children`: a column holding a pulled child places its
    /// children as one (`renderPulledColumn`), and is pulled itself by the
    /// column above it; `bandsRows` says the stack windows its own rows
    /// whatever they hold. Only in scroll content, where there is a request to
    /// pull by.
    func notePulled(bandsRows: Bool, children: () -> [ViewIdentity], context: RenderContext) {
        guard context.scrollContentOriginDepth != 0, let cache = context.renderCache else { return }
        // Only once something is filed at all, which on most pages nothing
        // ever is.
        let identities = cache.pullConsumers.isEmpty ? [] : children()
        let holdsPulled = identities.contains { cache.pullConsumers.holdsConsumer(below: $0) }
        let kind: PullConsumers.Kind? = holdsPulled ? .pullsChildren : bandsRows ? .bandsRows : nil
        cache.pullConsumers.note(context.identity, as: kind)
    }

    /// `size`, the measure of a stack over `collection`, once this stack is
    /// filed as pulled or withdrawn. A large stack bands its own rows
    /// wherever a request reaches it (``isPulledWhereItStands(context:)``),
    /// unless its rows are pulled themselves — asked of the first, which the
    /// closure that builds every row answers for all, and which the sample has
    /// measured — when it places them as a pulled column. Filed after the
    /// answer, whose sample is what files a pulled row. A small stack's
    /// uniform answer withdraws it; its exact walk files it on its own
    /// (`windowSizeThatFits`).
    func filingPulled(
        _ size: ViewSize, _ collection: ChildViewCollection, measureContext: RenderContext, context: RenderContext
    ) -> ViewSize {
        guard collection.count > Self.anchoredWindowThreshold else {
            if !pullsItsRows(context: context) { notePulled(bandsRows: false, children: { [] }, context: context) }
            return size
        }
        notePulled(
            bandsRows: isPulledWhereItStands(context: context),
            children: { [collection[0].identity(under: measureContext)] }, context: context)
        return size
    }

    /// Whether this stack places its rows as a pulled column: then it is
    /// estimated whatever its count, as it is drawn from its anchor whatever
    /// its count. Measured over every row, forty sections each sampling its
    /// own stack were measured on every frame a write cleared them.
    func pullsItsRows(context: RenderContext) -> Bool {
        context.renderCache?.pullConsumers.kind(of: context.identity) == .pullsChildren
    }

    /// `renderWindow`'s pulled column: the band, or `nil` when no request
    /// reaches this stack as one. A render that moved the pitch it estimates
    /// rows at drops the sizes kept for it, as the windowed paths' do.
    func renderPulledRows(context: RenderContext) -> FrameBuffer? {
        guard let window = pulledColumnWindow(context: context) else { return nil }
        let state = uniformWindowState(context: context)
        let before = state.measuredEstimate(spacing: spacing)
        let pulled = renderPulledColumn(window: window, context: context)
        if state.measuredEstimate(spacing: spacing) != before {
            context.renderCache?.forgetPassMeasures()
            forgetKeptSizes(context: context)
        }
        return pulled
    }

    /// A request from a column above counting from this stack's end is, under
    /// the uniform hypothesis, a line of its own: arithmetic. With none yet,
    /// it is left for the anchored walk to read. Either way a pulled request
    /// answers where the viewport's top fell (``ScrollContentReply/pulledPosition``).
    func resolveUniformPullEdge(_ window: inout ScrollContentWindow, count: Int, state: StackWindowState) {
        guard window.isPulled else { return }
        if window.edge == .end, !state.broken, let extent = state.hypothesisExtent {
            window.offset += count * (extent + spacing) - spacing
            window.edge = .top
        }
        if window.edge != .end { window.reply?.pulledPosition = window.offset }
    }

    /// Drops the sizes kept across frames for this stack and every view that
    /// holds it, when a render has moved the pitch its measure estimates
    /// rows at: a pulled stack is measured by that estimate wherever it
    /// stands, and a `ForEach` row holding one — a section of a feed — keeps
    /// its size from frame to frame as a row does (`measureValueMemoized`),
    /// so it would go on being served the height the old pitch priced.
    /// Buffers below are kept: they hold rows, which a pitch does not move.
    func forgetKeptSizes(context: RenderContext) {
        guard context.scrollContentOriginDepth != 0 else { return }
        context.renderCache?.clearAffected(by: context.identity, includingDescendants: false)
    }

    /// Draws the band of this column a pulled request asks for, outward from
    /// its anchor, and answers `window`'s reply as a windowed stack does: the
    /// band's place, the column's estimated height, and where the viewport's
    /// top fell. `nil` when it cannot (a spacer, whose share of the height only
    /// the whole column can deal), and the caller draws the column whole.
    func renderPulledColumn(window: ScrollContentWindow, context: RenderContext) -> FrameBuffer? {
        guard let reply = window.reply else { return nil }
        var childContext = context
        childContext.leaveScrollOrigin()
        // A row held by `.anchorPosition(.row(id))` is the scroll view's own
        // content's, and none below is it.
        childContext.environment.anchorPosition = nil
        let children = resolveChildViewCollection(from: content, context: childContext)
        guard !children.isEmpty else { return nil }
        let state = uniformWindowState(context: context)
        // Rows off the band leave the window, not the tree (§5h).
        context.stateStorage?.retainSubtree(context.identity)
        let width = context.availableWidth
        let frame = PulledColumnFrame(
            children: children, spacing: spacing, state: state,
            anchor: window.anchor?.claimed(byColumn: context.identity, state: state) ?? state.ownAnchor,
            proposal: ProposedViewSize(width: width, height: nil), context: childContext)

        var window = window
        let before = (ordinal: frame.anchor.ordinal, key: frame.anchor.key)
        frame.rebindAnchor(holdsRow: frame.anchor.key != nil)
        if let row = state.pulledAnchorRow, row.ordinal == frame.anchor.ordinal,
            row.key == children.key(at: row.ordinal)
        {
            frame.knownHeights[row.ordinal] = row.end
        }
        frame.enter(edgeOf: &window, estimatedEnd: frame.anchor.reportedTotal ?? frame.rowCount * frame.estimatedPitch)
        let resolvedSeek = resolvePulledSeek(frame: frame, window: &window)
        frame.advanceAnchor(to: window.offset, viewportHeight: window.viewportHeight, linesBelow: 0)
        frame.anchor.key = children.key(at: frame.anchor.ordinal)
        guard !frame.sawSpacer else { return nil }

        // Which edge a pulled anchored row counts from: its own position when
        // the anchor stayed in it, else the edge it is nearer.
        let anchored = frame.anchor.ordinal
        let stayed =
            state.pulledAnchorRow?.ordinal == anchored && before.ordinal == anchored
            && before.key == frame.anchor.key && resolvedSeek == nil
        let edge: PullEdge =
            stayed ? .position : frame.anchor.within * 2 < frame.height(of: anchored) ? .top : .end

        let drawn = fillPulled(
            frame: frame, window: window, anchoredEdge: edge, width: width, context: childContext)
        guard !frame.sawSpacer, let first = drawn.first, let last = drawn.last else { return nil }

        // The anchored row's place for the next frame: a pulled one's own
        // position and end, which the walk then moves from and across.
        if let piece = drawn.first(where: { $0.ordinal == anchored }), let position = piece.position {
            frame.anchor.within = position
            state.pulledAnchorRow = piece.end.map { (anchored, frame.anchor.key, $0) }
        } else {
            state.pulledAnchorRow = nil
        }

        var result = assemblePulled(
            drawn, frame: frame, window: window, width: width, context: childContext)
        let bandTop = first.top
        var memo: [String: Int] = [:]
        for piece in drawn { if let key = children.key(at: piece.ordinal) { memo[key] = piece.ordinal } }
        state.rowOrdinalMemo = memo

        // The column's height, estimated past what the band reached: the rows
        // below priced at their measures, eager or lazy alike — an eager
        // column measured every one anyway, and a lazy one prices those it
        // never reached at the running pitch.
        let lastEnd = last.endLine ?? (last.zero.flatMap { zero in last.end.map { zero + $0 } } ?? last.top + last.buffer.height)
        var total = max(bandTop + result.height, lastEnd)
        if last.ordinal < children.count - 1 {
            total += frame.gap(after: last.ordinal)
            let after = (last.ordinal + 1)..<children.count
            total +=
                overflow == .clip
                ? after.reduce(0) { $0 + frame.pitch(of: $1) }
                : after.count * frame.estimatedPitch
        }
        drawOffBand(drawn, frame: frame, window: window, into: &result, bandTop: bandTop, width: width, context: childContext)
        state.pulledRequests = frame.handed
        frame.anchor.reportedTotal = total
        frame.anchor.derivedOffset = window.offset
        reply.sliceOriginY = bandTop
        reply.sliceTotalHeight = total
        reply.sliceTotalIsEstimate = true
        reply.sliceHoldsFirstRow = first.ordinal == 0 && first.firstLine != nil
        reply.sliceHoldsLastRow = last.ordinal == children.count - 1 && last.endLine != nil
        reply.pulledPosition = window.offset
        reply.reportResolvedOffset(resolvedSeek, isHold: false)
        if let at = window.reportsIDAt {
            let sampleY = window.sampleY(at: at, contentBelow: !reply.sliceHoldsLastRow)
            let sampled = drawn.last { $0.top <= sampleY } ?? first
            reply.anchorID = children.reportedID(
                at: sampled.ordinal, content: content, sectionsWhole: context.keepsSectionsWhole)
        }
        ScrollContentReply.journal(from: context)
        return result
    }

    /// A pending `scrollTo` naming one of this column's own rows: the row
    /// becomes the anchor, on the line the request's alignment puts it, and
    /// the offset it was moved to — the rows above it priced at the running
    /// pitch — is returned for the scroll view to adopt. `nil` when nothing
    /// is sought or no row of this column holds the key.
    private func resolvePulledSeek(frame: PulledColumnFrame, window: inout ScrollContentWindow) -> Int? {
        guard let seek = window.seek else { return nil }
        window.seek = nil
        guard let ordinal = resolveOrdinal(forKey: seek.key, children: frame.children, state: frame.state)
        else { return nil }
        let rowHeight = frame.height(of: ordinal)
        let line: Int
        if let anchor = seek.anchor {
            let slack = window.viewportHeight - seek.topInset - seek.bottomInset - rowHeight
            line = seek.topInset + Int((Double(slack) * anchor.y).rounded())
        } else {
            line = ordinal < frame.anchor.ordinal
                ? seek.topInset
                : max(seek.topInset, window.viewportHeight - seek.bottomInset - rowHeight)
        }
        let top = ordinal * frame.estimatedPitch
        frame.anchor.ordinal = ordinal
        frame.anchor.key = frame.key(at: ordinal)
        let offset = max(0, top - line)
        frame.anchor.within = offset - top
        frame.anchor.derivedOffset = offset
        window.offset = offset
        return offset
    }

    /// The fill: the anchored row, then outward — down from each row's end
    /// while the viewport (and one row past it) wants lines, up from each
    /// row's top while the viewport's top lies above it, and one whole row
    /// past it as the margin a directional move steps into.
    private func fillPulled(
        frame: PulledColumnFrame, window: ScrollContentWindow, anchoredEdge: PullEdge, width: Int,
        context: RenderContext
    ) -> [PulledPiece] {
        let anchored = frame.anchor.ordinal
        let top = window.offset
        let bottom = top + window.viewportHeight
        let anchorPiece = drawPulledRow(
            anchored, at: .anchored(within: frame.anchor.within, edge: anchoredEdge),
            frame: frame, window: window, width: width, context: context)
        var below: [PulledPiece] = []
        var nextTop = anchorPiece.endLine.map { $0 + frame.gap(after: anchored) }
        var ordinal = anchored + 1
        while let y = nextTop, ordinal < frame.rowCount {
            let isMargin = y >= bottom
            let piece = drawPulledRow(ordinal, at: .top(y), frame: frame, window: window, width: width, context: context)
            below.append(piece)
            if isMargin { break }
            nextTop = piece.endLine.map { $0 + frame.gap(after: ordinal) }
            ordinal += 1
        }
        var above: [PulledPiece] = []
        ordinal = anchored - 1
        var nextEnd = anchorPiece.firstLine.map { $0 - (ordinal >= 0 ? frame.gap(after: ordinal) : 0) }
        while let end = nextEnd, ordinal >= 0 {
            let isMargin = end <= top
            // A margin row above is drawn whole or not at all: a pulled one
            // would be asked only for lines no one sees.
            if isMargin, frame.isPulled(ordinal) { break }
            let piece = drawPulledRow(ordinal, at: .end(end), frame: frame, window: window, width: width, context: context)
            above.append(piece)
            if isMargin { break }
            nextEnd = piece.firstLine.map { $0 - (ordinal > 0 ? frame.gap(after: ordinal - 1) : 0) }
            ordinal -= 1
        }
        return above.reversed() + [anchorPiece] + below
    }

    /// Draws row `ordinal` at `place`: whole, or — when it is pulled — handed a
    /// request in its own lines, and placed by what it answers.
    private func drawPulledRow(
        _ ordinal: Int, at place: PulledPlace, frame: PulledColumnFrame, window: ScrollContentWindow,
        width: Int, context: RenderContext
    ) -> PulledPiece {
        let child = frame.child(at: ordinal)
        let height = frame.height(of: ordinal)
        let viewportTop = window.offset
        guard frame.isPulled(ordinal) else {
            let rowTop: Int
            switch place {
            case .top(let y): rowTop = y
            case .end(let y): rowTop = y - height
            case .anchored(let within, _): rowTop = viewportTop - within
            }
            let buffer = child.render(width: width, height: height, context: context)
                .horizontallyAligned(toWidth: width, alignment: alignment)
            return PulledPiece(
                ordinal: ordinal, top: rowTop, buffer: buffer, firstLine: rowTop, endLine: rowTop + height,
                position: nil, end: nil, zero: nil)
        }
        var request = ScrollContentWindow(
            offset: 0, viewportHeight: window.viewportHeight,
            contentIdentity: child.identity(under: context), reply: ScrollContentReply())
        request.isPulled = true
        switch place {
        case .top(let y):
            request.offset = viewportTop - y
            request.edge = .top
        case .end(let y):
            request.offset = viewportTop - y
            request.edge = .end
        case .anchored(let within, let edge):
            request.edge = edge
            request.offset = edge == .end ? within - height : within
        }
        let rowContext = handing(request, to: request.contentIdentity!, frame: frame, context: context)
        let canvas = max(context.availableHeight, height, window.viewportHeight * 4)
        let buffer = child.render(width: width, height: canvas, context: rowContext)
            .horizontallyAligned(toWidth: width, alignment: alignment)
        let answer = request.reply!
        guard let origin = answer.sliceOriginY, let end = answer.sliceTotalHeight else {
            // Drawn whole after all: placed as a whole row is.
            let rowTop: Int
            switch place {
            case .top(let y): rowTop = y
            case .end(let y): rowTop = y - buffer.height
            case .anchored(let within, _): rowTop = viewportTop - within
            }
            return PulledPiece(
                ordinal: ordinal, top: rowTop, buffer: buffer, firstLine: rowTop, endLine: rowTop + buffer.height,
                position: nil, end: nil, zero: nil)
        }
        // The column line of the child's line 0.
        let zero: Int
        let position = answer.pulledPosition ?? request.offset
        switch place {
        case .top(let y): zero = y
        case .end(let y): zero = y - end
        case .anchored: zero = viewportTop - position
        }
        let pieceTop = zero + origin
        return PulledPiece(
            ordinal: ordinal, top: pieceTop, buffer: buffer,
            firstLine: answer.sliceHoldsFirstRow ? pieceTop : nil,
            endLine: answer.sliceHoldsLastRow ? pieceTop + buffer.height : nil,
            position: position, end: end, zero: zero)
    }

    /// `context` with `request` in it for the pulled child at `identity`.
    ///
    /// A memo between this column and what reads the request keys on no part
    /// of it — a `ForEach` row's trusts the environment its subtree noted, and
    /// a request is noted by no one — so a child handed a request other than
    /// the last frame's has its memo entries dropped, buffers only: a request
    /// moves which of the child's lines are drawn, never its size. One handed
    /// the same request (an idle frame, a child off the band) keeps them, and
    /// its reply is said again from the memo's journal.
    private func handing(
        _ request: ScrollContentWindow, to identity: ViewIdentity, frame: PulledColumnFrame, context: RenderContext
    ) -> RenderContext {
        if frame.state.pulledRequests[identity] != request {
            context.renderCache?.clearAffected(by: identity, keepingSizes: true)
        }
        frame.handed[identity] = request
        var rowContext = context
        rowContext.environment.scrollContentWindow = request
        return rowContext
    }

    /// The band: the pieces in row order, one below another. A piece placed
    /// above the end of the one before — an extent a child refined while it
    /// drew — is moved down to it, as the anchored window moves a row.
    private func assemblePulled(
        _ drawn: [PulledPiece], frame: PulledColumnFrame, window: ScrollContentWindow, width: Int,
        context: RenderContext
    ) -> FrameBuffer {
        var result = FrameBuffer()
        guard let first = drawn.first else { return result }
        var cursor = first.top
        for piece in drawn {
            if piece.top > cursor {
                result.appendVertically(FrameBuffer(emptyWithHeight: piece.top - cursor), spacing: 0)
                cursor = piece.top
            }
            result.appendVertically(piece.buffer, spacing: 0)
            cursor += piece.buffer.height
        }
        return result
    }

    /// The children the band leaves out that are drawn all the same, for
    /// their regions and their places in the focus ring, with no lines: every
    /// one of an eager column's (B-SCROLLFIT-14: its children exist as
    /// SwiftUI's do), and a lazy column's focused row and pending focus
    /// target. A pulled one is handed a request that does not move while it
    /// stays off the band, so its memo holds (B-SCROLLFIT-2).
    private func drawOffBand(
        _ drawn: [PulledPiece], frame: PulledColumnFrame, window: ScrollContentWindow, into result: inout FrameBuffer,
        bandTop: Int, width: Int, context: RenderContext
    ) {
        guard let first = drawn.first, let last = drawn.last else { return }
        var ordinals: [Int]
        if overflow == .clip {
            ordinals = Array(0..<first.ordinal) + Array((last.ordinal + 1)..<frame.rowCount)
        } else {
            let focus = context.environment.focusManager
            ordinals = [focus?.currentFocusedID, focus?.pendingFocusID].compactMap {
                targetOrdinal(for: $0, children: frame.children, state: frame.state, context: context)
            }
            ordinals = Array(Set(ordinals)).filter { $0 < first.ordinal || $0 > last.ordinal }.sorted()
        }
        guard !ordinals.isEmpty else { return }
        let bandHeight = result.height
        for ordinal in ordinals {
            let isAbove = ordinal < first.ordinal
            let estimate =
                isAbove
                ? first.top - (first.ordinal - ordinal) * frame.estimatedPitch
                : bandTop + bandHeight + (ordinal - last.ordinal - 1) * frame.estimatedPitch
            let drawnRow: FrameBuffer
            if frame.isPulled(ordinal) {
                var request = ScrollContentWindow(
                    offset: -window.viewportHeight, viewportHeight: window.viewportHeight,
                    contentIdentity: frame.child(at: ordinal).identity(under: context), reply: ScrollContentReply())
                request.isPulled = true
                request.edge = .top
                let rowContext = handing(request, to: request.contentIdentity!, frame: frame, context: context)
                drawnRow = frame.child(at: ordinal).render(
                    width: width, height: max(context.availableHeight, window.viewportHeight * 4), context: rowContext)
            } else {
                drawnRow = drawOffBandRow(
                    frame.child(at: ordinal), width: width, viewportHeight: window.viewportHeight, context: context)
            }
            let bandLocalY =
                isAbove ? min(estimate - bandTop, -window.viewportHeight) : max(estimate - bandTop, bandHeight)
            graftOffBandRow(drawnRow, into: &result, bandLocalY: bandLocalY)
        }
    }
}
