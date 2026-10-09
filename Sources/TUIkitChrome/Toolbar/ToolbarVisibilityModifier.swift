//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarVisibilityModifier.swift
//
//  `.toolbarVisibility(_:for:)`: a view's say in whether a window bar is shown.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Public Modifier

extension View {
    /// Specifies the visibility of a bar managed by the window — mirrors
    /// SwiftUI's `toolbarVisibility(_:for:)`.
    ///
    /// The preferred visibility flows up to the window, as it does on macOS:
    /// ``Visibility/hidden`` takes the bar away — its items, and the rows they
    /// held, a frame later, as any change to the window's bars is adopted —
    /// and ``Visibility/visible`` or ``Visibility/automatic`` leave it to
    /// what is placed in it (a bar with nothing in it is not drawn either way).
    /// When several views state one, the one declared last — the one closest
    /// to the content it wraps — wins.
    ///
    /// ```swift
    /// ContentView()
    ///     .toolbarVisibility(.hidden, for: .bottomBar)
    /// ```
    ///
    /// Hiding the bottom bar hides the line of key hints a `StatusBar()` there
    /// draws, not the keys: they still work. A hidden bar's items keep their
    /// `@State`, so the bar comes back as it went.
    ///
    /// In presented content — a sheet's, a full-screen cover's, a popover's —
    /// it states nothing. The presentation draws its own `.toolbar` items (see
    /// ``ToolbarItemPlacement``), and the window's bars are not its to hide: a
    /// sheet that hid the bottom bar took away the line of key hints that says
    /// how to close it.
    ///
    /// - Parameters:
    ///   - visibility: The preferred visibility of the bar.
    ///   - bars: The bars to update: ``ToolbarPlacement/windowToolbar`` (or
    ///     ``ToolbarPlacement/automatic``, or none at all) for the top bar,
    ///     ``ToolbarPlacement/bottomBar`` for the bottom one.
    /// - Returns: A view whose bars' preferred visibility is `visibility`.
    public func toolbarVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        _ToolbarVisibilityModifier(content: self, visibility: visibility, bars: bars)
    }
}

// MARK: - The Modifier

/// Declares a bar visibility into the window's chrome as `content` renders —
/// on the drawn walk, and on the first frame's seeding walk, as `.toolbar`
/// declares its items.
struct _ToolbarVisibilityModifier<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let visibility: Visibility
    let bars: [ToolbarPlacement]

    var body: Never { fatalError("_ToolbarVisibilityModifier renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Not from presented content: a sheet's toolbar is the sheet's
        // (`ToolbarPresentationRows.swift`), and a sheet hiding the window's
        // bottom bar took the line of key hints that says how to close it.
        if !context.environment.presentationHostsToolbar,
            let chrome = context.environment.windowChrome,
            !context.isMeasuring || context.environment.seedsWindowChrome
        {
            // Declared afresh by every walk: a memoised ancestor serving its
            // buffer would leave the window without the statement.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            for bar in bars.isEmpty ? [.automatic] : bars {
                chrome.declare(visibility, for: bar.edge == .bottom ? .bottom : .top)
            }
        }
        return TUIkitView.renderToBuffer(content, context: context)
    }

    /// The statement is the window's, so this measures as `content`.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a z-index or a container value (a `.tag`) written
/// inside it still reaches the container around it — see `_ToolbarModifier`'s
/// conformance. Read-only: not ``ContentRewrapping``.
extension _ToolbarVisibilityModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}
