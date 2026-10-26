//  🖥️ TUI — A Terminal UI framework for Swift
//  _MenuBarCore+Opening.swift
//
//  How the menu bar's menus open and close: a click on a title, F10, and Alt
//  with a title's first letter; with a menu open, Left and Right, F10, Escape.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension _MenuBarCore {
    /// A press on a title opens its menu, or closes it if it is the one open.
    ///
    /// On the press, as a pull-down menu opens, and the rest of the gesture is
    /// the menu's, as a Mac's menu bar tracks: the press is handed off
    /// (``MouseEventDispatcher/handOffGesture()``), so a drag down the menu
    /// highlights the row under the pointer and a release on one runs it,
    /// and a release away from every row closes the menu. A release that did
    /// not move ends a click, and leaves the menu up to be chosen from
    /// (``MouseEventDispatcher/pressOpenedPopup(_:)``). A pointer-opened menu
    /// highlights nothing. While a menu is open its dismiss backdrop covers
    /// the window and takes the press first.
    ///
    /// - Returns: Each title's handler, in bar order, for the open menu's
    ///   backdrop to find the titles by (``titleTracking(_:state:context:)``).
    @discardableResult
    func attachTitleRegions(
        to buffer: inout FrameBuffer, _ titles: TitleRow, state: MenuBarState, context: RenderContext
    ) -> [HitTestRegion.HandlerID] {
        guard let dispatcher = context.environment.mouseEventDispatcher else { return [] }
        var ids: [HitTestRegion.HandlerID] = []
        for (index, column) in titles.columns.enumerated() {
            let titleContext = context.withChildIdentity(type: TitleRow.self, index: index + 1)
            let id = dispatcher.register(in: titleContext) { [weak state, weak dispatcher] event in
                guard event.button == .left, let state, let dispatcher else { return false }
                guard event.phase == .pressed else { return event.phase == .released }
                if state.openMenu == index {
                    state.close()
                } else {
                    state.open(index, withSelection: false)
                    dispatcher.handOffGesture()
                    dispatcher.pressOpenedPopup(state.openedPopup)
                }
                return true
            }
            buffer.hitTestRegions.append(
                HitTestRegion(offsetX: column, offsetY: 0, width: titles.widths[index], height: 1, handlerID: id))
            ids.append(id)
        }
        return ids
    }

    /// With a menu open, the titles under its dismiss backdrop go on following
    /// the pointer, as a Mac's menu bar does: moved onto another title — or
    /// dragged there, holding the press that opened the menu — the pointer
    /// opens that title's menu instead, with nothing highlighted; pressed on
    /// another title, it opens that one (and the press goes on as a press on a
    /// closed title does, ``attachTitleRegions(to:_:state:context:)``), and
    /// on the open menu's own title it closes it; a held press let go on a
    /// title leaves its menu up. Anywhere else the backdrop has the event.
    /// With every menu closed there is no backdrop, and the pointer passing
    /// over the titles opens nothing.
    ///
    /// The titles are found by their handlers, `ids`, at the pointer's cell:
    /// the backdrop hears screen coordinates, and the dispatcher knows where
    /// the bar was composited.
    func titleTracking(
        _ ids: [HitTestRegion.HandlerID], state: MenuBarState, context: RenderContext
    ) -> MenuBackdropPassThrough? {
        guard !ids.isEmpty, let dispatcher = context.environment.mouseEventDispatcher else { return nil }
        return MenuBackdropPassThrough { [weak state, weak dispatcher] event in
            guard let state, let dispatcher, let open = state.openMenu else { return false }
            let under = dispatcher.handlerIDs(at: event.x, y: event.y)
            guard let index = ids.firstIndex(where: under.contains) else { return false }
            switch event.phase {
            case .moved, .entered:
                guard index != open else { return false }
                state.open(index, withSelection: false)
                return true
            case .dragged where event.button == .left:
                if index != open { state.open(index, withSelection: false) }
                return true
            case .pressed where event.button == .left:
                if index == open {
                    state.close()
                } else {
                    state.open(index, withSelection: false)
                    dispatcher.handOffGesture()
                    dispatcher.pressOpenedPopup(state.openedPopup)
                }
                return true
            case .released where event.button == .left:
                return true
            default:
                return false
            }
        }
    }

    /// With every menu closed: F10 opens the first menu, and Alt with a
    /// title's letter (``MenuBarMnemonics``: its first not taken by a title
    /// before it, no two the same) opens that menu — each with its first item
    /// highlighted, since the keyboard opened it. The app's menu has no letter
    /// (``TitleRow/mnemonics``): F10 is its key.
    ///
    /// F10 is a key handler: a function key is no keyboard shortcut. It is
    /// filed FIRST in the frame's handlers (`insertHandler(at:)`), which the
    /// dispatcher asks last: the bar is drawn after the page, and a handler
    /// added then would have been asked before the page's own, taking F10
    /// from an app that handles it — where a page's key comes before a
    /// command's (deviation W7). Alt and a letter are framework defaults
    /// (``KeyboardShortcutRegistry/registerDefault(_:holdsFocus:action:)``),
    /// so any shortcut of the app's on the same chord wins over the menu, and
    /// a focused text field keeps the chords it edits with (Alt-B, Alt-F),
    /// which no title is given while it has the focus. A
    /// terminal that does not send Option as Meta never sends them; F10 and a
    /// click work everywhere (Terminal compatibility survey.md, "The menu
    /// bar's keys").
    func attachOpeningKeys(_ titles: TitleRow, state: MenuBarState, context: RenderContext) {
        guard !titles.columns.isEmpty else { return }
        context.environment.keyEventDispatcher?.insertHandler(at: 0) { [weak state] event in
            guard Self.isMenuBarKey(event), let state else { return false }
            state.open(0, withSelection: true)
            return true
        }
        guard let registry = context.environment.keyboardShortcutRegistry else { return }
        for (index, mnemonic) in titles.mnemonics.enumerated() {
            guard let mnemonic else { continue }
            registry.registerDefault(KeyboardShortcut(KeyEquivalent(mnemonic), modifiers: .option)) { [weak state] in
                state?.open(index, withSelection: true)
            }
        }
    }

    /// With a menu open, in its section, ahead of its own keys: F10 closes it,
    /// and Alt with another title's first letter opens that menu instead.
    /// (Left and Right step to the next menu through the menu's own keys,
    /// `menuBarStep`; Escape closes it, as it closes any menu.)
    func attachOpenMenuKeys(_ titles: TitleRow, state: MenuBarState, sectionID: String, context: RenderContext) {
        let mnemonics = titles.mnemonics
        context.environment.keyEventDispatcher?.addHandler(sectionID: sectionID) { [weak state] event in
            guard let state, event.phase != .release else { return false }
            if Self.isMenuBarKey(event) {
                state.close()
                return true
            }
            guard event.alt, !event.ctrl, case .character(let character) = event.key,
                let index = mnemonics.firstIndex(of: Character(character.lowercased()))
            else { return false }
            state.open(index, withSelection: true)
            return true
        }
    }

    /// Whether `event` is F10 pressed alone: the key that opens and closes the
    /// menu bar. Shift-F10 is the context menu's.
    static func isMenuBarKey(_ event: KeyEvent) -> Bool {
        event.key == .f10 && !event.shift && !event.ctrl && !event.alt && event.phase != .release
    }
}
