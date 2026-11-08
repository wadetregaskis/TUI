//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationHostModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - Notification Host Modifier

/// Draws the toasts of the environment's ``NotificationService`` over one
/// view, as the window chrome draws them over every scene's content area.
///
/// An app never needs this: every scene hosts its notifications
/// (``NotificationOverlay``, drawn by `_WindowChromeHost`). It is for a test
/// that renders a view with no scene around it, through the package-level
/// `notificationHost()` (TUIPresentation). Applied inside a scene it would
/// draw every toast a second time.
///
/// The base content remains fully interactive — notifications do not dim
/// or block the background.
nonisolated package struct NotificationHostModifier<Content: View>: View {
    /// The base content to render.
    let content: Content

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and `View.notificationHost()` (TUIPresentation) makes these.
    package init(content: Content) {
        self.content = content
    }

    @MainActor package var body: Never {
        fatalError("NotificationHostModifier renders via Renderable")
    }
}

// MARK: - Renderable

@MainActor extension NotificationHostModifier: Renderable {
    package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let baseBuffer = TUIView.renderToBuffer(content, context: context)
        let screenWidth = context.availableWidth
        let screenHeight = context.availableHeight
        let layers = NotificationOverlay.layers(context: context, areaWidth: screenWidth, areaHeight: screenHeight)
        guard !baseBuffer.isEmpty, !layers.isEmpty else { return baseBuffer }

        // Expand the base buffer to the whole area so the toasts are placed
        // relative to it, not to the content's size. The base's overlay layers
        // and hit-test regions carry over: rebuilding `lines` from scratch
        // would drop them, and a control under a toast would stop answering
        // clicks until the toast had gone. The padding moves no content, so
        // they carry at the same coordinates.
        var fullscreenLines: [String] = []
        for row in 0..<max(0, screenHeight) {
            fullscreenLines.append(
                row < baseBuffer.lines.count
                    ? baseBuffer.lines[row].padToVisibleWidth(screenWidth) : String.spaces(screenWidth))
        }
        var result = baseBuffer.replacingLines(fullscreenLines)
        result.overlays.append(contentsOf: layers)
        return result
    }
}

// MARK: - Layoutable

@MainActor extension NotificationHostModifier: Layoutable {
    /// Notifications are transient overlays composited onto the page content,
    /// so the layout footprint is the base `content`.
    package func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - The modifier

extension View {
    /// Draws the environment's notifications over this view, as every scene
    /// draws them over its content: for a test that renders a view with no
    /// scene around it. An app needs nothing — its scenes host notifications —
    /// and this inside a scene would draw each toast twice.
    nonisolated package func notificationHost() -> some View {
        NotificationHostModifier(content: self)
    }
}
