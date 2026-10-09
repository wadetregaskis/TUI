//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScreenSelection+Menu.swift
//
//  The screen selection's context menu: Copy, offered on a right-click on the
//  highlight, as a Mac offers it on selected text.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

extension ScreenSelection {
    /// The focus section the menu presents in.
    static let menuSectionID = "screenselection-menu"

    /// Presents the selection's context menu over `buffer` while it is open —
    /// the shared menu presentation `.contextMenu` uses, so it looks, moves and
    /// dismisses as every other menu does — and takes its section down on the
    /// first frame after it closes.
    ///
    /// Called by the window with the page it drew, whose coordinates are the
    /// content area's: the ones the selection keeps the right-clicked cell in.
    @MainActor
    func presentMenu(over buffer: inout FrameBuffer, context: RenderContext) {
        guard !context.isMeasuring else { return }
        guard let anchor = menuAnchor else {
            if menuNeedsTeardown {
                menuNeedsTeardown = false
                context.environment.focusManager?.deactivateSection(id: Self.menuSectionID)
            }
            return
        }
        menuNeedsTeardown = true
        let controller = menuController ?? MenuPopupController()
        menuController = controller
        let title = LocalizationService.shared.string(for: LocalizationKey.Button.copy)
        presentMenuPopover(
            items: Button(title) { [weak self] in
                guard let self else { return }
                _ = copySelection()
                closeMenu()
            },
            over: &buffer, controller: controller, sectionID: Self.menuSectionID,
            // Clear of the content's own children: the window renders its
            // content at its own identity.
            itemsIndex: Self.menuItemsIndex,
            anchor: MenuAnchor(x: anchor.x, y: anchor.y, controlHeight: 0),
            dismiss: { [weak self, weak controller] in
                self?.closeMenu()
                controller?.closed()
            },
            context: context)
    }

    /// The child index the menu's items render at.
    private static let menuItemsIndex = 0x5E1
}
