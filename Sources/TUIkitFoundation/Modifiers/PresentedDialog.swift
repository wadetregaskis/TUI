//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentedDialog.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Renders presented dialog `content` into a buffer, embedding it in an
/// otherwise-invisible `ScrollView` capped to `capHeight` when its natural
/// height exceeds the visible area — so an over-tall dialog (a big colour
/// picker, a long form) stays fully reachable by scrolling instead of having
/// its footer/buttons clipped under the status bar. When the content fits it is
/// rendered as-is: no ScrollView, no scrollbar, no extra focus stop — nothing
/// to detect. The wrapping ScrollView follows the focused control (the reveal
/// system), so Tabbing through the dialog scrolls it into view, and the wheel
/// scrolls it too.
@MainActor
package func renderPresentedDialog<V: View>(
    _ content: V, context: RenderContext, capHeight: Int
) -> FrameBuffer {
    let naturalHeight = measureChild(
        content, proposal: ProposedSize(width: context.availableWidth, height: nil),
        context: context
    ).height
    if capHeight > 0, naturalHeight > capHeight {
        let scrolled = ScrollView(.vertical) { content }.asChrome().frame(height: capHeight)
        return TUIkitView.renderToBuffer(scrolled, context: context)
    }
    return TUIkitView.renderToBuffer(content, context: context)
}

extension RenderContext {
    /// Leaves behind, for a presented surface's content — a sheet's or a
    /// cover's, an alert's, a popover's, a menu's — what the place its
    /// presenter is drawn in asks of the views drawn there: its scroll canvas
    /// (``leaveScrollCanvas()``), the text alignment it states for nothing
    /// in particular (``EnvironmentValues/leaveUnstatedTextAlignment()``),
    /// the size and corners of a sheet it is drawn in
    /// (``consumeSheetSize()``), and the segmented face of a control group it
    /// is a control of (``EnvironmentValues/isControlSegment``), whose
    /// surface's buttons are faces of their own. The surface is attached
    /// inside the content that presents it, but drawn over the screen.
    ///
    /// The sheet's size is its own box's. An alert written at the root of a
    /// sheet's content — outside the box the content draws, where a sheet's
    /// detent and proposed width still stand — took them for its own box,
    /// and filled the whole sheet; so did a popover there, and a sheet with
    /// no detent of its own presented from it.
    ///
    /// One method for every presenter, so that what one leaves behind, each
    /// does.
    package mutating func leavePresenter() {
        leaveScrollCanvas()
        environment.leaveUnstatedTextAlignment()
        consumeSheetSize()
        if environment.isControlSegment { environment.isControlSegment = false }
    }
}
