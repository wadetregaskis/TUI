//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBarState.swift
//
//  Which of the menu bar's menus is open, from one frame to the next.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// Which of the menu bar's menus is open, and its highlight, or which title
/// the keyboard is on with every menu closed (``highlightedTitle``) — a manual
/// `StateStorage` box (not `@State`) the bar marks active each frame, the
/// pattern a pop-up `Menu`'s `MenuPopupState` follows.
///
/// A menu is held by its identity (``ResolvedCommandMenu/key``), and its place
/// among the bar's menus is looked up in the frame's: a menu can come or go
/// between frames (`if` in a `commands` body, a standard menu whose groups all
/// came up empty), and an open menu held by its place became the menu that
/// moved into it, under a highlight and a controller that were the other's.
@MainActor
final class MenuBarState {
    /// The keys of the bar's menus, in order, as the last frame resolved them
    /// (``adopt(menuKeys:)``): what a place the frame's handlers name means.
    private(set) var menuKeys: [String] = []

    /// The open menu's key, or `nil` with every menu closed.
    private var openKey: String?

    /// The key of the title the keyboard is on in the bar mode, or `nil`.
    private var highlightedKey: String?

    /// The open menu's place among the bar's menus, or `nil` with every menu
    /// closed.
    var openMenu: Int? { openKey.flatMap { menuKeys.firstIndex(of: $0) } }

    /// The title the keyboard is on while it walks the bar with every menu
    /// closed — the bar mode F10 enters — or `nil` outside it.
    var highlightedTitle: Int? { highlightedKey.flatMap { menuKeys.firstIndex(of: $0) } }

    /// The open menu's highlight and rows. A new one for each menu opened, so
    /// a menu never starts from another's rows.
    private(set) var controller = MenuPopupController()

    /// The bar's menus, as the press on a title that opens one hands them to
    /// the dispatcher for the rest of its gesture
    /// (``MouseEventDispatcher/pressOpenedPopup(_:)``): open while any menu
    /// is, whichever the held drag has since moved to.
    ///
    /// Built once, as a pop-up `Menu`'s is (`MenuPopupState.openedPopup`).
    /// Weak, because this state holds it and the dispatcher may hold it past
    /// the bar's removal.
    private(set) lazy var openedPopup = MouseEventDispatcher.OpenedPopup(
        isOpen: { [weak self] in self?.openKey != nil },
        close: { [weak self] in self?.close() })

    /// Takes the frame's menus, by their keys. A menu open or highlighted that
    /// is no longer among them closes, as one past the end did: the bar has
    /// nothing to show for it.
    func adopt(menuKeys keys: [String]) {
        menuKeys = keys
        if (openKey != nil && openMenu == nil) || (highlightedKey != nil && highlightedTitle == nil) { close() }
    }

    /// Opens the menu at `index`, with its first row highlighted if
    /// `withSelection` — the keyboard opened it — or with nothing highlighted
    /// for the pointer, which has chosen nothing yet. A place past the last
    /// menu closes the bar.
    func open(_ index: Int, withSelection: Bool) {
        guard menuKeys.indices.contains(index) else {
            close()
            return
        }
        let key = menuKeys[index]
        if openKey != key { controller = MenuPopupController() }
        highlightedKey = nil
        openKey = key
        controller.opened(withSelection: withSelection)
    }

    /// Opens the menu `offset` places from the open one among `count` menus,
    /// wrapping round the ends as a menu bar's arrows do, with its first
    /// enabled row highlighted `withSelection` — the keyboard was in the menu
    /// it stepped from — or nothing, the keyboard on the titles.
    func step(_ offset: Int, among count: Int, withSelection: Bool) {
        guard let openMenu, count > 0 else { return }
        open(((openMenu + offset) % count + count) % count, withSelection: withSelection)
    }

    /// Closes the open menu, if any, and leaves the bar mode. Idempotent.
    func close() {
        openKey = nil
        highlightedKey = nil
        controller.closed()
    }

    /// Enters the bar mode with every menu closed and the first title
    /// highlighted, as F10 does.
    func enterBarMode() {
        close()
        highlightedKey = menuKeys.first
    }

    /// Highlights title `index` in the bar mode, as the pointer passing over it does.
    func highlight(_ index: Int) {
        guard highlightedKey != nil, menuKeys.indices.contains(index) else { return }
        highlightedKey = menuKeys[index]
    }
}
