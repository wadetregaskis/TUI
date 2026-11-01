//  🖥️ TUI — A Terminal UI framework for Swift
//  PointerStyleModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUITerminalHost
import TUIView

// MARK: - The modifier

/// Files a region the size of its content that gives the pointer `style`'s
/// shape while it is over it — ``View/pointerStyle(_:)``.
///
/// Modifier infrastructure, `Renderable` as `.onHover` is: it draws its
/// content unchanged and adds a region to the buffer. The region is not a
/// handler's (``MouseEventDispatcher/registerPointerStyle(_:in:)``): no event
/// reaches it, and the pointer crossing it asks for no frame. The run loop
/// resolves the shape under the pointer after each batch of input and each
/// frame, and writes it only when it changes.
nonisolated struct PointerStyleModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The style asked for, or `nil` to leave the pointer to whatever is
    /// further out.
    let style: PointerStyle?

    @MainActor var body: Never {
        fatalError("PointerStyleModifier renders via Renderable")
    }
}

// MARK: - Renderable

@MainActor extension PointerStyleModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIView.renderToBuffer(content, context: context)
        // Nothing where the terminal shows no shapes: no region, and no motion
        // reporting asked for on its behalf (a terminal reporting every move
        // costs the app a wake for each). Nothing inside `.disabled(true)`
        // either, as `.onHover` hears nothing there: a disabled view says it
        // cannot be acted on, and a resize arrow or a hand over it would say
        // it can.
        guard let style, !context.isMeasuring, context.environment.isEnabled,
            context.environment.terminalFeatures.pointerShapes,
            let dispatcher = context.environment.mouseEventDispatcher
        else {
            return buffer
        }
        // The shape follows the pointer as it moves, which only motion
        // reporting tells: asked for while the style is on screen, and only
        // then. The region goes in front of the content's, whose styles are
        // noted as nested in it.
        dispatcher.requestFeature(.motion, in: context)
        let id = dispatcher.registerPointerStyle(style.shape, over: buffer.hitTestRegions, in: context)
        buffer.hitTestRegions.append(
            HitTestRegion(offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height, handlerID: id))
        return buffer
    }
}

// MARK: - Layoutable

@MainActor extension PointerStyleModifier: Layoutable {
    /// Forwards measurement straight to the content: a pointer style changes
    /// no layout.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it, as `.onHover`'s
/// does.
@MainActor extension PointerStyleModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
@MainActor extension PointerStyleModifier: DrawsContentUnchanged {}

// MARK: - View Extension

extension View {
    /// Sets the pointer style to display when the pointer is over the view.
    ///
    /// ```swift
    /// ImageCanvasView()
    ///     .pointerStyle(toolMode == .selection ? .rectSelection : nil)
    /// ```
    ///
    /// Of styles set on nested views, the innermost one under the pointer
    /// wins, and of views that overlap — an overlay, a `ZStack`'s layers, a
    /// background — the one in front; `nil` sets none, leaving the pointer to
    /// whatever is further out. A view covered by another — a sheet's
    /// backdrop, an open menu, a control drawn over it — shows its style only
    /// where nothing covers it; one inside `.draggable`, `.focusable()` or
    /// `.onMouseEvent`, which take its events without hiding it, shows
    /// through them. A view inside `.disabled(true)` shows none.
    ///
    /// The terminal draws the pointer, and only some let an app choose its
    /// shape; elsewhere this changes nothing. Read
    /// ``EnvironmentValues/terminalCapabilities``' ``TerminalCapabilities/Feature/pointerShapes`` to tell. See
    /// ``PointerStyle``. While a style is on screen, the terminal is asked to
    /// report the pointer's every move, as `.onHover` asks.
    ///
    /// - Parameter style: The pointer style to use.
    /// - Returns: A view that changes the style of the pointer when hovered.
    nonisolated public func pointerStyle(_ style: PointerStyle?) -> some View {
        PointerStyleModifier(content: self, style: style)
    }
}
