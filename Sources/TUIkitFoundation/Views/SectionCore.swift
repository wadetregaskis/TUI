//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SectionCore.swift
//
//  How a `Section` draws when it is drawn as one view: on its own — a view's
//  whole `body`, a scroll view's content — or as one of a pinned lazy stack's
//  own sections. Anywhere else it never draws as one: a container takes it
//  apart (`SectionAsParts.swift`), and a `List` reads it as rows.
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Section Core (Internal Rendering)

/// A section drawn as one view.
///
/// On its own it stacks its header, content and footer vertically, with no
/// styling and no spacing, as a `Group` drawn on its own stacks its members; a
/// lazy stack in its content still bands itself against the scroll window
/// (`ScrollWindowRelay`). Drawn by a `List` as one of its rows — a section the
/// list cannot read as rows of its own, such as one wrapped in a modifier — it
/// keeps the list's styling (``EnvironmentValues/drawsListSectionChrome``). As one of a pinned lazy stack's own sections it lays
/// its parts out as the stack lays out its children
/// (``PinnedSectionLayout``) and pins its header and footer
/// (`OverlayLayer.scrollPin`).
struct _SectionCore<Parent: View, Content: View, Footer: View>: View, Renderable, Layoutable {
    let header: Parent
    let content: Content
    let footer: Footer
    let isExpanded: Binding<Bool>?

    /// Whether the content is drawn: not while a collapsible section is
    /// collapsed.
    private var showsContent: Bool { isExpanded?.wrappedValue ?? true }

    /// The header as a `List` draws it: behind a disclosure triangle for a
    /// collapsible section, under the header's chrome role.
    private var listHeader: _SectionHeader<Parent> {
        _SectionHeader(header: header, isExpanded: isExpanded)
    }

    /// `context` for a header or footer: under its chrome role when a `List`
    /// draws the section (``EnvironmentValues/drawsListSectionChrome``), so its
    /// text takes the role's styling through the cascade, and as it is
    /// otherwise.
    private func chromeContext(_ context: RenderContext, _ role: ChromeRole) -> RenderContext {
        context.environment.drawsListSectionChrome ? sectionChromeContext(context, role) : context
    }

    /// The header or footer as drawn: dropped when a `List` draws the section
    /// and it draws blank (a `Text("")`), as a list drops a blank header row.
    private func drawnChrome(_ buffer: FrameBuffer, _ context: RenderContext) -> FrameBuffer? {
        context.environment.drawsListSectionChrome && sectionBufferIsBlank(buffer) ? nil : buffer
    }

    /// The header as drawn in `context`.
    private func renderHeader(_ context: RenderContext) -> FrameBuffer? {
        guard !(header is EmptyView) else { return nil }
        let headerContext = chromeContext(context, .sectionHeader)
        let buffer =
            context.environment.drawsListSectionChrome
            ? TUIkitView.renderToBuffer(listHeader, context: headerContext)
            : TUIkitView.renderToBuffer(header, context: headerContext)
        return drawnChrome(buffer, context)
    }

    var body: Never {
        fatalError("_SectionCore renders via Renderable")
    }

    /// The pinned stack this is one of the own sections of: what it pins, and
    /// how it lays out its children — or `nil`.
    private func pinningStack(
        _ context: RenderContext
    ) -> (pins: (headers: Bool, footers: Bool), layout: PinnedSectionLayout)? {
        guard let scope = context.environment.pinnedSectionScope,
            scope.owns(sectionAt: context.identity),
            let layout = context.environment.pinnedSectionLayout
        else { return nil }
        return ((scope.pinsHeaders, scope.pinsFooters), layout)
    }

    /// `context` for what the section draws, which is no section of the
    /// stack's: a section in its content is that section's, not the stack's,
    /// and is taken apart there.
    private func drawingContext(_ context: RenderContext) -> RenderContext {
        guard context.environment.pinnedSectionScope != nil || context.sectionWholeness != .apart else {
            return context
        }
        var drawing = context
        if drawing.environment.pinnedSectionScope != nil { drawing.environment.pinnedSectionScope = nil }
        drawing.sectionWholeness = .apart
        return drawing
    }

    /// Size from one render, on its own: whether a lazy stack in the content
    /// draws a band or every row is known only by drawing it. Flexibility comes
    /// from the parts, so a `.frame(maxWidth: .infinity)` content still reports
    /// the section width-flexible to its parent.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        if let stack = pinningStack(context) {
            return stackedSize(
                layout: stack.layout, proposal: proposal, context: drawingContext(context))
        }
        let size = measureFixedByRendering(self, proposal: proposal, context: context)
        var widthFlexible = false
        var heightFlexible = false
        func note(_ childSize: ViewSize) {
            if childSize.isWidthFlexible { widthFlexible = true }
            if childSize.isHeightFlexible { heightFlexible = true }
        }
        if !(header is EmptyView) {
            note(measureChild(header, proposal: proposal, context: chromeContext(context, .sectionHeader)))
        }
        if showsContent { note(measureChild(content, proposal: proposal, context: context)) }
        if !(footer is EmptyView) {
            note(measureChild(footer, proposal: proposal, context: chromeContext(context, .sectionFooter)))
        }
        return ViewSize(
            width: size.width, height: size.height,
            isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let stack = pinningStack(context)
        let context = drawingContext(context)
        if let stack { return renderStacked(layout: stack.layout, pins: stack.pins, context: context) }

        var lines: [String] = []
        // A `Section` assembles its lines by hand rather than compositing, so
        // EVERYTHING a child's buffer carries beside those lines is lost unless
        // it is carried deliberately — and each of the three is lost silently,
        // in a way that reads as an ordinary page:
        //
        // - a dropped **run** is a spinner or a caret that only keeps moving
        //   because something else forces a full re-render;
        // - a dropped **hit-test region** is a control that draws its hover and
        //   focus states perfectly and cannot be clicked;
        // - a dropped **overlay** is a `.sheet`, `.alert`, `.popover`, `Picker`
        //   drop-down or `.contextMenu` that never reaches the root compositor
        //   — for a modal, one that takes the keyboard and then does not appear.
        //
        // Only the runs were carried at first, which is how the other two came
        // to be missing for as long as they were: the class was noticed and one
        // instance of it fixed.
        var runs: [AnimatedCellRun] = []
        // The parts' layers, gathered as a stack gathers its children's: what
        // a part draws past its region is cut where a later part paints, so it
        // is drawn over the parts before it and under the parts after it. A
        // buffer of no lines, not the section's: it only carries the layers,
        // so that the stack's own two steps (`coverOverflow(under:at:)`,
        // `appendOverlays(of:shiftedByX:y:)`) do the work and keep the hint
        // that none is overflow: a part that carries no layer costs a test.
        var layers = FrameBuffer()
        var regions: [HitTestRegion] = []
        var faded: [OpacityRegion] = []
        func take(_ buffer: FrameBuffer) {
            let dy = lines.count
            runs += buffer.shiftedAnimatedCells(byX: 0, y: dy)
            layers.coverOverflow(under: buffer, at: (x: 0, y: dy))
            layers.appendOverlays(of: buffer, shiftedByX: 0, y: dy)
            regions += buffer.shiftedHitTestRegions(byX: 0, y: dy)
            faded += buffer.shiftedOpacityRegions(byX: 0, y: dy)
            lines.append(contentsOf: buffer.lines)
        }
        // A header or footer outside a scroll band is not drawn, but its
        // controls are carried at their place beside the band, as a windowed
        // stack grafts an off-band row: a focus move onto one still finds where
        // to scroll.
        func carry(_ buffer: FrameBuffer, at dy: Int) {
            layers.appendOverlays(of: buffer, shiftedByX: 0, y: dy)
            regions += buffer.shiftedHitTestRegions(byX: 0, y: dy)
        }

        // The header and footer as written: outside a `List`, a section gives
        // them no styling of its own (decisions B16), and a collapsible
        // section's header is no control. A list's section keeps the list's.
        let headerBuffer = renderHeader(context)

        // A lazy stack in the content still bands itself against a scroll
        // window — single-child steps lead to it — so it is handed the window
        // as the content sees it, below the header and above the footer.
        let relay = ScrollWindowRelay(
            context: context, linesAbove: headerBuffer?.height ?? 0,
            linesBelow: { footerLinesBelowScrollContent(context: context) })
        let contentBuffer =
            showsContent
            ? TUIkitView.renderToBuffer(content, context: relay?.contentContext(context) ?? context)
            : FrameBuffer()

        let footerBuffer: FrameBuffer? =
            footer is EmptyView
            ? nil
            : drawnChrome(
                TUIkitView.renderToBuffer(footer, context: chromeContext(context, .sectionFooter)), context)

        let placement =
            relay?.answer(contentBuffer: contentBuffer, linesBelow: footerBuffer?.height ?? 0)
            ?? ScrollWindowRelay.Placement()
        if let headerBuffer {
            if placement.drawsAbove {
                take(headerBuffer)
            } else {
                carry(headerBuffer, at: min(placement.contentTop, 0) - headerBuffer.height)
            }
        }
        take(contentBuffer)
        if let footerBuffer {
            if placement.drawsBelow {
                take(footerBuffer)
            } else {
                carry(footerBuffer, at: placement.contentTop + placement.contentHeight)
            }
        }

        var buffer = FrameBuffer(lines: lines)
        buffer.overlays = layers.overlays
        buffer.hitTestRegions = regions
        // A measure pass draws nothing, so a run left on it would describe cells
        // that were never on screen — and keep the animation clock alive from a
        // pass that produced no frame. Overlays and regions carry either way,
        // as they do through `replacingLines`: neither holds a clock open, and
        // a measure buffer is discarded whole.
        if !context.isMeasuring { buffer.animatedCells = runs }
        // Carries either way, with the overlays and regions rather than with
        // the runs: it holds no clock open, and a translucent view inside a
        // section is as translucent while being measured as while being drawn.
        buffer.opacityRegions = faded
        return buffer
    }

    /// The footer's lines, for a lazy stack in the content that bands itself
    /// against a scroll window (`ScrollWindowRelay`, which asks only when it
    /// relays one) and needs them before the footer is drawn: drawn after the
    /// content, the footer's controls join the focus ring after the content's.
    /// So they are drawn once first as a measure draws them — no control
    /// registers there — and a footer the section drops (a `List`'s blank
    /// one) has none.
    private func footerLinesBelowScrollContent(context: RenderContext) -> Int {
        guard !(footer is EmptyView) else { return 0 }
        let drawn = TUIkitView.renderToBuffer(
            footer,
            context: fixedMeasureContext(
                proposal: ProposedSize(width: context.availableWidth, height: nil),
                context: chromeContext(context, .sectionFooter)))
        return drawnChrome(drawn, context)?.height ?? 0
    }
}

// MARK: - One of a Pinned Stack's Own Sections

extension _SectionCore {
    /// The views of each part, resolved as a container taking the section
    /// apart resolves them (`sectionPartChildren`), so the section lays out
    /// exactly what such a container would.
    private func partChildren(_ context: RenderContext) -> [[ChildView]] {
        [
            sectionPartChildren(header, part: 0, in: context),
            showsContent ? sectionPartChildren(content, part: 1, in: context) : [],
            sectionPartChildren(footer, part: 2, in: context),
        ]
    }

    /// The section's size laid out as the stack lays out its children: the
    /// views' extents along the stack's axis, `spacing` between every two that
    /// draw something, and across it the widest of them.
    private func stackedSize(
        layout: PinnedSectionLayout, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize {
        let vertical = layout.axis == .vertical
        var along = 0
        var across = 0
        var placed = 0
        var widthFlexible = false
        var heightFlexible = false
        for child in partChildren(context).joined() {
            let size = child.measure(
                proposal: vertical
                    ? ProposedSize(width: proposal.width, height: nil)
                    : ProposedSize(width: nil, height: proposal.height),
                context: context)
            if size.isWidthFlexible { widthFlexible = true }
            if size.isHeightFlexible { heightFlexible = true }
            // A view that draws no line (or column) takes no room and earns no
            // gap — the stack's own rule (`FrameBuffer.appendVertically`,
            // `appendHorizontally`).
            let extent = vertical ? size.height : size.width
            guard extent > 0 else { continue }
            along += (placed > 0 ? layout.spacing : 0) + extent
            across = max(across, vertical ? size.width : size.height)
            placed += 1
        }
        return ViewSize(
            width: vertical ? across : along, height: vertical ? along : across,
            isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible)
    }

    /// The section laid out as the stack lays out its children, its header
    /// and footer pinned.
    ///
    /// Each part is drawn as a block of its views, aligned across the
    /// section's breadth by the stack's alignment, and the blocks are laid
    /// along the stack's axis `spacing` apart: what the stack would draw with
    /// the parts as its own children, the section's breadth standing in for
    /// the stack's.
    private func renderStacked(
        layout: PinnedSectionLayout, pins: (headers: Bool, footers: Bool), context: RenderContext
    ) -> FrameBuffer {
        let vertical = layout.axis == .vertical
        let drawn = partChildren(context).map { children in
            children.map { child in
                // At the extent the view asks for along the axis, and as a
                // lazy stack offers its children across it.
                if vertical {
                    let height = child.measure(
                        proposal: ProposedSize(width: context.availableWidth, height: nil), context: context
                    ).height
                    return child.render(width: context.availableWidth, height: max(0, height), context: context)
                }
                let width = child.measure(proposal: .unspecified, context: context).width
                return child.render(width: max(0, width), height: context.availableHeight, context: context)
            }
        }
        let occupied = drawn.joined().filter { vertical ? !$0.lines.isEmpty : $0.width > 0 }
        let breadth = occupied.map { vertical ? $0.width : $0.height }.max() ?? 0
        func append(_ buffer: FrameBuffer, to block: inout FrameBuffer) {
            if vertical {
                block.appendVertically(buffer, spacing: layout.spacing)
            } else {
                block.appendHorizontally(buffer, spacing: layout.spacing)
            }
        }
        let blocks = drawn.map { buffers in
            var block = FrameBuffer()
            for buffer in buffers {
                append(
                    vertical
                        ? buffer.horizontallyAligned(toWidth: breadth, alignment: layout.alignment.horizontal)
                        : buffer.verticallyAligned(toHeight: breadth, alignment: layout.alignment.vertical),
                    to: &block)
            }
            return block
        }
        let (header, content, footer) = (blocks[0], blocks[1], blocks[2])
        func extent(_ buffer: FrameBuffer) -> Int { vertical ? buffer.height : buffer.width }

        var section = FrameBuffer()
        append(header, to: &section)
        func start(of block: FrameBuffer) -> Int {
            extent(section) + (extent(section) > 0 && extent(block) > 0 ? layout.spacing : 0)
        }
        let contentStart = start(of: content)
        append(content, to: &section)
        let footerStart = start(of: footer)
        append(footer, to: &section)

        if !context.isMeasuring, extent(content) > 0 {
            let contentEnd = contentStart + extent(content)
            if pins.headers, extent(header) > 0 {
                section.overlays.append(
                    Self.pinnedLayer(
                        header, at: 0, vertical: vertical, edge: vertical ? .top : .leading,
                        travel: contentEnd - extent(header)))
            }
            if pins.footers, extent(footer) > 0 {
                section.overlays.append(
                    Self.pinnedLayer(
                        footer, at: footerStart, vertical: vertical, edge: vertical ? .bottom : .trailing,
                        travel: footerStart - contentStart))
            }
        }
        return section
    }

    /// A layer pinning `chrome` — a header or a footer, drawn where the flow
    /// draws it, `offset` along the stack's axis — to an edge of the scroll
    /// view it is in (`OverlayLayer.scrollPin`), free to travel `travel` rows
    /// (or columns) toward the far end of its section: until a header's far
    /// edge meets the content's last row, or a footer's near edge the
    /// content's first, which is SwiftUI's rule (measured on macOS 15.8, on
    /// both axes).
    ///
    /// Padded to the chrome block's width, which every part is aligned across,
    /// so a pinned header covers every cell of the rows it lands on. Without
    /// its presentations: those ride on the chrome the flow draws, and the
    /// scroll view moves them with it.
    private static func pinnedLayer(
        _ chrome: FrameBuffer, at offset: Int, vertical: Bool, edge: OverlayLayer.ScrollPin.Edge,
        travel: Int
    ) -> OverlayLayer {
        var copy = chrome.replacingLines(chrome.lines.map { $0.padToVisibleWidth(chrome.width) })
        copy.overlays = []
        var layer = OverlayLayer(
            offsetX: vertical ? 0 : offset, offsetY: vertical ? offset : 0, content: copy, isOpaque: false)
        layer.scrollPin = OverlayLayer.ScrollPin(edge: edge, travel: travel)
        return layer
    }
}
