//  🖥️ TUI — A Terminal UI framework for Swift
//  ContentToolbar.swift
//
//  `.contentToolbar(for:content:)`: toolbar content a container's own view
//  keeps, whatever content it shows — the foot of a tab view's sidebar.
//
//  Here, below the tab view (TUITabs) that draws it and the toolbar content
//  (TUIChrome) that one of the two modifiers takes: each of those modules
//  sees this one, and neither sees the other.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIView

// MARK: - Content Toolbar Placement

/// The kind of content view whose toolbar ``View/contentToolbar(for:content:)-kus4``
/// populates — mirrors SwiftUI's `ContentToolbarPlacement`.
public struct ContentToolbarPlacement: Hashable, Sendable {
    /// The content views a content toolbar can be placed on.
    private enum Kind: Hashable, Sendable {
        case tabViewSidebar
    }

    private let kind: Kind

    /// The sidebar of a `.sidebarAdaptable` tab view: its toolbar is a row at
    /// the foot of the sidebar, under its tabs and its footer, above its
    /// bottom bar.
    ///
    /// SwiftUI's iPadOS spelling, which macOS marks unavailable; here, as for
    /// the other iOS placements TUI reads, it is the same sidebar on every
    /// platform, so ported iPad code keeps its sidebar toolbar.
    public static let tabViewSidebar = Self(kind: .tabViewSidebar)
}

// MARK: - Public Modifier

extension View {
    /// Populates the toolbar of the specified content view type with the views
    /// you provide — mirrors SwiftUI's `contentToolbar(for:content:)`.
    ///
    /// Toolbar content that stays the same whichever content the container
    /// shows. For ``ContentToolbarPlacement/tabViewSidebar``, a row of the
    /// views, one column apart, at the foot of a `.sidebarAdaptable` tab view's
    /// sidebar — under its tabs, whichever tab is selected:
    ///
    /// ```swift
    /// TabView {
    ///     Tab("Inbox", systemImage: "tray") { InboxView() }
    ///     Tab("Sent", systemImage: "paperplane") { SentView() }
    /// }
    /// .tabViewStyle(.sidebarAdaptable)
    /// .contentToolbar(for: .tabViewSidebar) {
    ///     Button("New Mailbox", systemImage: "plus") { addMailbox() }
    /// }
    /// ```
    ///
    /// Shown only by a `.sidebarAdaptable` tab view, as the sidebar's header
    /// and footer are; a tab view drawing a strip, or a compact size class's,
    /// has no sidebar to put it in.
    ///
    /// - Parameters:
    ///   - placement: The content view whose toolbar to populate.
    ///   - content: The views of the toolbar.
    /// - Returns: A view whose tab view sidebar's toolbar holds `content`.
    public func contentToolbar<Content: View>(
        for placement: ContentToolbarPlacement, @ViewBuilder content: () -> Content
    ) -> some View {
        contentToolbar(for: placement, drawing: AnyView(HStack(spacing: 1) { content() }))
    }

    /// Makes `toolbar` the content toolbar of `placement`'s content views:
    /// what both forms of ``contentToolbar(for:content:)`` — the views', and
    /// the toolbar content's (TUIChrome) — hand the tab view sidebar.
    package func contentToolbar(for placement: ContentToolbarPlacement, drawing toolbar: AnyView) -> some View {
        _ContentToolbarModifier(content: self, toolbar: toolbar)
    }
}

// MARK: - Environment

/// Environment key for the toolbar a tab view's sidebar draws at its foot.
private struct TabViewSidebarToolbarKey: EnvironmentKey {
    // Computed: a stored view is not `Sendable`, and this is `nil`.
    static var defaultValue: AnyView? { nil }
}

extension EnvironmentValues {
    /// The toolbar a `.sidebarAdaptable` tab view's sidebar draws at its foot
    /// (``View/contentToolbar(for:content:)``), or `nil` for none.
    ///
    /// Written straight into the environment, as the sidebar's header and
    /// footer are (TUITabs), rather than through an environment modifier: a
    /// view cannot be compared, and an incomparable value would turn every
    /// memo below the tab view off. Only the sidebar reads it, and it draws
    /// it every frame.
    package var tabViewSidebarToolbar: AnyView? {
        get { self[TabViewSidebarToolbarKey.self] }
        set { self[TabViewSidebarToolbarKey.self] = newValue }
    }
}

// MARK: - The Modifier

/// Sets the tab view sidebar's toolbar for `content`.
struct _ContentToolbarModifier<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let toolbar: AnyView

    var body: Never { fatalError("_ContentToolbarModifier renders via Renderable") }

    private func withToolbar(_ context: RenderContext) -> RenderContext {
        var context = context
        context.environment.tabViewSidebarToolbar = toolbar
        return context
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: withToolbar(context))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: withToolbar(context))
    }
}
