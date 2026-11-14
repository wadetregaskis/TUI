//  🖥️ TUI — A Terminal UI framework for Swift
//  _ListCore+Pulled.swift
//
//  SCROLL-FIT's pull (designs P3 and P4), for a `List` in a scroll view's
//  content: with the switch on (`EnvironmentValues.scrollFitsContent`), a list
//  that a column pulls where it stands is its content's height, as the
//  owner's SCROLL-FIT ruling has it, and draws only the lines the scroll view
//  shows. Rows of one line each are placed by arithmetic (P3); rows of several
//  lines, or in sections, are walked from an anchor by the fill engine, the
//  rows not yet built priced at the running pitch (P4, `PulledRowBand.swift`).
//  Either way nothing off screen is built, and the band is drawn as the list
//  draws itself framed to those rows — its own window walk, its rows, its
//  cursor, its clicks — with its own indicators off and its own scrolling
//  handed to the scroll view, then cut to the band's lines. An empty list is
//  its placeholder's height, drawn whole.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The rows a pulled list draws this frame: the list's own window, placed
/// where the band is rather than where the list last scrolled itself
/// (``_ListCore/renderPulledFrame(context:)``).
struct ListPulledRows {
    /// The first row drawn, at a fixed pitch.
    let offset: Int
    /// For rows of varying height, what places them once the list's rows are
    /// at hand; `nil` at a fixed pitch.
    var variable: ListPulledVariable?

    /// Puts `handler` where the band is, whatever the list last scrolled
    /// itself to; and passes the wheel on to the scroll view that scrolls it.
    @MainActor
    func pin<SelectionValue: Hashable>(_ handler: ItemListHandler<SelectionValue>) {
        handler.scrollOffset = variable?.firstRow ?? offset
        handler.scrollTopClipLines = variable?.clip ?? 0
        handler.isScrollEnabled = false
    }
}

/// How a pulled list of rows of varying height (design P4) places its rows:
/// asked by the list's frame once its rows are extracted at the width they
/// are drawn at (``resolve(pitch:key:ordinal:)``), so that a row's pitch is
/// the height the list draws it at, and read back after the list is drawn.
@MainActor
final class ListPulledVariable {
    let request: PulledBandRequest?
    let lines: ListPulledLines
    let rows: PulledRows
    /// The cursor's row, which a focus reveal seeks.
    let cursorRow: Int
    /// With no request, how far down the list the first frame's measuring
    /// walk draws.
    let reach: Int

    /// The band, once placed (with a request).
    private(set) var result: PulledRowsBand?
    /// The rows drawn: from ``firstRow``, ``clip`` lines of it hidden.
    private(set) var firstRow = 0
    private(set) var clip = 0
    /// The lines of the framed drawing to keep.
    private(set) var drawnLines = 0..<1

    init(request: PulledBandRequest?, lines: ListPulledLines, rows: PulledRows, cursorRow: Int, reach: Int) {
        self.request = request
        self.lines = lines
        self.rows = rows
        self.cursorRow = cursorRow
        self.reach = reach
    }

    /// Places the band from the list's rows — `pitch(n)` the lines row `n`
    /// draws, `key` and `ordinal` its scroll key both ways — and answers the
    /// height to frame the list's drawing to.
    func resolve(
        width: Int, pitch: @escaping (Int) -> Int, key: @escaping (Int) -> String?,
        ordinal: @escaping (String) -> Int?
    ) -> Int {
        rows.noteShape(width: width, count: lines.count)
        guard let request else {
            let top = rows.top(count: lines.count, top: lines.top, bottom: lines.bottom, reach: reach, pitch: pitch)
            drawnLines = 0..<top.lines
            return lines.top + top.rowLines + lines.bottom
        }
        let cursorRow = min(cursorRow, lines.count - 1)
        let index = lines.index
        let band = request.band(
            of: rows, count: lines.count, top: lines.top, bottom: lines.bottom, pitch: pitch, key: key,
            ordinal: ordinal
        ) { seek in seek.focusID != nil ? cursorRow : index(seek.key) }
        result = band
        firstRow = band.firstRow
        clip = band.clip
        drawnLines = band.drawnLines
        return band.frameHeight(top: lines.top, bottom: lines.bottom)
    }
}

/// A list's lines as SCROLL-FIT's pull reads them: the chrome above its rows
/// (a border, a borderless title), its rows, the chrome below.
struct ListPulledLines {
    /// How many rows the list holds.
    let count: Int
    /// The lines above the first row, and below the last.
    let top: Int
    let bottom: Int
    /// The row a `scrollTo` key names, by a scan of the keys: no row built.
    let index: (String) -> Int?
    /// Whether the rows vary in height — found taller than a line, or not
    /// all content (sections) — and are walked (``ListPulledVariable``)
    /// rather than counted a line each.
    let variable: Bool

    /// The list's height at a line a row: its chrome and a line per row.
    var total: Int { top + count + bottom }

    /// Whether the list has no rows: then it is its placeholder's lines.
    var isEmpty: Bool {
        // swiftlint:disable:next empty_count
        count == 0
    }

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

/// A pulled list's state: whether its rows were found to be other than one
/// line each, once in its life — B-SCROLLFIT-3's uniform hypothesis, refuted
/// for good, after which its rows are walked as rows of varying height — and
/// what that walk keeps between frames.
@MainActor
final class ListPulledPitch {
    var refuted = false
    let rows = PulledRows()
}

extension _ListCore {
    /// The list's lines when a column pulls it (the file header), or `nil`
    /// when it is drawn as before: the switch off, outside scroll content,
    /// given a height, or below a container that does not pull.
    func pulledLines(context: RenderContext) -> ListPulledLines? {
        guard context.environment.scrollFitsContent, context.scrollContentOriginDepth != 0,
            !context.hasExplicitHeight, context.isPulledWhereItStands
        else { return nil }
        let source = extractRows(from: content, context: context)
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
        let variable = source.allContentIfKnown != true || pulledState(context: context)?.refuted == true
        return ListPulledLines(
            count: source.count, top: top, bottom: chrome - top, index: { source.index(ofScrollKey: $0) },
            variable: variable)
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

    /// The list's pulled state, when it has drawn pulled.
    private func pulledState(context: RenderContext) -> ListPulledPitch? {
        guard let storage = context.stateStorage else { return nil }
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: Self.pulledPitchStateIndex)
        let box: StateBox<ListPulledPitch>? = storage.existingStorage(for: key)
        return box?.value
    }

    /// The list's measure when it is pulled: its content's height, filed as a
    /// view that bands its own lines, so the column above hands it a request.
    /// Withdrawn otherwise. At a line a row the height is exact; rows of
    /// varying height are priced at the running pitch of those measured, and
    /// before any is drawn at a line each, building none — sampled in the
    /// measure, every rung of the scroll view's measuring ladder sampled them
    /// again, so the first frame built more rows the more there were. The
    /// first band's answer corrects it. An empty list is its placeholder's
    /// lines, drawn whole.
    func pulledHeight(context: RenderContext) -> Int? {
        guard context.environment.scrollFitsContent else { return nil }
        let lines = pulledLines(context: context)
        context.notePulledBand(lines.map { !$0.isEmpty } ?? false)
        guard let lines else { return nil }
        guard !lines.isEmpty else {
            let placeholder = emptyStateContent(height: Self.chromeProbeHeight, context: context)
            return lines.top + placeholder.lines.count + lines.bottom
        }
        guard lines.variable else { return lines.total }
        guard let rows = pulledState(context: context)?.rows, rows.hasSamples || rows.reportedRowsHeight != nil
        else { return lines.total }
        return lines.top + rows.estimatedRowsHeight(count: lines.count) + lines.bottom
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
    /// band's lines, and answered back. `nil` when the list is not pulled, or
    /// is empty (drawn whole, at its placeholder's height).
    ///
    /// With no request — the first frame's measuring walk, which gives the
    /// content only the lines down to the viewport's bottom — the band is the
    /// list's top, as far down as the walk goes and no further than a
    /// viewport, so that walk too builds only a screenful of rows.
    func renderPulledFrame(context: RenderContext) -> (buffer: FrameBuffer, viewport: CellRect?)? {
        guard let lines = pulledLines(context: context), !lines.isEmpty else { return nil }
        let request = context.pulledBandRequest()
        let handler = existingHandler(context: context)
        let reach =
            context.isMeasuring
            ? context.availableHeight : context.environment.scrollViewportSize?.height ?? context.availableHeight
        if lines.variable {
            return renderVariableFrame(lines: lines, request: request, handler: handler, reach: reach, context: context)
        }
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
            lineRange = 0..<max(1, min(lines.total, reach))
        }
        let rows = lines.rows(for: lineRange)
        var framed = context
        framed.availableHeight = lines.top + rows.count + lines.bottom
        let frame = renderFrame(context: framed, pulled: ListPulledRows(offset: rows.lowerBound))
        let cut = lines.drawnLines(of: lineRange, rows: rows)
        var buffer = frame.buffer.lines(in: cut)

        if let handler = existingHandler(context: context), !context.isMeasuring {
            // One line a row, or the hypothesis is refuted for good: walked as
            // rows of varying height from the next frame, which measures it
            // again.
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
        return (buffer, Self.cutViewport(frame.viewport, by: cut))
    }

    /// The frame of a pulled list of rows of varying height
    /// (``renderPulledFrame(context:)``): the rows walked from the list's
    /// anchor once the frame has them (``ListPulledVariable``), the drawing
    /// cut to the band, the cursor's row marked where the band misses it.
    private func renderVariableFrame(
        lines: ListPulledLines, request: PulledBandRequest?, handler: ItemListHandler<SelectionValue>?,
        reach: Int, context: RenderContext
    ) -> (buffer: FrameBuffer, viewport: CellRect?) {
        let state = pulledStateCreating(context: context)
        let variable = ListPulledVariable(
            request: request, lines: lines, rows: state.rows, cursorRow: handler?.focusedIndex ?? 0, reach: reach)
        let frame = renderFrame(context: context, pulled: ListPulledRows(offset: 0, variable: variable))
        let cut = variable.drawnLines.clamped(to: 0..<max(1, frame.buffer.height))
        var buffer = frame.buffer.lines(in: cut)
        if let result = variable.result {
            if let handler = existingHandler(context: context), !context.isMeasuring {
                let cursor = result.lines(
                    ofRow: min(handler.focusedIndex, lines.count - 1), viewportHeight: request?.viewportHeight ?? reach)
                buffer.markPulledControl(
                    focusID: handler.focusID, band: result.band.lines, total: result.band.total,
                    cursorLine: cursor.top, cursorHeight: cursor.height)
                // Page Up and Page Down move by the scroll view's viewport,
                // in the rows it shows (B-SCROLLFIT-5).
                handler.viewportHeight = result.rowsOnScreen
            }
            request?.answer(result.band)
        }
        return (buffer, Self.cutViewport(frame.viewport, by: cut))
    }

    /// The list's content window in a drawing cut to `cut`.
    private static func cutViewport(_ viewport: CellRect?, by cut: Range<Int>) -> CellRect? {
        viewport.map { CellRect(x: $0.x, y: $0.y - cut.lowerBound, width: $0.width, height: $0.height) }
    }

    /// The list's handler, when it has one: the cursor's row, and what a
    /// pulled frame tells it of the scroll view.
    private func existingHandler(context: RenderContext) -> ItemListHandler<SelectionValue>? {
        guard let storage = context.stateStorage else { return nil }
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: Self.handlerStateIndex)
        let box: StateBox<ItemListHandler<SelectionValue>>? = storage.existingStorage(for: key)
        return box?.value
    }

    /// The list's pulled state, made on its first pulled frame.
    private func pulledStateCreating(context: RenderContext) -> ListPulledPitch {
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: Self.pulledPitchStateIndex)
        return context.stateStorage!.storage(for: key, default: ListPulledPitch()).value
    }

    private func refutePitch(context: RenderContext) {
        guard context.stateStorage != nil else { return }
        pulledStateCreating(context: context).refuted = true
    }
}
