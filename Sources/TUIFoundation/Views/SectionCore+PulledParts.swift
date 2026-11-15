//  🖥️ TUI — A Terminal UI framework for Swift
//  SectionCore+PulledParts.swift
//
//  SCROLL-FIT's follow-ups (S8): one of a lazy stack's own sections whose
//  content is a long loop — `LazyVStack { Section { ForEach(0..<10_000) } }`,
//  pinned or not — is drawn as a column of its parts, the loop a lazy stack of
//  its own that the column pulls, as `LazyVStack { header; ForEach }` is
//  (`ImplicitColumnWindowing.swift`). Laid out whole, as the stack lays out
//  its sections (`renderStacked`), every row of the loop was built for each
//  measure of the stack: 30,035 rows on the first frame for one section of
//  10,000 rows unpinned, 110,000 for two pinned.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension _SectionCore {
    /// The section as a column of its parts, at a step of its own
    /// (``_ImplicitColumnOfSeveral``), when it is one of a lazy stack's own
    /// sections down a column and its content is a loop past the lazy stack's
    /// threshold, in scroll content (``sectionContentLoopWindows(_:in:)``);
    /// `nil` otherwise, and the section lays its parts out whole.
    ///
    /// The column lays the parts out as the stack would, at its alignment and
    /// spacing, and its loop, one of the column's views, is drawn as a lazy
    /// stack at the same alignment and spacing (``ImplicitColumnRowLayout``),
    /// a pulled child of the column. So only the rows on screen are built.
    /// The parts' identities are the column's, not those the section laid
    /// out whole gives them, so a loop growing past the threshold starts its
    /// rows' state afresh, once, as a `GroupBox`'s does.
    func pulledPartsColumn(
        layout: PinnedSectionLayout, context: RenderContext
    ) -> (column: _VStackCore<Section<Parent, Content, Footer>>, context: RenderContext)? {
        guard layout.axis == .vertical, isExpanded?.wrappedValue ?? true,
            sectionContentLoopWindows(content, in: context)
        else { return nil }
        let alignment = layout.alignment.horizontal
        let column = _VStackCore(
            alignment: alignment, spacing: layout.spacing, overflow: .clip,
            content: Section(header: header, content: content, footer: footer, isExpanded: isExpanded))
        var columnContext = context.withChildIdentity(type: _ImplicitColumnOfSeveral.self)
        columnContext.environment.implicitColumnRowLayout = ImplicitColumnRowLayout(
            alignment: alignment, spacing: layout.spacing)
        return (column, columnContext)
    }

    /// The column drawn, its header and footer pinned as `renderStacked`
    /// pins them: a copy of each, marked to pin, at its place in the
    /// section's lines.
    ///
    /// Pulled, the column draws a band of the section's lines, and answers
    /// where it falls in them (`sliceOriginY`) and how tall the section is
    /// (`sliceTotalHeight`, an estimate below the band): the header's place
    /// is its line 0 and the footer's the section's end, in the band's lines.
    /// A header or footer the band leaves out is drawn for its pin as a
    /// measure draws it, so no control in it joins the focus ring twice: the
    /// column draws it off the band for its place in the ring already.
    func renderPulledParts(
        _ pulled: (column: _VStackCore<Section<Parent, Content, Footer>>, context: RenderContext),
        layout: PinnedSectionLayout, pins: (headers: Bool, footers: Bool), context: RenderContext
    ) -> FrameBuffer {
        var buffer = TUIView.renderToBuffer(pulled.column, context: pulled.context)
        guard !context.isMeasuring, pins.headers || pins.footers else { return buffer }
        let reply = context.environment.scrollContentWindow.flatMap {
            $0.isAtOrigin(context.identity) ? $0.reply : nil
        }
        let origin = reply?.sliceOriginY ?? 0
        let total = reply?.sliceTotalHeight ?? buffer.height
        let holdsFirst = reply?.sliceOriginY == nil || reply?.sliceHoldsFirstRow == true
        let holdsLast = reply?.sliceOriginY == nil || reply?.sliceHoldsLastRow == true

        let headerBlock = partBlock(header, part: 0, layout: layout, width: buffer.width, context: pulled.context)
        let footerBlock = partBlock(footer, part: 2, layout: layout, width: buffer.width, context: pulled.context)
        let headerLines = headerBlock.height
        let footerLines = footerBlock.height
        let contentStart = headerLines + (headerLines > 0 ? layout.spacing : 0)
        let footerStart = total - footerLines
        let contentEnd = footerStart - (footerLines > 0 ? layout.spacing : 0)
        guard contentEnd > contentStart else { return buffer }

        // A part's lines as the band drew them, when it holds them; else as
        // drawn here.
        func chrome(_ block: FrameBuffer, at top: Int, inBand: Bool) -> FrameBuffer {
            let local = top - origin
            guard inBand, local >= 0, local + block.height <= buffer.height else { return block }
            return buffer.copying(lines: local..<(local + block.height))
        }
        if pins.headers, headerLines > 0 {
            buffer.overlays.append(
                OverlayLayer.scrollPinned(
                    chrome(headerBlock, at: 0, inBand: holdsFirst), at: -origin, edge: .top,
                    travel: contentEnd - headerLines))
        }
        if pins.footers, footerLines > 0 {
            buffer.overlays.append(
                OverlayLayer.scrollPinned(
                    chrome(footerBlock, at: footerStart, inBand: holdsLast), at: footerStart - origin,
                    edge: .bottom, travel: footerStart - contentStart))
        }
        return buffer
    }

    /// A header's or footer's views drawn as the column draws them, one below
    /// another `spacing` apart and aligned across `width`, as a measure draws
    /// them: blank for a part with none.
    private func partBlock<Part: View>(
        _ view: Part, part index: Int, layout: PinnedSectionLayout, width: Int, context: RenderContext
    ) -> FrameBuffer {
        guard Part.self != EmptyView.self else { return FrameBuffer() }
        let measuring = fixedMeasureContext(proposal: ProposedViewSize(width: width, height: nil), context: context)
        var block = FrameBuffer()
        for child in sectionPartChildren(view, part: index, in: measuring) {
            let height = child.measure(proposal: ProposedViewSize(width: width, height: nil), context: measuring).height
            let drawn = child.render(width: width, height: max(0, height), context: measuring)
            block.appendVertically(
                drawn.horizontallyAligned(toWidth: width, alignment: layout.alignment.horizontal),
                spacing: layout.spacing)
        }
        return block
    }
}
