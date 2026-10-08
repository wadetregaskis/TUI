//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContextMenuPresentation.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Context-menu state

/// The persisted open/anchor state of one ``ContextMenuModifier`` — a manual
/// StateStorage box (not `@State`) marked active each frame, the same pattern
/// ``Menu`` and the Picker drop-down use.
@MainActor
package final class ContextMenuState {
    /// Whether the menu is currently shown.
    package var isOpen = false
    /// The open menu's highlight and its rows — see ``MenuPopupController``.
    package let controller = MenuPopupController()
    /// The column of the click that opened it, in the modified content's local
    /// coordinate space (composition makes it absolute).
    package var anchorX = 0
    /// The row of the opening click, content-local.
    package var anchorY = 0
    /// Whether the keyboard opened it, which changes where it is anchored —
    /// see ``MenuAnchor/centredWithin``.
    package var openedByKeyboard = false
    /// Whether a menu was presented since the closed content last rendered, so
    /// the section it activated may be left to tear down.
    package var needsSectionTeardown = false

    /// No arguments, spelled out because the implicit initializer is internal
    /// and TUIkitLists makes these, for the lists' and tabs' row menus.
    package init() {}

    /// Closes the menu — chosen from, dismissed, or let go of — dropping its
    /// highlight. Idempotent.
    package func close() {
        isOpen = false
        controller.closed()
    }

    /// The menu, as the press that opens it hands it to the dispatcher for the
    /// rest of its gesture (``MouseEventDispatcher/pressOpenedPopup(_:)``).
    /// Built once, weakly, as ``MenuPopupState/openedPopup`` is.
    package private(set) lazy var openedPopup = MouseEventDispatcher.OpenedPopup(
        isOpen: { [weak self] in self?.isOpen ?? false },
        close: { [weak self] in self?.close() })
}

// MARK: - The keyboard's way to a menu

extension KeyEvent {
    /// Whether this is the key that opens a context menu on what holds the
    /// focus — Shift+F10, which every desktop shares, or the PC keyboard's
    /// Menu key where the terminal reports it (``Key/menu``) — and closes an
    /// open one. One test for every menu that answers it: `.contextMenu`, a
    /// list's or table's row menu, a tab's.
    package var opensContextMenu: Bool { (key == .f10 && shift) || key == .menu }
}

// MARK: - Presenting

/// How a context menu is opened and drawn, shared by `.contextMenu` and the
/// context menus a tab view's tabs carry (`TabContent.contextMenu(menuItems:)`):
/// the secondary-click trigger, the menu hung at its anchor, and the Shift+F10
/// that closes it.
@MainActor
package enum ContextMenuPresentation {
    /// Draws the open menu over `baseBuffer` — the content it belongs to,
    /// already rendered — and keeps the trigger live under it.
    package static func present<Items: View>(
        _ items: Items, over baseBuffer: inout FrameBuffer, stateBox: StateBox<ContextMenuState>,
        sectionID: String, context: RenderContext
    ) {
        let state = stateBox.value
        // The presentation itself is shared with the pop-up `Menu`: same
        // bordered column of Buttons, same focus/keyboard grab, same dismiss
        // backdrop. Only the trigger and the anchor differ — here, the cell the
        // secondary click landed on (content-local; composition makes it
        // absolute).
        // Where it hangs depends on what opened it. A right-click anchors AT the
        // clicked cell — the pointer is about to pick from the menu, so the rows
        // want to be in a predictable place under it, and there is nothing above
        // that cell for a flip to clear. Shift+F10 has no pointer to be
        // predictable for, so the menu centres on the view and hangs beneath it
        // like a pull-down: it reads as that view's menu instead of as something
        // that landed in the corner, and the whole view is what a flip must
        // clear.
        let anchor =
            state.openedByKeyboard
            ? MenuAnchor(
                x: 0, y: baseBuffer.height, controlHeight: baseBuffer.height,
                centredWithin: baseBuffer.width)
            : MenuAnchor(x: state.anchorX, y: state.anchorY, controlHeight: 0)
        // The trigger stays live under the open menu, so a second right-click on
        // the target closes and re-opens it — usually invisible, and a small hop
        // when the click moved, which is what macOS does. The two halves are
        // already there: the dismiss backdrop closes the menu on a right press
        // and then DECLINES it (see `attachDismissBackdrop`), so the press
        // bubbles down to whatever it landed on. Without a trigger to bubble to,
        // the target's own second click was the one gesture that could only ever
        // dismiss — while the same click on a *different* target opened that
        // one's menu, which is an inconsistency with no explanation a user could
        // find.
        if !context.isMeasuring {
            attachTrigger(to: &baseBuffer, stateBox: stateBox, focusID: nil, context: context)
        }
        presentMenuPopover(
            items: items, over: &baseBuffer, controller: state.controller,
            sectionID: sectionID, itemsIndex: 1, anchor: anchor,
            dismiss: { state.close() }, context: context)
        attachKeyboardCloser(state: state, sectionID: sectionID, context: context)
    }

    /// Opens the menu as the keyboard does: on its first item, so the arrows
    /// have somewhere to go, and written back through its box, which drops a
    /// memo holding the closed content.
    package static func openFromKeyboard(_ stateBox: StateBox<ContextMenuState>, onOpen: MenuOpenAction?) {
        let state = stateBox.value
        state.isOpen = true
        state.openedByKeyboard = true
        state.controller.opened(withSelection: true)
        stateBox.value = state
        onOpen?()
    }

    /// Closes the menu on **Shift+F10** while it is open.
    ///
    /// The gesture is a toggle: it is the keyboard's whole vocabulary for this
    /// menu, so pressing it again has to undo it, the way clicking a pull-down
    /// button a second time closes its menu. Escape already closes too — this is
    /// the symmetry, not the only way out.
    ///
    /// Registered on the MENU's section rather than the page's: the menu grabs
    /// the keyboard while it is up, so the trigger that opened it is not
    /// listening any more.
    package static func attachKeyboardCloser(
        state: ContextMenuState, sectionID: String, context: RenderContext
    ) {
        guard !context.isMeasuring, let dispatcher = context.environment.keyEventDispatcher
        else { return }
        dispatcher.addHandler(sectionID: sectionID) { event in
            guard event.opensContextMenu else { return false }
            state.close()
            return true
        }
    }

    /// Attaches the whole-content secondary-click trigger: a right-click or
    /// Ctrl-click PRESS opens the menu and records the click cell as its anchor.
    ///
    /// Registered UNDERNEATH the content's own regions (inserted first, so the
    /// dispatcher's innermost-first walk reaches it last). Two things depend on
    /// that. A right-click on an interactive child bubbles down to here when the
    /// child does not want it, which is how a `.contextMenu` on a container
    /// answers a click on its contents. And, less obviously, a LEFT click must
    /// pass straight through: the dispatcher stops at the first region that
    /// declines a left click rather than bubbling it, so a trigger registered on
    /// TOP of the content would decline every ordinary click and the button
    /// underneath would never see one — a `.contextMenu` would silently make its
    /// own content unclickable.
    ///
    /// On the press, not the release, because that is the gesture a Mac context
    /// menu answers: press and hold, drag down the rows, release on one to run
    /// it. The press hands the rest of the gesture back to live hit-testing
    /// (``MouseEventDispatcher/handOffGesture()``) so the drag and release reach
    /// the menu rather than routing back here — see ``Button/menuTrigger(_:)``,
    /// which is the same move for a pull-down.
    ///
    /// The region carries the focus stop's id (`ContextMenuModifier`'s keyboard trigger),
    /// which is how an enclosing `ScrollView` finds where the focus lives to
    /// scroll it into view. Without it, Tab walked the focus down a list of rows
    /// with context menus and off the bottom of the scroll view, onto rows
    /// nobody could see — and Shift+F10 then opened a menu on one of them.
    ///
    /// Opening writes the state back through its box, which is what drops a
    /// memo holding the closed content: the state is a class, changed in place,
    /// and a row served as it was stored would never draw the menu.
    @MainActor
    package static func attachTrigger(
        to buffer: inout FrameBuffer, stateBox: StateBox<ContextMenuState>, focusID: String?,
        context: RenderContext
    ) {
        let state = stateBox.value
        guard let dispatcher = context.environment.mouseEventDispatcher else { return }
        let onOpen = context.environment.menuOpenAction
        // Weak: the dispatcher holds this handler (see `Button`'s). Passive:
        // it takes no plain left press, so a drag handle in front of it still
        // stands aside for selectable text (`PressRole.dragSource`).
        let handlerID = dispatcher.registerPassive(in: context) { [weak dispatcher] event in
            // Secondary click = right button, or Ctrl + left (the fallback where a
            // terminal claims right-click for itself, e.g. iTerm2 by default).
            let isSecondary =
                event.button == .right || (event.button == .left && event.ctrl)
            guard isSecondary else { return false }
            switch event.phase {
            case .pressed:
                state.anchorX = event.x
                state.anchorY = event.y
                state.isOpen = true
                state.openedByKeyboard = false
                // Opened by the pointer: nothing is chosen yet.
                state.controller.opened(withSelection: false)
                stateBox.value = state
                onOpen?()
                dispatcher?.handOffGesture()
                dispatcher?.pressOpenedPopup(state.openedPopup)
                return true
            case .released:
                // Spent on the press, and the release is the menu's: its
                // backdrop takes it once drawn, and while the menu is not on
                // screen the dispatcher spends it itself
                // (``MouseEventDispatcher/pressOpenedPopup(_:)``). Should one
                // arrive anyway, it is consumed.
                return true
            default:
                return false
            }
        }
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0, offsetY: 0,
                width: max(1, buffer.width), height: max(1, buffer.height),
                handlerID: handlerID, focusID: focusID),
            at: 0)
    }
}
