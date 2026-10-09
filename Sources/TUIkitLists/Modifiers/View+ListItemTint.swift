//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+ListItemTint.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitStyling
import TUIkitView

extension View {
    /// Sets the tint effect for content in a list.
    ///
    /// A ``SidebarListStyle`` list draws its rows' `Label` icons in the tint
    /// (the accent when none is set), as macOS sidebars do; the other styles
    /// leave icons in their row's foreground, as macOS's do.
    ///
    /// - Parameter tint: The tint effect to use, or `nil` to keep the inherited
    ///   tint.
    public func listItemTint(_ tint: ListItemTint?) -> some View {
        transformEnvironment(\.listItemTint) { current in
            if let tint { current = tint }
        }
    }

    /// Sets a fixed tint color for content in a list: the same as
    /// ``listItemTint(_:)-(ListItemTint?)`` with ``ListItemTint/fixed(_:)``.
    ///
    /// - Parameter tint: The color to use to tint the content, or `nil` to keep
    ///   the inherited tint.
    public func listItemTint(_ tint: Color?) -> some View {
        listItemTint(tint.map { ListItemTint.fixed($0) })
    }
}
