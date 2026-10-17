//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditingMenu.swift
//
//  The menu a right-click or Shift+F10 opens on a text field, a secure field
//  or a text editor: Cut, Copy, Paste, Yank, Select All.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The commands

/// A command of a text control's context menu.
enum TextEditingMenuCommand {
    case cut
    case copy
    case paste
    /// Inserts the text the last kill (Ctrl-K) removed, as Ctrl-Y does.
    case yank
    case selectAll
}

/// A text control's editing state, as its context menu needs it: what can be
/// done, and the doing.
@MainActor
protocol TextEditingMenuHandler: AnyObject {
    /// Whether there is a selection that Cut and Copy may take: none in a
    /// ``SecureField``, whose contents are never copied.
    var menuCanCopy: Bool { get }
    /// Whether a kill has left text for Yank to insert.
    var menuCanYank: Bool { get }
    /// Carries out `command`, as its key would.
    func performMenuCommand(_ command: TextEditingMenuCommand)
}

/// Where a text control's menu finds the control's handler.
///
/// The menu is made in the control's `body`, before its core has drawn and
/// so before the handler it keeps in its state can be reached. The control
/// holds one of these in its own `@State`, the same object frame after
/// frame, and its core writes the handler into it as it draws: by the time a
/// menu is chosen from, the core has drawn at least once.
@MainActor
final class TextEditingMenuTarget {
    weak var handler: (any TextEditingMenuHandler)?
}

// MARK: - The menu

/// A text control's context menu: Cut, Copy and Paste; Yank where a kill has
/// left text for it; Select All.
///
/// Cut and Copy are offered disabled where nothing is selected, and in a
/// ``SecureField``, as macOS offers them; Paste always, since what the
/// clipboard holds is not known until it is read.
///
/// TUI-specific: SwiftUI's text controls take theirs from the platform's text
/// system. Yank is the Emacs kill ring's, which a terminal's readline users
/// reach for, and which the menu shows only while it holds something.
struct TextEditingMenu: View {
    let target: TextEditingMenuTarget

    var body: some View {
        let handler = target.handler
        let canCopy = handler?.menuCanCopy ?? false
        item(.cut, LocalizationKey.Menu.cut.rawValue).disabled(!canCopy)
        item(.copy, LocalizationKey.Button.copy.rawValue).disabled(!canCopy)
        item(.paste, LocalizationKey.Button.paste.rawValue)
        if handler?.menuCanYank == true {
            item(.yank, LocalizationKey.Menu.yank.rawValue)
        }
        Divider()
        item(.selectAll, LocalizationKey.Menu.selectAll.rawValue)
    }

    private func item(_ command: TextEditingMenuCommand, _ key: String) -> Button {
        Button(LocalizationService.shared.string(for: key)) { [target] in
            target.handler?.performMenuCommand(command)
        }
    }
}

extension View {
    /// This text control with its editing menu, opened by a right-click (or
    /// Ctrl-click) on it, or by Shift+F10 while it holds the focus. It adds
    /// no focus stop: the control is one already.
    func textEditingMenu(_ target: TextEditingMenuTarget) -> some View {
        ContextMenuModifier(content: self, menuItems: TextEditingMenu(target: target), keyboardRoute: .contentStops)
    }
}
