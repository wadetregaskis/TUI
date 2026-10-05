//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SectionCore.swift
//
//  How a `Section` draws when it is drawn as one view: split out of
//  `Section.swift`, which had passed the file-length ceiling.
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Section Core (Internal Rendering)

/// Internal core view that handles section rendering.
///
/// `_SectionCore` is a leaf node that renders the section's header, content,
/// and footer with appropriate styling. It conforms to `Renderable` for
/// direct buffer output.
struct _SectionCore<Parent: View, Content: View, Footer: View>: View, Renderable, Layoutable {
    let header: Parent
    let content: Content
    let footer: Footer
    let isExpanded: Binding<Bool>?

    /// The header as it is drawn: behind a disclosure triangle for a
    /// collapsible section.
    private var drawnHeader: _SectionHeader<Parent> {
        _SectionHeader(header: header, isExpanded: isExpanded)
    }

    /// Whether the content is drawn: not while a collapsible section is
    /// collapsed.
    private var showsContent: Bool { isExpanded?.wrappedValue ?? true }

    var body: Never {
        fatalError("_SectionCore renders via Renderable")
    }

    /// Size from one render: the stack of header/content/footer drops a *blank*
    /// header or footer (e.g. `header: { Text("") }` that padded to spaces),
    /// which can't be detected without rendering, so the height isn't a clean
    /// structural sum. Flexibility comes from the parts — measured under the same
    /// chrome contexts the render uses (chrome role styles, it does not resize) —
    /// so a `.frame(maxWidth: .infinity)` content still reports the section
    /// width-flexible to its parent.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let size = measureFixedByRendering(self, proposal: proposal, context: context)
        var widthFlexible = false
        var heightFlexible = false
        func note(_ childSize: ViewSize) {
            if childSize.isWidthFlexible { widthFlexible = true }
            if childSize.isHeightFlexible { heightFlexible = true }
        }
        if !(header is EmptyView) {
            note(measureChild(drawnHeader, proposal: proposal,
                              context: sectionChromeContext(context, .sectionHeader)))
        }
        if showsContent { note(measureChild(content, proposal: proposal, context: context)) }
        if !(footer is EmptyView) {
            note(measureChild(footer, proposal: proposal,
                              context: sectionChromeContext(context, .sectionFooter)))
        }
        return ViewSize(
            width: size.width, height: size.height,
            isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // One of a pinned lazy stack's own sections pins its header and footer
        // (`PinnedSectionScope`). What it draws is not the stack's: a section
        // that is this one's whole content is no section of the stack's.
        let pins = context.environment.pinnedSectionScope?.pins(at: context.identity)
        var context = context
        if pins != nil { context.environment.pinnedSectionScope = nil }

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
        var overlays: [OverlayLayer] = []
        var regions: [HitTestRegion] = []
        var faded: [OpacityRegion] = []
        func take(_ buffer: FrameBuffer) {
            let dy = lines.count
            runs += buffer.shiftedAnimatedCells(byX: 0, y: dy)
            overlays += buffer.shiftedOverlays(byX: 0, y: dy)
            regions += buffer.shiftedHitTestRegions(byX: 0, y: dy)
            faded += buffer.shiftedOpacityRegions(byX: 0, y: dy)
            lines.append(contentsOf: buffer.lines)
        }
        // A header or footer outside a scroll band is not drawn, but its
        // controls are carried at their place beside the band, as a windowed
        // stack grafts an off-band row: a focus move onto one still finds where
        // to scroll.
        func carry(_ buffer: FrameBuffer, at dy: Int) {
            overlays += buffer.shiftedOverlays(byX: 0, y: dy)
            regions += buffer.shiftedHitTestRegions(byX: 0, y: dy)
        }

        // Header and footer render under a chrome role, so their text resolves
        // the role's default styling (header bold+dim, footer dim) plus any
        // `.chrome(...)` theme overrides through the normal cascade — see
        // ``ChromeRole`` and ``Text``.
        var headerBuffer: FrameBuffer?
        if !(header is EmptyView) {
            let rendered = TUIkit.renderToBuffer(
                drawnHeader, context: sectionChromeContext(context, .sectionHeader))
            // Drop a blank header (e.g. `header: { Text("") }`) rather than show
            // an empty line above the content.
            if !sectionBufferIsBlank(rendered) { headerBuffer = rendered }
        }

        // A lazy stack in the content still bands itself against a scroll
        // window — single-child steps lead to it — so it is handed the window
        // as the content sees it, below the header and above the footer.
        let relay = ScrollWindowRelay(
            context: context, linesAbove: headerBuffer?.height ?? 0,
            linesBelow: { footerLinesBelowScrollContent(context: context) })
        let contentBuffer =
            showsContent
            ? TUIkit.renderToBuffer(content, context: relay?.contentContext(context) ?? context)
            : FrameBuffer()

        var footerBuffer: FrameBuffer?
        if !(footer is EmptyView) {
            let rendered = TUIkit.renderToBuffer(
                footer, context: sectionChromeContext(context, .sectionFooter))
            if !sectionBufferIsBlank(rendered) { footerBuffer = rendered }
        }

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

        if let pins, pins.headers || pins.footers, !context.isMeasuring {
            overlays += pinnedChrome(
                header: placement.drawsAbove ? headerBuffer : nil, content: contentBuffer,
                footer: placement.drawsBelow ? footerBuffer : nil, pins: pins)
        }

        var buffer = FrameBuffer(lines: lines)
        buffer.overlays = overlays
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

    /// The layers that pin this section's header to the top edge of the
    /// scroll view it is in, and its footer to the bottom, for a section of a
    /// pinned lazy stack (`OverlayLayer.scrollPin`): a copy of each, where
    /// the flow draws it, free to travel the height of the content.
    ///
    /// Padded to the section's width, so a pinned header covers every cell of
    /// the rows it lands on — the section's own rows, since the content's
    /// last row is as far as it goes. Without its presentations: those ride
    /// on the header the flow draws, and the scroll view moves them with it.
    ///
    /// - Parameters:
    ///   - header: The header, when it was drawn at the top of the section.
    ///   - footer: The footer, when it was drawn at the bottom.
    private func pinnedChrome(
        header: FrameBuffer?, content: FrameBuffer, footer: FrameBuffer?,
        pins: (headers: Bool, footers: Bool)
    ) -> [OverlayLayer] {
        let travel = content.height
        guard travel > 0 else { return [] }
        let width = max(header?.width ?? 0, content.width, footer?.width ?? 0)
        func layer(_ chrome: FrameBuffer, atY y: Int, edge: OverlayLayer.ScrollPin.Edge) -> OverlayLayer {
            var copy = chrome.replacingLines(chrome.lines.map { $0.padToVisibleWidth(width) })
            copy.overlays = []
            var layer = OverlayLayer(offsetX: 0, offsetY: y, content: copy, isOpaque: false)
            layer.scrollPin = OverlayLayer.ScrollPin(edge: edge, travel: travel)
            return layer
        }
        var layers: [OverlayLayer] = []
        if pins.headers, let header {
            layers.append(layer(header, atY: 0, edge: .top))
        }
        if pins.footers, let footer {
            layers.append(layer(footer, atY: (header?.height ?? 0) + travel, edge: .bottom))
        }
        return layers
    }

    /// The footer's lines, for a lazy stack in the content that bands itself
    /// against a scroll window (`ScrollWindowRelay`, which asks only when it
    /// relays one) and needs them before the footer is drawn: drawn after the
    /// content, the footer's controls join the focus ring after the content's.
    ///
    /// So they are drawn once first as a measure draws them — no control
    /// registers there — and a footer that draws blank has none, as the
    /// render drops it. Measured instead, a blank footer counted its lines,
    /// and the stack answered for content longer than the content drawn: at
    /// the end, over a blank footer of one line, the read-back sample was
    /// charged a "more below" line that was not drawn, and named the row above
    /// the last.
    private func footerLinesBelowScrollContent(context: RenderContext) -> Int {
        guard !(footer is EmptyView) else { return 0 }
        let drawn = TUIkit.renderToBuffer(
            footer,
            context: fixedMeasureContext(
                proposal: ProposedSize(width: context.availableWidth, height: nil),
                context: sectionChromeContext(context, .sectionFooter)))
        return sectionBufferIsBlank(drawn) ? 0 : drawn.height
    }
}
