//  🖥️ TUI — A Terminal UI framework for Swift
//  _ListCore+Pulled.swift
//
//  SCROLL-FIT's pull (design P3), for a `List` in a scroll view's content: with
//  the switch on (`EnvironmentValues.scrollFitsContent`), a list of one-line
//  rows that a column pulls where it stands is its content's height, as the
//  owner's SCROLL-FIT ruling has it, and draws only the lines the scroll view
//  shows: its rows at a fixed pitch, so where each falls is arithmetic and
//  nothing off screen is built. The band is drawn as the list draws itself
//  framed to those rows — its own window walk, its rows, its cursor, its
//  clicks — with its own indicators off and its own scrolling handed to the
//  scroll view, then cut to the band's lines.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The rows a pulled list draws this frame: the list's own window, placed
/// where the band is rather than where the list last scrolled itself
/// (``_ListCore/renderPulledFrame(context:)``).
struct ListPulledRows {
    /// The first row drawn.
    let offset: Int

    /// Puts `handler` where the band is, whatever the list last scrolled
    /// itself to; and passes the wheel on to the scroll view that scrolls it.
    @MainActor
    func pin<SelectionValue: Hashable>(_ handler: ItemListHandler<SelectionValue>) {
        handler.scrollOffset = offset
        handler.scrollTopClipLines = 0
        handler.isScrollEnabled = false
    }
}

/// A list's lines as SCROLL-FIT's pull reads them: the chrome above its rows
/// (a border, a borderless title), its rows one line each, the chrome below.
struct ListPulledLines {
    /// How many rows the list holds.
    let count: Int
    /// The lines above the first row, and below the last.
    let top: Int
    let bottom: Int
    /// The row a `scrollTo` key names, by a scan of the keys: no row built.
    let index: (String) -> Int?

    /// The list's height: its chrome and a line per row.
    var total: Int { top + count + bottom }

    /// The rows the lines `band` hold, never none: a band of chrome alone
    /// draws the row next to it, which the cut then leaves out.
    func rows(for band: Range<Int>) -> Range<Int> {
        let first = min(max(band.lowerBound - top, 0), count - 1)
        let end = min(max(band.upperBound - top, first + 1), count)
        return first..<end
    }

    /// The lines of the list drawn framed to `rows` — its chrome above, those
    /// rows, its chrome below — that hold the list's lines `band`.
    func drawnLines(of band: Range<Int>, rows: Range<Int>) -> Range<Int> {
        func drawn(_ line: Int) -> Int {
            if line < top { return line }
            if line < top + count { return top + line - top - rows.lowerBound }
            return top + rows.count + line - top - count
        }
        return drawn(band.lowerBound)..<(drawn(band.upperBound - 1) + 1)
    }
}

/// Whether a list's rows were found to be other than one line each, once in
/// its life: then it is drawn as before the pull (B-SCROLLFIT-3's uniform
/// hypothesis, refuted for good). Variable rows are P4's.
final class ListPulledPitch {
    var refuted = false
}

extension _ListCore {
    /// The list's lines when a column pulls it (the file header), or `nil`
    /// when it is drawn as before: the switch off, outside scroll content,
    /// given a height, below a container that does not pull, rows not all
    /// content (sections), no rows, or rows found taller than a line.
    func pulledLines(context: RenderContext) -> ListPulledLines? {
        guard context.environment.scrollFitsContent, context.scrollContentOriginDepth != 0,
            !context.hasExplicitHeight, context.isPulledWhereItStands, !pitchIsRefuted(context: context)
        else { return nil }
        let source = extractRows(from: content, context: context)
        guard !source.isEmpty, source.allContentIfKnown == true else { return nil }
        let style = context.environment.listStyle
        let titleOverhead = (title != nil && !style.showsBorder) ? 1 : 0
        // The chrome is what the container keeps of a height past it.
        var probing = context
        probing.availableHeight = Self.chromeProbeHeight
        let rowLines =
            containerBodyHeight(
                title: title, config: listContainerConfig(context: context), content: _ListContentView(lines: []),
                footer: footer, context: probing) - titleOverhead
        let chrome = max(0, Self.chromeProbeHeight - rowLines)
        let top = min(chrome, (style.showsBorder ? 1 : 0) + titleOverhead + style.rowPadding.top)
        return ListPulledLines(
            count: source.count, top: top, bottom: chrome - top, index: { source.index(ofScrollKey: $0) })
    }

    /// The indicators the list draws: none when pulled, the scroll view
    /// around it showing where it is; else what its environment says for
    /// rows that do or do not overflow.
    static func indicators(
        overflowing: Bool, contentHeight: Int, pulled: ListPulledRows?, _ context: RenderContext
    ) -> ResolvedScrollIndicators {
        guard pulled == nil else { return .none }
        return context.environment.verticalScrollIndicators(overflowing: overflowing)
            .fitting(contentHeight: contentHeight)
    }

    /// A height past any list's chrome, at which the container is asked what
    /// it keeps for the rows.
    private static var chromeProbeHeight: Int { 1_000 }

    private func pitchIsRefuted(context: RenderContext) -> Bool {
        guard let storage = context.stateStorage else { return false }
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: Self.pulledPitchStateIndex)
        let box: StateBox<ListPulledPitch>? = storage.existingStorage(for: key)
        return box?.value.refuted == true
    }

    /// The list's measure when it is pulled: its content's height, held, and
    /// filed as a view that bands its own lines, so the column above hands it
    /// a request. Withdrawn otherwise.
    func pulledHeight(context: RenderContext) -> Int? {
        guard context.environment.scrollFitsContent else { return nil }
        let lines = pulledLines(context: context)
        context.notePulledBand(lines != nil)
        return lines?.total
    }

    /// A `scrollTo` search measuring this list (`ScrollKeyLocate`), switch
    /// on: the key is found when one of its rows carries it, by a scan of the
    /// keys, so a column hands it the seek.
    func answerSearch(_ search: ScrollKeyLocate, context: RenderContext) {
        guard context.environment.scrollFitsContent else { return }
        if extractRows(from: content, context: context).index(ofScrollKey: search.key) != nil {
            search.found = true
        }
    }

    /// The frame of a pulled list: the band of its lines a request asks for,
    /// drawn as the list draws itself framed to the band's rows, cut to the
    /// band's lines, and answered back. `nil` when the list is not pulled.
    ///
    /// With no request — the first frame's measuring walk, which gives the
    /// content only the lines down to the viewport's bottom — the band is the
    /// list's top, as far down as the walk goes and no further than a
    /// viewport, so that walk too builds only a screenful of rows.
    func renderPulledFrame(context: RenderContext) -> (buffer: FrameBuffer, viewport: CellRect?)? {
        guard let lines = pulledLines(context: context) else { return nil }
        let request = context.pulledBandRequest()
        let handler = existingHandler(context: context)
        let band: PulledBand?
        let lineRange: Range<Int>
        if let request {
            let resolved = request.band(total: lines.total) { seek in
                if seek.focusID != nil {
                    // A focus reveal: the cursor's row.
                    return (lines.top + min(handler?.focusedIndex ?? 0, lines.count - 1), 1)
                }
                return lines.index(seek.key).map { (lines.top + $0, 1) }
            }
            band = resolved
            lineRange = resolved.lines
        } else {
            band = nil
            let reach =
                context.isMeasuring
                ? context.availableHeight : context.environment.scrollViewportSize?.height ?? context.availableHeight
            lineRange = 0..<max(1, min(lines.total, reach))
        }
        let rows = lines.rows(for: lineRange)
        var framed = context
        framed.availableHeight = lines.top + rows.count + lines.bottom
        let frame = renderFrame(context: framed, pulled: ListPulledRows(offset: rows.lowerBound))
        let cut = lines.drawnLines(of: lineRange, rows: rows)
        var buffer = frame.buffer.lines(in: cut)

        if let handler = existingHandler(context: context), !context.isMeasuring {
            // One line a row, or the hypothesis is refuted for good: drawn as
            // before from the next frame, which measures it again.
            if handler.viewportHeight != rows.count, handler.dropSlotLines == 0 {
                refutePitch(context: context)
                request?.measureWentStale()
            }
            buffer.markPulledControl(
                focusID: handler.focusID, band: lineRange, total: lines.total,
                cursorLine: lines.top + handler.focusedIndex)
            // Page Up and Page Down move by the scroll view's viewport, not
            // the band's rows (B-SCROLLFIT-5).
            if let request { handler.viewportHeight = max(1, request.viewportHeight) }
        }
        if let band { request?.answer(band) }
        let viewport = frame.viewport.map {
            CellRect(x: $0.x, y: $0.y - cut.lowerBound, width: $0.width, height: $0.height)
        }
        return (buffer, viewport)
    }

    /// The list's handler, when it has one: the cursor's row, and what a
    /// pulled frame tells it of the scroll view.
    private func existingHandler(context: RenderContext) -> ItemListHandler<SelectionValue>? {
        guard let storage = context.stateStorage else { return nil }
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: Self.handlerStateIndex)
        let box: StateBox<ItemListHandler<SelectionValue>>? = storage.existingStorage(for: key)
        return box?.value
    }

    private func refutePitch(context: RenderContext) {
        guard let storage = context.stateStorage else { return }
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: Self.pulledPitchStateIndex)
        storage.storage(for: key, default: ListPulledPitch()).value.refuted = true
        context.notePulledBand(false)
    }
}
