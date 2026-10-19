//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _MenuBarCore+Opening.swift
//
//  How the menu bar's menus open and close: a click on a title, F10, and Alt
//  with a title's first letter; with a menu open, Left and Right, F10, Escape.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension _MenuBarCore {
    /// A click on a title opens its menu, or closes it if it is the one open.
    ///
    /// On the press, as a pull-down menu opens: the release that follows is
    /// this handler's (the press is claimed), so it chooses nothing. A
    /// pointer-opened menu highlights nothing. While a menu is open its
    /// dismiss backdrop covers the window and takes the press first, so a
    /// click on any title then closes the menu.
    func attachTitleRegions(
        to buffer: inout FrameBuffer, _ titles: TitleRow, state: MenuBarState, context: RenderContext
    ) {
        guard let dispatcher = context.environment.mouseEventDispatcher else { return }
        for (index, column) in titles.columns.enumerated() {
            let titleContext = context.withChildIdentity(type: TitleRow.self, index: index + 1)
            let id = dispatcher.register(in: titleContext) { [weak state] event in
                guard event.button == .left, let state else { return false }
                guard event.phase == .pressed else { return event.phase == .released }
                if state.openMenu == index {
                    state.close()
                } else {
                    state.open(index, withSelection: false)
                }
                return true
            }
            buffer.hitTestRegions.append(
                HitTestRegion(offsetX: column, offsetY: 0, width: titles.widths[index], height: 1, handlerID: id))
        }
    }

    /// With every menu closed: F10 opens the first menu, and Alt with a
    /// title's first letter opens that menu — each with its first item
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
    /// a focused text field keeps the chords it edits with (Alt-B, Alt-F). A
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
