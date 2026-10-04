//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Inspector.swift
//
//  `inspector(isPresented:content:)` and `inspectorColumnWidth`: a trailing
//  column beside a view, shown and hidden by a binding.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Modifiers

extension View {
    /// Inserts an inspector at the applied position in the view hierarchy.
    /// Mirrors SwiftUI's `inspector(isPresented:content:)`.
    ///
    /// ```swift
    /// Editor()
    ///     .inspector(isPresented: $showingInspector) {
    ///         TextTraits()
    ///             .inspectorColumnWidth(28)
    ///     }
    /// ```
    ///
    /// The inspector is a trailing column, as on macOS in a regular size class:
    /// the view and the inspector side by side, with a divider between them
    /// that the reader can move — it is a focus stop (Left and Right move it a
    /// cell, five with Shift) and the pointer drags it, as an ``HSplitView``'s
    /// is. The column starts at the width ``View/inspectorColumnWidth(_:)``
    /// names, or 30 columns. The view keeps its state while the inspector
    /// comes and goes.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the inspector is shown.
    ///   - content: The inspector's content.
    public func inspector<V: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> V) -> some View {
        _InspectorModifier(content: self, isPresented: isPresented, inspector: content())
    }

    /// Sets a fixed, preferred width for the inspector containing this view.
    /// Mirrors SwiftUI's `inspectorColumnWidth(_:)`.
    ///
    /// Apply it to the inspector's **content**. The width is in columns, as a
    /// terminal measures (§2.1 of the compatibility doc). As on macOS, a fixed
    /// width is where the column starts, and the reader can still move the
    /// divider.
    ///
    /// - Parameter width: The inspector column's width, in columns.
    public func inspectorColumnWidth(_ width: Int) -> some View {
        _InspectorColumnWidthView(content: self, ideal: width)
    }

    /// Sets a flexible, preferred width for the inspector containing this
    /// view. Mirrors SwiftUI's `inspectorColumnWidth(min:ideal:max:)`.
    ///
    /// The column starts at `ideal`. The divider is not held between `min` and
    /// `max` — SwiftUI documents that a platform may use a different width than
    /// asked — so they are accepted and the reader can move it anywhere the
    /// split allows (decisions B40).
    ///
    /// - Parameters:
    ///   - min: The narrowest the column should be, in columns.
    ///   - ideal: The width the column starts at, in columns.
    ///   - max: The widest the column should be, in columns.
    public func inspectorColumnWidth(min: Int? = nil, ideal: Int, max: Int? = nil) -> some View {
        _ = (min, max)
        return _InspectorColumnWidthView(content: self, ideal: ideal)
    }
}

// MARK: - The inspector

/// The view and its inspector, as the two panes of a horizontal split.
///
/// The view is the split's first child whether or not the inspector shows, so
/// its identity — and with it its `@State` — survives the inspector coming and
/// going.
struct _InspectorModifier<Content: View, Inspector: View>: View {
    let content: Content
    let isPresented: Binding<Bool>
    let inspector: Inspector

    /// The column's width when the content names none — about the 270 points
    /// macOS opens an inspector at, in nine-point columns.
    static var defaultWidth: Int { 30 }

    var body: some View {
        let width =
            presentationTrait(InspectorColumnWidthProviding.self, of: inspector)?.idealWidth
            ?? Self.defaultWidth
        return HSplitView {
            // The view takes what the column leaves: a split gives a pane that
            // fills the rest, and two that hug an even share each.
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if isPresented.wrappedValue {
                inspector.frame(width: Swift.max(1, width))
            }
        }
    }
}

/// Content that has named its inspector column's width.
@MainActor
protocol InspectorColumnWidthProviding {
    var idealWidth: Int { get }
}

/// The wrapper ``View/inspectorColumnWidth(_:)`` produces. Renders and
/// measures as its content; carrying the width is its whole job.
struct _InspectorColumnWidthView<Content: View>: View, InspectorColumnWidthProviding {
    let content: Content
    let ideal: Int

    var idealWidth: Int { ideal }

    var body: Never {
        fatalError("_InspectorColumnWidthView renders via Renderable")
    }
}

extension _InspectorColumnWidthView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(content, context: context)
    }
}

extension _InspectorColumnWidthView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// Seen through like the presentation traits, so the width is found with an
/// `interactiveDismissDisabled()` either side of it, as SwiftUI's example
/// writes them.
extension _InspectorColumnWidthView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``.
extension _InspectorColumnWidthView: SingleContentWrapper {
    var wrappedContent: Content { content }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _InspectorColumnWidthView: DrawsContentUnchanged {}
