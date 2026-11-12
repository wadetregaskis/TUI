//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollParallelFill.swift
//
//  SCROLL-FIT's parallel shape (design B-SCROLLFIT-12): a container that
//  places its children side by side or over one another — an `HStack`, a
//  `ZStack` — handed a scroll view's request, hands each pulled child the
//  same request moved by the child's place in the container, draws every
//  other child whole, and keeps of each only the lines of the band.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// One child of a parallel container, as the fill places it.
struct PulledParallelChild {
    /// The child's identity, where a request handed to it is addressed.
    let identity: ViewIdentity
    /// Its top in the container's lines, where the alignment puts it at its
    /// measured height.
    let y: Int
    /// Its measured height: a pulled child's is its estimate.
    let height: Int
    /// Whether a pulled view sits below it (`PullConsumers`).
    let isPulled: Bool
}

/// What a parallel container remembers of its pulled children from one frame
/// to the next: its own position as it last answered it, each pulled child's,
/// and the request each was handed.
@MainActor
final class PulledParallelState {
    var position: Int?
    var positions: [ViewIdentity: Int] = [:]
    var requests: [ViewIdentity: ScrollContentWindow] = [:]
}

/// A pulled child's answer, in its own lines.
private struct PulledParallelAnswer {
    let buffer: FrameBuffer
    /// Where its band starts, where it ends (its total), and where the
    /// viewport's top fell.
    let origin: Int
    let total: Int
    let position: Int
    let holdsFirst: Bool
    let holdsLast: Bool
    /// Whether it resolved the seek it was handed.
    var resolvedSeek = false
}

/// One child's part of a parallel container's band: what it draws there,
/// cut to the band, and how far down the band that starts.
struct PulledParallelPiece {
    let buffer: FrameBuffer
    let y: Int
    let bandHeight: Int

    /// The piece as a column the band's height, blank above and below it:
    /// what a row lays beside its neighbours. Layered — a z-order, a glide —
    /// the piece is drawn at `y` as it is, so its blanks cover nothing.
    var column: FrameBuffer {
        var column = y > 0 ? FrameBuffer(emptyWithWidth: buffer.width, height: y) : FrameBuffer()
        column.appendVertically(buffer, spacing: 0)
        if column.height < bandHeight {
            column.appendVertically(
                FrameBuffer(emptyWithWidth: buffer.width, height: bandHeight - column.height), spacing: 0)
        }
        return column
    }
}

@MainActor
enum PulledParallel {
    /// The band `window` asks of a container whose children stand side by
    /// side or over one another, as one piece per child (`nil` for a child
    /// that draws nothing there) and the band's height; `window`'s reply
    /// answered as a windowed stack's is. `nil` when
    /// no child is pulled, or the tallest pulled one drew itself whole, and
    /// the container draws its children whole.
    ///
    /// Each pulled child is handed the request moved by its place in the
    /// container: from the container's top or end by its top or end, or —
    /// the container's own position carried on from the last frame — its own
    /// position moved by the same delta, so it walks the delta in its own
    /// lines. The container's lines are its tallest pulled child's (the lead),
    /// moved down to the child's place: the band is the lead's band, the
    /// position the lead's, and every other child is placed against it — a
    /// pulled one by where the viewport's top fell in it, one drawn whole by
    /// its place — and cut to the band. When the lead's band holds its first
    /// or its last row, the band reaches the container's top or end too.
    ///
    /// `render` draws child `index` in a context and a height.
    static func fill(
        window: ScrollContentWindow, children: [PulledParallelChild], state: PulledParallelState,
        context: RenderContext, render: (Int, RenderContext, Int) -> FrameBuffer
    ) -> (pieces: [PulledParallelPiece?], height: Int)? {
        guard let reply = window.reply,
            let lead = children.indices.filter({ children[$0].isPulled }).max(by: {
                children[$0].height < children[$1].height
            })
        else { return nil }
        let rowHeight = children.map { $0.y + $0.height }.max() ?? 0
        let delta = window.edge == .position ? state.position.map { window.offset - $0 } : nil
        var handed: [ViewIdentity: ScrollContentWindow] = [:]
        var answers: [Int: PulledParallelAnswer] = [:]
        var wholes: [Int: FrameBuffer] = [:]
        let canvas = max(context.availableHeight, window.viewportHeight * 4)
        /// Draws pulled child `index` handed `request`, answering into `answers`.
        func drawPulled(_ index: Int, _ request: ScrollContentWindow) {
            let child = children[index]
            handed[child.identity] = request
            let childContext = context.handingPulled(
                request, to: child.identity, last: state.requests[child.identity])
            let buffer = render(index, childContext, max(canvas, child.height))
            guard let answer = request.reply, let origin = answer.sliceOriginY, let total = answer.sliceTotalHeight
            else {
                answers[index] = nil
                wholes[index] = buffer
                return
            }
            answers[index] = PulledParallelAnswer(
                buffer: buffer, origin: origin, total: total, position: answer.pulledPosition ?? request.offset,
                holdsFirst: answer.sliceHoldsFirstRow, holdsLast: answer.sliceHoldsLastRow,
                resolvedSeek: request.seek != nil && answer.seekResolvedOffset != nil)
        }
        for (index, child) in children.enumerated() {
            guard child.isPulled else {
                wholes[index] = render(index, context, child.height)
                continue
            }
            var request = pulledRequest(for: child, window: window)
            if let delta, let last = state.positions[child.identity] {
                request.edge = .position
                request.offset = last + delta
            } else if window.edge == .end {
                request.edge = .end
                request.offset = window.offset + (rowHeight - child.y - child.height)
            } else {
                request.edge = .top
                request.offset = window.offset - child.y
            }
            handSeek(of: window, to: &request, child: child, isLead: index == lead, rowHeight: rowHeight)
            drawPulled(index, request)
        }
        guard let leading = answers[lead] else { return nil }

        // The lead's line 0 in the container's lines: its first row at the
        // child's top when its band holds that row, else where its own lines
        // put it.
        let leadZero = children[lead].y - (leading.holdsFirst ? leading.origin : 0)
        let position = leading.position + leadZero
        // A seek the lead resolved moved the container's lines under every
        // other pulled child, each handed its place before the lead answered:
        // handed it again, at its place below the container's new top.
        if leading.resolvedSeek {
            let others = children.indices.filter { $0 != lead && answers[$0] != nil }
            others.forEach { index in
                var request = pulledRequest(for: children[index], window: window)
                request.edge = .top
                request.offset = position - children[index].y
                drawPulled(index, request)
            }
            reply.reportResolvedOffset(position, isHold: false)
        }
        var top = leadZero + leading.origin
        var bottom = top + leading.buffer.height
        var total = leading.holdsLast ? bottom : leadZero + leading.total
        var tops: [Int: Int] = [:]
        for index in children.indices {
            if let answer = answers[index] {
                let zero = index == lead ? leadZero : position - answer.position
                tops[index] = zero + answer.origin
                if index != lead { total = max(total, zero + answer.total) }
            } else if wholes[index] != nil {
                tops[index] = children[index].y
                total = max(total, children[index].y + children[index].height)
            }
        }
        if leading.holdsFirst { top = min(top, 0) }
        if leading.holdsLast { bottom = max(bottom, total) }

        let bandHeight = max(0, bottom - top)
        var pieces: [PulledParallelPiece?] = Array(repeating: nil, count: children.count)
        for index in children.indices {
            guard let buffer = answers[index]?.buffer ?? wholes[index], let pieceTop = tops[index] else { continue }
            let y = pieceTop - top
            pieces[index] = PulledParallelPiece(
                buffer: buffer.lines(in: max(0, -y)..<max(0, bandHeight - y)), y: max(0, y), bandHeight: bandHeight)
        }

        state.position = position
        state.positions = answers.reduce(into: [:]) { $0[children[$1.key].identity] = $1.value.position }
        state.requests = handed
        reply.sliceOriginY = top
        reply.sliceTotalHeight = max(total, bottom)
        reply.sliceTotalIsEstimate = true
        reply.sliceHoldsFirstRow = leading.holdsFirst
        reply.sliceHoldsLastRow = leading.holdsLast
        reply.pulledPosition = position
        ScrollContentReply.journal(from: context)
        return (pieces, bandHeight)
    }

    /// Hands `window`'s seek, if any, on in `request`: to the lead, the child
    /// whose lines are the container's, with the content around it as the
    /// container's — what the child's clamp and indicator headroom read.
    private static func handSeek(
        of window: ScrollContentWindow, to request: inout ScrollContentWindow, child: PulledParallelChild,
        isLead: Bool, rowHeight: Int
    ) {
        guard isLead, let seek = window.seek else { return }
        request.seek = seek
        request.linesAbove = window.linesAbove + child.y
        request.linesBelow = window.linesBelow + max(0, rowHeight - child.y - child.height)
    }

    /// A request for pulled `child`, its offset still to be placed.
    private static func pulledRequest(for child: PulledParallelChild, window: ScrollContentWindow) -> ScrollContentWindow {
        var request = ScrollContentWindow(
            offset: 0, viewportHeight: window.viewportHeight, contentIdentity: child.identity,
            reply: ScrollContentReply())
        request.isPulled = true
        return request
    }
}
