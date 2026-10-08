//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InteractiveDismissDisabled.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// The wrapper ``View/interactiveDismissDisabled(_:)`` produces. Renders and
/// measures as its content; carrying the flag is its whole job.
struct _InteractiveDismissView<Content: View>: View, InteractiveDismissDisabling {
    let content: Content
    let interactiveDismissIsDisabled: Bool

    var body: Never {
        fatalError("_InteractiveDismissView renders via Renderable")
    }
}

extension _InteractiveDismissView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(content, context: context)
    }
}

extension _InteractiveDismissView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _InteractiveDismissView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

extension View {
    /// Conditionally prevents a presentation from being dismissed by hand.
    ///
    /// Mirrors SwiftUI's `interactiveDismissDisabled(_:)`. Apply it to the
    /// presented **content**:
    ///
    /// ```swift
    /// .sheet(isPresented: $editing) {
    ///     Editor()
    ///         .interactiveDismissDisabled(hasUnsavedChanges)
    /// }
    /// ```
    ///
    /// SwiftUI's gesture is a downward swipe; a terminal's are **Escape** and a
    /// click outside, so those are what this suppresses. Everything else still
    /// closes the presentation: a `Done` button flipping the binding,
    /// `@Environment(\.dismiss)`, or the app setting it to `false` — which is
    /// the point of the modifier, not a gap in it. It is how a sheet insists on
    /// an answer rather than letting the reader wander off.
    ///
    /// A dismissal-disabled popover still swallows the click that lands outside
    /// it. Letting that click through to the page would be the opposite of what
    /// was asked for: the presentation stays up and something behind it acts.
    ///
    /// Alerts and confirmation dialogs are unaffected. Escape there does not
    /// dismiss anything — it CHOOSES the `.cancel`-role button, which is an
    /// answer, and an answer is not something this modifier takes away.
    ///
    /// - Parameter isDisabled: Whether to prevent interactive dismissal.
    ///   Default `true`.
    public func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View {
        _InteractiveDismissView(content: self, interactiveDismissIsDisabled: isDisabled)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _InteractiveDismissView: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _InteractiveDismissView: DrawsContentUnchanged {}
