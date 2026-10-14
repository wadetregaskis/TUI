//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarRemovalModifier.swift
//
//  `View.toolbar(removing:)`: take away a control the framework provides by
//  default. TUIkit's window bars hold what a `.toolbar` places in them (see
//  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` §2.6) and the
//  title; the default items are the split view's sidebar toggle, which lives on
//  the split itself, and the title, in the top bar's title slot and on a
//  navigation stack's bar.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Storage

/// Whether a ``View/toolbar(removing:)`` inside a split view's column removed the
/// sidebar toggle. A preference, because the modifier may sit anywhere inside
/// the column and the split view reads it from outside; `true` wins.
struct SidebarToggleRemovedKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct SidebarToggleRemovedEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

/// Whether a ``View/toolbar(removing:)`` inside a navigation stack's pushed
/// screen removed the title. A preference, because the modifier may sit
/// anywhere in the screen and the stack reads the screen's preferences to draw
/// its bar; `true` wins.
struct ToolbarTitleRemovedKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct ToolbarTitleRemovedEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether a ``View/toolbar(removing:)`` on or above this view removed a
    /// split view's sidebar toggle.
    var sidebarToggleRemoved: Bool {
        get { self[SidebarToggleRemovedEnvironmentKey.self] }
        set { self[SidebarToggleRemovedEnvironmentKey.self] = newValue }
    }

    /// Whether a ``View/toolbar(removing:)`` on or above this view removed the
    /// title, for a navigation stack it holds.
    var toolbarTitleRemoved: Bool {
        get { self[ToolbarTitleRemovedEnvironmentKey.self] }
        set { self[ToolbarTitleRemovedEnvironmentKey.self] = newValue }
    }
}

// MARK: - Modifier

/// Publishes a removal into the enclosing preference scope — the sidebar
/// toggle's for a split view whose column holds it, the title's for a
/// navigation stack whose screen holds it — declares a title's to the window's
/// chrome, and renders `content` unchanged.
struct ToolbarRemovalView<Content: View>: View {
    let content: Content

    /// What this modifier removes; `nil`, which publishes nothing, for `nil`.
    let removes: ToolbarDefaultItemKind.Kind?

    var body: Never {
        fatalError("ToolbarRemovalView renders via Renderable")
    }

    /// Declared as a per-pass side effect for the reason
    /// `NavigationSplitViewColumnWidthView` declares its write: a memoising
    /// ancestor serving a cached buffer or measurement would drop the write, and
    /// the split view would put its toggle back.
    private func publish(context: RenderContext) {
        guard let removes else { return }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        switch removes {
        case .sidebarToggle:
            context.environment.preferenceStorage?.setValue(true, forKey: SidebarToggleRemovedKey.self)
        case .title:
            context.environment.preferenceStorage?.setValue(true, forKey: ToolbarTitleRemovedKey.self)
            windowChrome(context)?.removeTitle()
        case .search:
            windowChrome(context)?.removeSearchField()
        }
    }

    /// The window's chrome, to tell of a removal this walk, as a
    /// `.navigationTitle` offers it a title (`PreferenceModifier`): on a drawn
    /// walk, and on the first frame's seeding walk, which measures — the top
    /// bar's rows depend on whether there is a title, and a bar's on whether a
    /// search field is in it. `nil` in presented content, whose removal is the
    /// presentation's, not the window's.
    private func windowChrome(_ context: RenderContext) -> WindowChromeState? {
        guard !context.isMeasuring || context.environment.seedsWindowChrome,
            !context.environment.presentationHostsToolbar
        else { return nil }
        return context.environment.windowChrome
    }
}

extension ToolbarRemovalView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        publish(context: context)
        return TUIkitView.renderToBuffer(content, context: context)
    }
}

extension ToolbarRemovalView: Layoutable {
    /// Publishes during a measure too: the split view measures a column to learn
    /// what it asked for before it lays the handles out. The keys' `reduce` is
    /// an OR, so publishing twice in a pass is idempotent, and so is declaring
    /// the title's removal to the window's chrome.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        publish(context: context)
        return measureChild(content, proposal: proposal, context: context)
    }
}

extension View {
    /// Removes a control the framework provides by default.
    ///
    /// With ``ToolbarDefaultItemKind/sidebarToggle`` it removes a
    /// ``NavigationSplitView``'s toggle handles: the ◀ on its leftmost divider
    /// (which goes back to three grip dots, or to a plain space when the split
    /// cannot resize) and the ▶ edge column shown while a leading column is
    /// hidden. `nil` removes nothing, and does not undo a removal further out.
    ///
    /// With ``ToolbarDefaultItemKind/title`` it removes the title: the top
    /// bar's title slot is empty while the view is drawn — anywhere in the
    /// window but in presented content, as one toolbar's title item serves the
    /// whole window in SwiftUI — and a ``NavigationStack``'s bar over a pushed
    /// screen draws its Back button alone, without the screen's title, its
    /// subtitle or the trail, where the modifier is in that screen or on or
    /// above the stack. The window's title is still the outermost
    /// `.navigationTitle`, which a terminal window's title would be set from;
    /// only the title item goes.
    ///
    /// With ``ToolbarDefaultItemKind/search`` it removes the search field a
    /// `searchable` modifier draws, wherever it would be drawn — at the top of
    /// the view, or in a bar a ``DefaultToolbarItem`` placed it in — when the
    /// modifier is on or above the searchable, or drawn anywhere else in the
    /// window but in presented content. With no field drawn nothing can take
    /// the focus to it, so `isSearching` stays `false`; the query binding is
    /// the app's still.
    ///
    /// ```swift
    /// NavigationSplitView {
    ///     Sidebar()
    ///         .toolbar(removing: .sidebarToggle)
    /// } detail: {
    ///     Detail()
    /// }
    /// ```
    ///
    /// The modifier works on the split view, anywhere above it, or anywhere
    /// inside one of its columns. A hidden column is not rendered, so the split
    /// view remembers what each column said the last time it was shown. A split
    /// that is hidden from its very first frame has never shown its leading
    /// columns, so put the modifier on the split view or in the detail column.
    ///
    /// Removing the handles does not change what `columnVisibility` can do from
    /// code.
    ///
    /// The window's bars put no default item of their own beside what a
    /// `.toolbar` places in them and the title, so those and the split view's
    /// handles are all there is to remove (see
    /// `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` §2.6).
    ///
    /// - Parameter defaultItemKind: The kind of control to remove, or `nil`.
    /// - Returns: A view whose window and split views omit that control.
    public func toolbar(removing defaultItemKind: ToolbarDefaultItemKind?) -> some View {
        // Reduced to its kind, and that to Bools, before it reaches the
        // environment or the preference store, neither of which should hold a
        // non-Sendable value.
        let removes = defaultItemKind?.kind
        return ToolbarRemovalView(
            content: transformEnvironment(\.sidebarToggleRemoved) { removed in
                if removes == .sidebarToggle { removed = true }
            }
            .transformEnvironment(\.toolbarTitleRemoved) { removed in
                if removes == .title { removed = true }
            }
            .transformEnvironment(\.toolbarSearchRemoved) { removed in
                if removes == .search { removed = true }
            },
            removes: removes)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension ToolbarRemovalView: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension ToolbarRemovalView: DrawsContentUnchanged {}
