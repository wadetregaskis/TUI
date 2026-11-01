//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowInteractionBehavior.swift
//
//  SwiftUI's `WindowInteractionBehavior` and `windowDismissBehavior(_:)`:
//  whether the person can close the window a view is in.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - The Behavior

/// Options for enabling and disabling window interaction behaviors — mirrors
/// SwiftUI's `WindowInteractionBehavior`.
///
/// Used with ``View/windowDismissBehavior(_:)``: the one window interaction a
/// terminal app's windows have, closing (Escape, or the menu bar's Window ▸
/// Close Window, on a window opened over another). Minimising, resizing, full
/// screen and dragging a window by its background are the terminal emulator's,
/// and their modifiers do not compile here.
public struct WindowInteractionBehavior: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic, enabled, disabled
    }

    private let kind: Kind

    /// The automatic behavior: enabled or disabled by the enclosing scene —
    /// for dismissal, enabled.
    public static let automatic = Self(kind: .automatic)

    /// The enabled behavior.
    public static let enabled = Self(kind: .enabled)

    /// The disabled behavior.
    public static let disabled = Self(kind: .disabled)
}

// MARK: - The Modifier

extension View {
    /// Configures the dismiss functionality for the window enclosing this view
    /// — mirrors SwiftUI's `windowDismissBehavior(_:)`.
    ///
    /// ```swift
    /// Window("Welcome", id: "welcome") {
    ///     WelcomeView()
    ///         .windowDismissBehavior(.disabled)
    /// }
    /// ```
    ///
    /// `.disabled` takes away the person's ways to close the window — Escape,
    /// which closes a window opened over another, and the menu bar's Window ▸
    /// Close Window — as macOS takes away its close button and ⌘W. The app can
    /// still close it, with `dismissWindow`.
    ///
    /// - Parameter behavior: The dismiss behavior.
    /// - Returns: A view whose window closes only as `behavior` allows.
    nonisolated public func windowDismissBehavior(_ behavior: WindowInteractionBehavior) -> some View {
        _WindowDismissBehaviorModifier(content: self, behavior: behavior)
    }
}

/// Declares the window's dismiss behavior into its chrome as `content`
/// renders, as `.toolbarVisibility` declares a bar's visibility: afresh every
/// walk, the declaration closest to the content winning.
nonisolated struct _WindowDismissBehaviorModifier<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let behavior: WindowInteractionBehavior

    @MainActor var body: Never { fatalError("_WindowDismissBehaviorModifier renders via Renderable") }

    @MainActor func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Declared by the walk that seeds a new window's chrome too, measuring
        // as it is, as `.toolbar` declares there: the window is closable or not
        // from its first frame.
        if !context.isMeasuring || context.environment.seedsWindowChrome,
            let chrome = context.environment.windowChrome
        {
            // Declared afresh by every walk: a memoised ancestor serving its
            // buffer would leave the window without the statement.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            chrome.declareDismissBehavior(behavior)
        }
        return TUIView.renderToBuffer(content, context: context)
    }

    /// Transparent: it measures as its content.
    @MainActor func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
