//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcutRegistry+KeyPresses.swift
//
//  The keys a labelled `onKeyPress` answers to, for F1's list of the keys in
//  force (A-KEYHELP-1).
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - A labelled key press

/// What F1's list shows for an `onKeyPress` given a `label`: the keys it names
/// and what they do (the owner's ruling A-KEYHELP-1, 2026-11-20).
///
/// Only the overloads that name their keys take a label: one on a set of
/// characters, or on any key, names no key the list could show.
package struct KeyPressListing {
    /// The keys the handler is for.
    let keys: Set<KeyEquivalent>

    /// What they do, as the app wrote it.
    let label: Text

    /// What one render registers: the keys as shortcuts, in a shortcut list's
    /// order, and the label's words as that render reads them.
    struct Named {
        let keys: [KeyboardShortcut]
        let title: () -> String
        /// Where it was declared (``KeyboardShortcutRegistry/Scope``).
        let section: String?
    }

    /// The keys and label as `context` reads them: the label in its language,
    /// and the focus section the handler is declared in, as a shortcut's is.
    ///
    /// The keys go through ``KeyboardShortcut``, so they are spelled with the
    /// glyphs a shortcut is spelled with, Return and Escape included, and
    /// listed in a shortcut list's order (``KeyboardShortcut/<(_:_:)``).
    @MainActor
    func named(in context: RenderContext) -> Named {
        let words = label.reading(in: context).content
        return Named(
            keys: keys.map { KeyboardShortcut($0, modifiers: []) }.sorted(), title: { words },
            section: context.environment.shortcutSectionID)
    }
}

/// A labelled `onKeyPress`, as F1's list shows it: its keys, each spelled, and
/// what they do.
package struct ListedKeyPress: Equatable, Sendable {
    package let keys: [String]
    package let title: String

    package init(keys: [String], title: String) {
        self.keys = keys
        self.title = title
    }
}

// MARK: - Registry

extension KeyboardShortcutRegistry {
    /// A labelled `onKeyPress` registered this frame: its keys, what it is
    /// called, where it was declared, and the pane it was drawn in.
    struct KeyPressEntry {
        let keys: [KeyboardShortcut]
        let title: () -> String
        let scope: Scope
        let pane: String?
    }

    /// Records that a labelled `onKeyPress` on `keys` is on the screen, called
    /// `title`, declared in `section`, and in the pane rendering now
    /// (``currentPane``). It binds nothing: the handler hears its keys through
    /// the focus path, and this only lists them.
    package func noteKeyPress(_ keys: [KeyboardShortcut], title: @escaping () -> String, section: String?) {
        keyPresses.append(KeyPressEntry(keys: keys, title: title, scope: Scope(section: section), pane: currentPane))
    }

    /// The labelled `onKeyPress` handlers on the screen as of the frame last
    /// drawn, in the order they were drawn, by the rules ``listing(activePane:reachesPage:modalSection:)``
    /// lists a shortcut by: while a modal holds the keyboard, only those
    /// declared in it; with the focus in a pane, the pane's and, where
    /// `reachesPage`, the page's.
    ///
    /// Whether the focus is on the handler's view does not matter: the list
    /// says what the screen answers to, and the keys are the handler's whenever
    /// its view holds the focus.
    package func keyPressListing(
        activePane: String? = nil, reachesPage: Bool = true, modalSection: String? = nil
    ) -> [ListedKeyPress] {
        keyPresses.compactMap { entry in
            guard entry.scope.fires(under: modalSection),
                entry.pane == activePane || (entry.pane == nil && reachesPage)
            else { return nil }
            return ListedKeyPress(keys: entry.keys.map { KeySymbols.trigger($0.trigger) }, title: entry.title())
        }
    }
}
