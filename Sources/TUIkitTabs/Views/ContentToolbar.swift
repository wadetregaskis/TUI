//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentToolbar.swift
//
//  `.contentToolbar(for:content:)`: toolbar content a container's own view
//  keeps, whatever content it shows — the foot of a tab view's sidebar.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Content Toolbar Placement

/// The kind of content view whose toolbar ``View/contentToolbar(for:content:)``
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
    /// the other iOS placements TUIkit reads, it is the same sidebar on every
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
        let toolbar = AnyView(HStack(spacing: 1) { content() })
        return _TabViewSidebarAccessoryModifier(content: self) { $0.toolbar = toolbar }
    }
}
