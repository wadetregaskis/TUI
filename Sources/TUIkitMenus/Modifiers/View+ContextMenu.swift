//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+ContextMenu.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

// MARK: - View extension

extension View {
    /// Adds a context menu (right-click / Ctrl-click pop-up of `Button`s) to this
    /// view — mirrors SwiftUI's `contextMenu(menuItems:)`.
    ///
    /// ```swift
    /// Text("Right-click me")
    ///     .contextMenu {
    ///         Button("Cut") { … }
    ///         Button("Copy") { … }
    ///         Divider()
    ///         Button("Delete", role: .destructive) { … }
    ///     }
    /// ```
    ///
    /// The menu opens on the right-button **press**, and the rest of that
    /// gesture belongs to it: keep the button down, drag over the rows to
    /// highlight them, and release on one to run it — the way a Mac context
    /// menu tracks. Letting go anywhere else puts the menu away without running
    /// anything. A quick right-click works too — a release that never moved
    /// completes a *click*, and leaves the menu up until the next one. Escape or
    /// an outside click also dismisses it.
    ///
    /// Where the terminal swallows right-click (iTerm2 does by default) a
    /// **Ctrl-click** opens it instead. Right-clicking works reliably in Apple
    /// Terminal, Ghostty and Warp (see `Documentation/Terminals/Terminal compatibility survey.md`).
    ///
    /// From the keyboard: the modified view becomes a focus stop, and
    /// **Shift+F10** opens the menu while it is focused — the binding every
    /// platform that has a keyboard context-menu route agrees on (macOS has
    /// none of its own, and Mac keyboards have no Menu key) — as does a PC
    /// keyboard's Menu key where the terminal reports it. TUI-specific: it
    /// is the reason a `.contextMenu` adds a Tab stop, which SwiftUI's does
    /// not, because a menu reachable only by mouse is not reachable at all.
    /// In a `List` row it adds none: the list is the stop, and its Shift+F10
    /// opens the cursor row's menu, as it opens a selection menu's.
    ///
    /// - Parameter menuItems: A view builder of the menu's `Button`s (and
    ///   `Divider`s).
    /// - Returns: A view that shows the context menu on secondary-click.
    public func contextMenu<MenuItems: View>(
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        ContextMenuModifier(content: self, menuItems: menuItems())
    }

    /// Adds a context menu with a custom preview to a view.
    ///
    /// The menu is the one ``View/contextMenu(menuItems:)`` shows, opened the same
    /// ways. The preview is not shown, as on macOS: SwiftUI documents that
    /// "this view modifier produces a context menu on macOS, but that platform
    /// doesn't display the preview", which is the iOS lift-and-hold picture.
    /// The `preview` closure is never called.
    ///
    /// - Parameters:
    ///   - menuItems: A view builder of the menu's `Button`s (and `Divider`s).
    ///   - preview: The view iOS shows beside the menu; not shown here.
    /// - Returns: A view that shows the context menu on secondary-click.
    public func contextMenu<MenuItems: View, Preview: View>(
        @ViewBuilder menuItems: () -> MenuItems,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        ContextMenuModifier(content: self, menuItems: menuItems())
    }
}
