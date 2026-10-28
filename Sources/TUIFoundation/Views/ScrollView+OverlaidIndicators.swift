//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollView+OverlaidIndicators.swift
//
//  A scroll view's indicators drawn over its content while the pointer is
//  over it, under `.scrollIndicatorPlacement(.overContent)`: the vertical bar
//  on the content's last column, the horizontal bar on its last row, the "N
//  more" lines on its first and last — each drawn exactly as it is beside the
//  content, in the cells it covers. The content was laid out at the whole
//  viewport, so nothing moves as they come and go.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension _ScrollViewCore {
    /// Draws the indicators over `visibleBuffer`, the viewport's content, if
    /// the pointer is over the view and the content overflows that way.
    func applyOverlaidScrollChrome(
        to visibleBuffer: inout FrameBuffer, handler: ScrollViewHandler, contentWidth: Int,
        wantsHorizontal: Bool, isFocused: Bool, focusID: String, context: RenderContext
    ) {
        let environment = context.environment
        let hovered = handler.isPointerOver
        let vertical = environment.overlaidVerticalScrollIndicators(
            overflowing: handler.contentHeight > handler.viewportHeight, hovered: hovered)
        let horizontal =
            wantsHorizontal
            && environment.overlaidHorizontalScrollbar(
                overflowing: handler.horizontal.extent > handler.horizontal.viewportHeight, hovered: hovered)
        guard vertical.bar || vertical.text || horizontal else { return }
        if vertical.text, visibleBuffer.height >= ResolvedScrollIndicators.minimumTextHeight {
            visibleBuffer = applyScrollIndicators(
                to: visibleBuffer, handler: handler, width: contentWidth, palette: environment.palette,
                surface: environment.enclosingSurface,
                cycle: handler.hasContentAbove || handler.hasContentBelow
                    ? scrollIndicatorCycle(isFocused: isFocused, context: context) : nil,
                flash: nil, locale: environment.locale, always: false, reserving: false, blanksAtZero: true)
            attachIndicatorMouseHandlers(to: &visibleBuffer, contentWidth: contentWidth, handler: handler, context: context)
        }
        var width = contentWidth
        if vertical.bar {
            // The content's last columns give way to the bar, which is drawn
            // after them as it is beside the content.
            width = max(1, contentWidth - environment.scrollbarWidth)
            visibleBuffer = visibleBuffer.clamped(toWidth: width, height: visibleBuffer.height)
            visibleBuffer = appendVerticalScrollbar(
                to: visibleBuffer, contentWidth: width, handler: handler, isFocused: isFocused, context: context)
            attachScrollbarMouseHandler(
                to: &visibleBuffer, contentWidth: width, handler: handler, focusID: focusID, context: context)
        }
        if horizontal, visibleBuffer.height > 1 {
            visibleBuffer = visibleBuffer.clamped(toWidth: visibleBuffer.width, height: visibleBuffer.height - 1)
            visibleBuffer = appendHorizontalScrollbar(
                to: visibleBuffer, contentWidth: width, hasVerticalBar: vertical.bar, handler: handler,
                isFocused: isFocused, context: context)
            attachHorizontalScrollbarMouseHandler(
                to: &visibleBuffer, contentWidth: width, handler: handler, focusID: focusID, context: context)
        }
    }
}
