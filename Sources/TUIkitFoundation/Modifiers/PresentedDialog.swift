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
    /// (``leaveScrollCanvas()``) and the text alignment it states for nothing
    /// in particular (``EnvironmentValues/leaveUnstatedTextAlignment()``).
    /// The surface is attached inside the content that presents it, but drawn
    /// over the screen.
    ///
    /// One method for every presenter, so that what one leaves behind, each
    /// does.
    package mutating func leavePresenter() {
        leaveScrollCanvas()
        environment.leaveUnstatedTextAlignment()
    }
}
