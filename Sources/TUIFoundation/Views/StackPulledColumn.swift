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
    /// Whether a pulled child resolved the seek it was handed: its position
    /// is where the seek put the viewport's top in its lines.
    var resolvedSeek = false

    /// The piece `delta` lines further down the column.
    func shifted(by delta: Int) -> Self {
        var piece = Self(
            ordinal: ordinal, top: top + delta, buffer: buffer, firstLine: firstLine.map { $0 + delta },
            endLine: endLine.map { $0 + delta }, position: position, end: end, zero: zero.map { $0 + delta })
        piece.resolvedSeek = resolvedSeek
        return piece
    }
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
        // A request counted from this column's top or end — the column above
        // fills to it from a neighbour, or has just moved its anchor into it —
        // places the anchor afresh, whatever this column remembers of it.
        let enteredAtAnEdge = window.edge != .position
        frame.enter(edgeOf: &window, estimatedEnd: frame.anchor.reportedTotal ?? frame.rowCount * frame.estimatedPitch)
        // A seek moves from the rows on screen, read from the anchor, so the
        // anchor is walked to this frame's offset first, as the anchored
        // window walks it (`renderAnchoredWindow`).
        if window.seek != nil {
            frame.advanceAnchor(to: window.offset, viewportHeight: window.viewportHeight, linesBelow: 0)
        }
        let seeking = resolvePulledSeek(frame: frame, window: &window, width: width)
        // A row handed a seek keeps the anchor wherever the viewport's top is
        // in it until it answers: the walk would move a place above its top
        // onto the row above, which the seek never reaches.
        if seeking?.handed == nil {
            frame.advanceAnchor(to: window.offset, viewportHeight: window.viewportHeight, linesBelow: 0)
        }
        frame.anchor.key = children.key(at: frame.anchor.ordinal)
        guard !frame.sawSpacer else { return nil }

        // Which edge a pulled anchored row counts from: its own position when
        // the anchor stayed in it, else the edge it is nearer. Not after an
        // entry at an edge, which moved the anchor even where it names the row
        // it named before: a column in a row of an outer one, entered from
        // below, handed its last row the position that row had frames ago.
        let anchored = frame.anchor.ordinal
        let stayed =
            !enteredAtAnEdge && state.pulledAnchorRow?.ordinal == anchored && before.ordinal == anchored
            && before.key == frame.anchor.key && seeking == nil
        let edge: PullEdge =
            seeking?.handedEdge
            ?? (stayed ? .position : frame.anchor.within * 2 < frame.height(of: anchored) ? .top : .end)

        frame.focusMark = context.environment.focusManager.map { ($0, $0.registrationMark()) }
        var drawn = fillPulled(
            frame: frame, window: window, anchoredEdge: edge, seek: seeking?.handed, width: width,
            context: childContext)
        guard !frame.sawSpacer, !drawn.isEmpty else { return nil }
        let resolvedSeek = settle(seeking, of: anchored, drawn: &drawn, window: &window)
        guard let first = drawn.first, let last = drawn.last else { return nil }

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

    /// The offset this frame's seek moved the column to, for the scroll view
    /// to adopt, or `nil`. A seek the anchored row resolved moved the
    /// viewport's top in it from where it was handed to where the row answers:
    /// the column's offset moves with it, and so does every piece, each placed
    /// against that row, so the rows around it keep their places in the
    /// column's lines.
    private func settle(
        _ seeking: PulledSeek?, of anchored: Int, drawn: inout [PulledPiece], window: inout ScrollContentWindow
    ) -> Int? {
        switch seeking {
        case .moved(let offset): return offset
        case .handed(_, let top, _):
            guard let piece = drawn.first(where: { $0.ordinal == anchored }), piece.resolvedSeek,
                let position = piece.position
            else { return nil }
            let delta = top + position - window.offset
            window.offset += delta
            drawn = drawn.map { $0.shifted(by: delta) }
            return window.offset
        case nil: return nil
        }
    }

    /// The fill: the anchored row, then outward — down from each row's end
    /// while the viewport (and one row past it) wants lines, up from each
    /// row's top while the viewport's top lies above it, and one whole row
    /// past it as the margin a directional move steps into.
    private func fillPulled(
        frame: PulledColumnFrame, window: ScrollContentWindow, anchoredEdge: PullEdge, seek: HandedSeek?,
        width: Int, context: RenderContext
    ) -> [PulledPiece] {
        let anchored = frame.anchor.ordinal
        let top = window.offset
        let bottom = top + window.viewportHeight
        let anchorPiece = drawPulledRow(
            anchored, at: .anchored(within: frame.anchor.within, edge: anchoredEdge), seek: seek,
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
            let piece = frame.drawingAbove {
                drawPulledRow(ordinal, at: .end(end), frame: frame, window: window, width: width, context: context)
            }
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
        _ ordinal: Int, at place: PulledPlace, seek: HandedSeek? = nil, frame: PulledColumnFrame,
        window: ScrollContentWindow, width: Int, context: RenderContext
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
        if let seek {
            request.seek = seek.request
            request.linesAbove = seek.linesAbove
            request.linesBelow = seek.linesBelow
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
        var piece = PulledPiece(
            ordinal: ordinal, top: pieceTop, buffer: buffer,
            firstLine: answer.sliceHoldsFirstRow ? pieceTop : nil,
            endLine: answer.sliceHoldsLastRow ? pieceTop + buffer.height : nil,
            position: position, end: end, zero: zero)
        piece.resolvedSeek = seek != nil && answer.seekResolvedOffset != nil
        return piece
    }

    /// `context` with `request` in it for the pulled child at `identity`
    /// (``RenderContext/handingPulled(_:to:last:)``), remembered as handed
    /// this frame.
    private func handing(
        _ request: ScrollContentWindow, to identity: ViewIdentity, frame: PulledColumnFrame, context: RenderContext
    ) -> RenderContext {
        frame.handed[identity] = request
        return context.handingPulled(request, to: identity, last: frame.state.pulledRequests[identity])
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
        // Those above, nearest first, each filed ahead of the one before in
        // the focus ring: so they run in order, ahead of the band.
        let above = ordinals.filter { $0 < first.ordinal }
        for ordinal in above.reversed() + ordinals.filter({ $0 > last.ordinal }) {
            let isAbove = ordinal < first.ordinal
            let estimate =
                isAbove
                ? first.top - (first.ordinal - ordinal) * frame.estimatedPitch
                : bandTop + bandHeight + (ordinal - last.ordinal - 1) * frame.estimatedPitch
            let drawnRow: FrameBuffer
            if isAbove {
                drawnRow = frame.drawingAbove {
                    drawOffBandChild(ordinal, frame: frame, window: window, width: width, context: context)
                }
            } else {
                drawnRow = drawOffBandChild(ordinal, frame: frame, window: window, width: width, context: context)
            }
            let bandLocalY =
                isAbove ? min(estimate - bandTop, -window.viewportHeight) : max(estimate - bandTop, bandHeight)
            graftOffBandRow(drawnRow, into: &result, bandLocalY: bandLocalY)
        }
    }

    /// Off-band child `ordinal`, drawn for its regions and its places in the
    /// focus ring: a pulled one handed a request that stays still while it is
    /// off the band, any other drawn as an off-band row is.
    private func drawOffBandChild(
        _ ordinal: Int, frame: PulledColumnFrame, window: ScrollContentWindow, width: Int, context: RenderContext
    ) -> FrameBuffer {
        guard frame.isPulled(ordinal) else {
            return drawOffBandRow(
                frame.child(at: ordinal), width: width, viewportHeight: window.viewportHeight, context: context)
        }
        var request = ScrollContentWindow(
            offset: -window.viewportHeight, viewportHeight: window.viewportHeight,
            contentIdentity: frame.child(at: ordinal).identity(under: context), reply: ScrollContentReply())
        request.isPulled = true
        request.edge = .top
        let rowContext = handing(request, to: request.contentIdentity!, frame: frame, context: context)
        return frame.child(at: ordinal).render(
            width: width, height: max(context.availableHeight, window.viewportHeight * 4), context: rowContext)
    }
}
