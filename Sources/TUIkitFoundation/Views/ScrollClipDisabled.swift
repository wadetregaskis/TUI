//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollClipDisabled.swift
//
//  `scrollClipDisabled(_:)`: a scroll view that draws its content past its
//  bounds, over what is beside it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Environment

private struct ScrollClipDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the scroll views in this subtree draw their content past their
    /// bounds — see ``TUIkit/View/scrollClipDisabled(_:)``.
    ///
    /// Internal: SwiftUI exposes the modifier, not an environment value.
    var scrollClipDisabled: Bool {
        get { self[ScrollClipDisabledKey.self] }
        set { self[ScrollClipDisabledKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets whether a scroll view clips its content to its bounds. Matches
    /// SwiftUI's modifier of the same name.
    ///
    /// By default a ``ScrollView`` draws only what is inside its viewport.
    /// Disabled, it also draws the content that runs past it — above and below,
    /// and either side of a horizontal one — over whatever is beside the scroll
    /// view, as SwiftUI's does:
    ///
    /// ```swift
    /// ScrollView(.horizontal) {
    ///     HStack(spacing: 2) { ForEach(cards) { CardView($0) } }
    /// }
    /// .scrollClipDisabled()
    /// ```
    ///
    /// What is drawn past the bounds:
    /// - **The content's own lines**, as far as the content draws them: all of
    ///   an eager stack, and the band a lazy stack draws around its viewport —
    ///   a row or so beyond each edge, as SwiftUI draws its nearby rows.
    /// - **The content's floating drawing** — an `.offset` view, a transition
    ///   on its way in — which the scroll view otherwise cuts at its bounds.
    ///
    /// It is drawn at the scroll view's own place in the stacking order, as
    /// SwiftUI's is (measured): over the views before the scroll view and under
    /// the views after it, so a sibling below a scroll view hides what runs
    /// down into it where the sibling draws, while what runs up over the
    /// sibling above is drawn over it. A later view hides it only under the
    /// cells it paints: its stack's alignment padding, an overlay's spacer or
    /// an offset view's empty footprint hides nothing, as in SwiftUI. What is
    /// drawn there can be clicked there. Blank cells at either end of a line
    /// draw nothing and take no click, so a short or indented line neither
    /// erases nor steals the clicks of what is beside it.
    ///
    /// ``List`` and ``Table`` keep clipping (decisions-D2S B-D2S-4), and so do
    /// the scrollers the framework puts around a tall menu, a sheet's or a
    /// framed container's content, whose content belongs inside their surface;
    /// the scroll views in that content still answer the modifier.
    ///
    /// A scroll view clipping, as nearly all do, pays one environment read a
    /// frame for it.
    ///
    /// - Parameter disabled: Whether to stop clipping.
    /// - Returns: A view whose scroll views clip, or do not clip, their content.
    public func scrollClipDisabled(_ disabled: Bool = true) -> some View {
        environment(\.scrollClipDisabled, disabled)
    }
}

// MARK: - The scroll view's side

extension _ScrollViewCore {
    /// The content past the viewport, as layers floating around the scroll
    /// view: asked only when the scroll view does not clip
    /// (`drawnViewport`, which reads that once a frame), and only drawn on a
    /// render pass.
    ///
    /// The content the frame drew (`full`, a band for a lazy stack) is placed
    /// where the viewport's window puts it — the offset, the horizontal offset,
    /// the overscroll and alignment slide — and the scroll view's own rect,
    /// its bars and reserved "N more" lines included, is cut out of it: that is
    /// drawn in the flow. Its layers are not carried: the window already
    /// carries them, unclipped (``viewportOverlay(_:shiftedByX:y:width:height:clips:)``).
    /// What is left is drawn as the cells it paints (`OverlayLayer.drawnParts()`):
    /// the blank cells at either end of a line draw nothing and take no click,
    /// so a short or indented line neither erases nor steals the clicks of what
    /// is beside it.
    ///
    /// The layers are marked ``OverlayLayer/isOverflow``, which places
    /// them at the scroll view's z position: content composed after the scroll
    /// view cuts them away beneath it.
    func overflowLayers(
        of full: FrameBuffer, sliceOriginY: Int, handler: ScrollViewHandler, chrome: ScrollChrome,
        width: Int, height: Int, horizontal: Bool, context: RenderContext
    ) -> [OverlayLayer] {
        guard !context.isMeasuring else { return [] }
        var content = full
        content.overlays = []
        let slide =
            handler.overscrollState.excursion
            - alignmentShift(handler: handler, viewportHeight: height, context: context)
        var layer = OverlayLayer(
            offsetX: horizontal ? -handler.horizontal.scrollOffset : 0,
            offsetY: sliceOriginY - handler.scrollOffset - slide,
            content: content,
            zIndex: OverlayLayer.displacedDrawingZIndex,
            clampsToScreen: false, isOpaque: false)
        layer.isOverflow = true
        // The whole view, in the content window's coordinates: the reserved
        // lines sit above and below the window, the bars beside and below it.
        // Cut first, so only the overflow's lines are read for what they paint.
        let reserved = chrome.reservesIndicatorLines ? 1 : 0
        return layer.excluding(
            x: 0, y: -reserved,
            width: width + (chrome.verticalBar ? 1 + chrome.indicatorMargins.trailing : 0),
            height: height + 2 * reserved + (chrome.horizontalBar ? 1 + chrome.indicatorMargins.bottom : 0)
        ).flatMap { $0.drawnParts() }
    }
}
