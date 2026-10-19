//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Inspector.swift
//
//  `inspector(isPresented:content:)` and `inspectorColumnWidth`: a trailing
//  column beside a view, shown and hidden by a binding.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
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
    /// names, or 30 columns, and the divider stops at the minimum and maximum
    /// ``View/inspectorColumnWidth(min:ideal:max:)`` names. The view keeps its
    /// state while the inspector comes and goes.
    ///
    /// The divider's middle row is a ▶ that hides the inspector — a still click
    /// on it, or Return or Space with the divider focused — writing `false`
    /// through `isPresented`, as a split view's leftmost divider carries a ◀.
    /// To show it again, an app gives the reader a control of its own, as in
    /// SwiftUI, or places TUIkit's `DefaultToolbarItem(kind: .inspectorToggle)`
    /// in a bar: a button that hides and shows the inspector it is declared
    /// round or in, else the window's first. The window puts none in its bars
    /// by default, as SwiftUI puts none in a toolbar. `.toolbar(removing:
    /// .inspectorToggle)` on or above this view takes the ▶ and the buttons
    /// away.
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
    /// The column starts at `ideal`, and the divider stops where the column
    /// would be narrower than `min` or wider than `max` — the bounds an
    /// ``HSplitView`` pane's frame states, which is what the inspector's
    /// column is. With too little room for `min`, the column gives way.
    ///
    /// - Parameters:
    ///   - min: The narrowest the column should be, in columns.
    ///   - ideal: The width the column starts at, in columns.
    ///   - max: The widest the column should be, in columns.
    public func inspectorColumnWidth(min: Int? = nil, ideal: Int, max: Int? = nil) -> some View {
        _InspectorColumnWidthView(content: self, minimum: min, ideal: ideal, maximum: max)
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
        let width = presentationTrait(InspectorColumnWidthProviding.self, of: inspector)
        let ideal = Swift.max(1, width?.idealWidth ?? Self.defaultWidth)
        return _InspectorToggleHost(isPresented: isPresented) {
            HSplitView {
            // The view takes what the column leaves: a split gives a pane that
            // fills the rest, and two that hug an even share each.
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if isPresented.wrappedValue {
                // The split reads the column's bounds off this frame: it starts
                // at the ideal width, and the divider stops at the others.
                inspector.frame(
                    minWidth: width?.minimumWidth, idealWidth: ideal,
                    maxWidth: width?.maximumWidth.map { .fixed($0) } ?? .infinity, alignment: .topLeading)
            }
            }
        }
    }
}

// MARK: - The inspector's toggle

/// Publishes an inspector's toggle round the view and its inspector, so a
/// `DefaultToolbarItem(kind: .inspectorToggle)` declared in either toggles this
/// inspector; offers it to the window, for one declared round it; and hands it
/// to the split's last divider, which draws a ▶ that hides the inspector.
///
/// Renders its content at its own identity, so its one slot is in the range
/// reserved for it (`StateStorage.StateKey`).
///
/// None of it where `.toolbar(removing: .inspectorToggle)` is on or above it,
/// or it is disabled, or measuring — and then a toolbar item declared inside
/// reaches no inspector further out.
struct _InspectorToggleHost<Content: View>: View, Renderable, Layoutable {
    let isPresented: Binding<Bool>
    let content: Content

    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.isPresented = isPresented
        self.content = content()
    }

    var body: Never { fatalError("_InspectorToggleHost renders via Renderable") }

    /// `context` for the content, with the inspector's toggle published.
    private func toggling(_ context: RenderContext) -> RenderContext {
        var inner = context
        inner.environment.inspectorToggleScope = .split(nil)
        inner.environment.trailingPaneToggle = nil
        guard !context.isMeasuring, context.environment.isEnabled, !context.environment.inspectorToggleRemoved,
            let storage = context.stateStorage
        else { return inner }
        storage.markActive(context.identity)
        let action = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: InspectorToggleStateIndex.action),
            default: PanelToggle.Action()
        ).value
        let binding = isPresented
        action.perform = { binding.wrappedValue.toggle() }
        let toggle = PanelToggle(
            panel: .inspector, owner: context.identity, isShown: binding.wrappedValue, action: action)
        PanelToggleOffer.offer(
            toggle, itemIdentity: context.withChildIdentity(erasedType: _InspectorToggleItemSlot.self, key: "bar").identity,
            context: context)
        inner.environment.inspectorToggleScope = .split(toggle)
        if toggle.isShown { inner.environment.trailingPaneToggle = toggle }
        return inner
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: toggling(context))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: toggling(context))
    }
}

/// The identity step a window's button for an inspector takes under the
/// inspector's.
enum _InspectorToggleItemSlot {}

/// ``_InspectorToggleHost``'s `StateStorage` slots, at file scope because a
/// generic type cannot hold static stored properties.
private enum InspectorToggleStateIndex {
    /// The toggle's ``PanelToggle/Action``, kept so each render's toggle
    /// compares equal to the last while the inspector neither shows nor hides.
    static let action = -160
}

/// Content that has named its inspector column's width.
@MainActor
protocol InspectorColumnWidthProviding {
    var minimumWidth: Int? { get }
    var idealWidth: Int { get }
    var maximumWidth: Int? { get }
}

/// The wrapper ``View/inspectorColumnWidth(_:)`` produces. Renders and
/// measures as its content; carrying the width is its whole job.
struct _InspectorColumnWidthView<Content: View>: View, InspectorColumnWidthProviding {
    let content: Content
    var minimum: Int?
    let ideal: Int
    var maximum: Int?

    var minimumWidth: Int? { minimum }
    var idealWidth: Int { ideal }
    var maximumWidth: Int? { maximum }

    var body: Never {
        fatalError("_InspectorColumnWidthView renders via Renderable")
    }
}

extension _InspectorColumnWidthView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: context)
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

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _InspectorColumnWidthView: DrawsContentUnchanged {}
/// Measures its content in the context it is given, so an alignment guide
/// inside it is asked through it — see `HandsContentItsContext`.
extension _InspectorColumnWidthView: HandsContentItsContext {}
