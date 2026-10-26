//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarItemHiddenModifier.swift
//
//  `.toolbarItemHidden(_:)`: one view of a toolbar item hidden, the rest of the
//  item drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Public Modifier

extension View {
    /// Hides an individual view within a control group toolbar item — mirrors
    /// SwiftUI's `toolbarItemHidden(_:)`.
    ///
    /// Inside a toolbar item — a `ControlGroup`'s button, one of a
    /// ``ToolbarItemGroup``'s views — a hidden view takes no room and draws
    /// nothing, and the item's other views close up round it; its `@State` is
    /// kept for when it shows again. Anywhere else it changes nothing, as in
    /// SwiftUI, where the modifier speaks only to a toolbar.
    ///
    /// ```swift
    /// ToolbarItem(id: "share") {
    ///     ControlGroup {
    ///         ShareButton()
    ///         CollaborationButton()
    ///             .toolbarItemHidden(!inCollaboration)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter hidden: Whether the view in a control group toolbar item is
    ///   hidden.
    /// - Returns: The view, hidden within its toolbar item if `hidden`.
    public func toolbarItemHidden(_ hidden: Bool = true) -> some View {
        _ToolbarItemHiddenModifier(content: self, isHidden: hidden)
    }
}

// MARK: - Where a View Is Drawn

/// Environment key for whether a view is drawn as part of a toolbar item.
private struct DrawsToolbarItemKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether this view is drawn as part of a toolbar item — in one of the
    /// window's bars or a presentation's rows (`_ToolbarEntryView`) — which is
    /// where `.toolbarItemHidden(_:)` hides it.
    var drawsToolbarItem: Bool {
        get { self[DrawsToolbarItemKey.self] }
        set { self[DrawsToolbarItemKey.self] = newValue }
    }
}

// MARK: - The Modifier

/// Draws `content`, or — hidden inside a toolbar item — nothing, keeping its
/// state.
struct _ToolbarItemHiddenModifier<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let isHidden: Bool

    var body: Never { fatalError("_ToolbarItemHiddenModifier renders via Renderable") }

    /// Whether the view is hidden where it is drawn.
    private func hides(in context: RenderContext) -> Bool {
        isHidden && context.environment.drawsToolbarItem
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard hides(in: context) else { return TUIView.renderToBuffer(content, context: context) }
        // Undrawn, so its state would be collected at the end of the pass:
        // kept, as a hidden bar keeps its items' (`retainUndrawnItems`). The
        // content renders at this modifier's own identity.
        if !context.isMeasuring, let storage = context.stateStorage {
            storage.markActive(context.identity)
            storage.retainSubtree(context.identity)
        }
        return FrameBuffer()
    }

    /// No room at all while hidden, so a stack closes up round it.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard hides(in: context) else { return measureChild(content, proposal: proposal, context: context) }
        return ViewSize(width: 0, height: 0)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a z-index or a container value written inside it
/// still reaches the container around it. Read-only: not
/// ``ContentRewrapping``.
extension _ToolbarItemHiddenModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}
