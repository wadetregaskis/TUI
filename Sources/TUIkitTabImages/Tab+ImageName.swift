//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Tab+ImageName.swift
//
//  `Tab("Settings", image: "gear") { … }`: a tab whose label's picture is an
//  image resource named by a string, found as `Image(_:bundle:)` finds it, as
//  `Label(_:image:)`'s is. Declared in a module of its own, built on
//  TUIkitBitmaps (finding the name is the bitmap path's) and TUIkitTabs, so
//  that an app showing images pays nothing for tabs and one using tabs nothing
//  for image decoding (decisions C11, the owner's TAB-IMAGE-NAME option 2).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitBitmaps
import TUIkitFoundation
import TUIkitTabs

// MARK: - Selected by a value

extension Tab where Label == DefaultTabLabel {
    /// Creates a tab with a localized title and an image resource, selected
    /// by `value` — mirrors SwiftUI's `init(_:image:value:role:content:)`.
    ///
    /// The image is found as ``Image/init(_:bundle:)`` finds it, a plain image
    /// file among the main bundle's resources, as ``Label``'s
    /// `init(_:image:)` finds its icon. A `.sidebarAdaptable` sidebar's row
    /// draws it in the two cells a symbol takes, before the title; a strip's
    /// chip draws the title alone, as it does for a symbol the terminal cannot
    /// draw.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the tab's title — a literal is looked up, see
    ///     ``LocalizedStringKey``.
    ///   - image: The name of the image resource.
    ///   - value: The selection value that selects this tab.
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    public init(
        _ titleKey: LocalizedStringKey, image: String, value: Value, role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: value, role: role,
            label: DefaultTabLabel(title: titleKey.titleWords, systemImage: nil, image: Image(image)),
            content: content())
    }

    /// Creates a tab with a title shown as written and an image resource,
    /// selected by `value` — see
    /// ``init(_:image:value:role:content:)-(LocalizedStringKey,_,Value,_,_)``.
    ///
    /// - Parameters:
    ///   - title: The tab's title.
    ///   - image: The name of the image resource.
    ///   - value: The selection value that selects this tab.
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S, image: String, value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: value, role: role,
            label: DefaultTabLabel(title: String(title), systemImage: nil, image: Image(image)),
            content: content())
    }

    /// Creates a tab with a localized title and an image resource, selected
    /// by `value` in a tab view whose selection is optional.
    public init<T: Hashable>(
        _ titleKey: LocalizedStringKey, image: String, value: T, role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) where Value == T? {
        self.init(
            value: value, role: role,
            label: DefaultTabLabel(title: titleKey.titleWords, systemImage: nil, image: Image(image)),
            content: content())
    }

    /// Creates a tab with a title shown as written and an image resource,
    /// selected by `value` in a tab view whose selection is optional.
    @_disfavoredOverload
    public init<S: StringProtocol, T: Hashable>(
        _ title: S, image: String, value: T, role: TabRole? = nil, @ViewBuilder content: () -> Content
    ) where Value == T? {
        self.init(
            value: value, role: role,
            label: DefaultTabLabel(title: String(title), systemImage: nil, image: Image(image)),
            content: content())
    }
}

// MARK: - Selected by place

extension Tab where Value == Never, Label == DefaultTabLabel {
    /// Creates a tab with a localized title and an image resource, in a tab
    /// view without a selection — mirrors SwiftUI's
    /// `init(_:image:role:content:)`.
    ///
    /// The image is found and drawn as
    /// ``init(_:image:value:role:content:)-(LocalizedStringKey,_,Value,_,_)``'s.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the tab's title.
    ///   - image: The name of the image resource.
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    public init(
        _ titleKey: LocalizedStringKey, image: String, role: TabRole? = nil, @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: nil, role: role,
            label: DefaultTabLabel(title: titleKey.titleWords, systemImage: nil, image: Image(image)),
            content: content())
    }

    /// Creates a tab with a title shown as written and an image resource, in
    /// a tab view without a selection.
    ///
    /// - Parameters:
    ///   - title: The tab's title.
    ///   - image: The name of the image resource.
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S, image: String, role: TabRole? = nil, @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: nil, role: role,
            label: DefaultTabLabel(title: String(title), systemImage: nil, image: Image(image)),
            content: content())
    }
}
