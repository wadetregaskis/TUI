//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuBarState.swift
//
//  Which of the menu bar's menus is open, from one frame to the next.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// Which of the menu bar's menus is open, and its highlight — a manual
/// `StateStorage` box (not `@State`) the bar marks active each frame, the
/// pattern a pop-up `Menu`'s `MenuPopupState` follows.
@MainActor
final class MenuBarState {
    /// The open menu's place among the bar's menus, or `nil` with every menu
    /// closed.
    private(set) var openMenu: Int?

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
        isOpen: { [weak self] in self?.openMenu != nil },
        close: { [weak self] in self?.close() })

    /// Opens the menu at `index`, with its first row highlighted if
    /// `withSelection` — the keyboard opened it — or with nothing highlighted
    /// for the pointer, which has chosen nothing yet.
    func open(_ index: Int, withSelection: Bool) {
        if openMenu != index { controller = MenuPopupController() }
        openMenu = index
        controller.opened(withSelection: withSelection)
    }

    /// Opens the menu `offset` places from the open one among `count` menus,
    /// wrapping round the ends as a menu bar's arrows do; the keyboard steps,
    /// so its first row is highlighted.
    func step(_ offset: Int, among count: Int) {
        guard let openMenu, count > 0 else { return }
        open(((openMenu + offset) % count + count) % count, withSelection: true)
    }

    /// Closes the open menu, if any. Idempotent.
    func close() {
        openMenu = nil
        controller.closed()
    }
}
