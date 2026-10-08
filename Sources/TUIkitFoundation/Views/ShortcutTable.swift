//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShortcutTable.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Shortcut Table

/// An action a shortcut table binds keys to, with the keys TUIkit binds it to
/// out of the box.
package protocol ShortcutTableAction: Hashable, CaseIterable, Sendable {
    /// What TUIkit binds this action to out of the box.
    var defaultShortcuts: Set<KeyboardShortcut> { get }
}

/// A table of an app's changes to the keys of a closed set of actions, each
/// action's value a ``ShortcutSet`` over TUIkit's defaults — ``RowShortcuts``
/// is the model, and the rules below are its, kept once so a second table
/// cannot read them differently.
package protocol ShortcutTable {
    associatedtype Action: ShortcutTableAction

    /// The app's changes, by action. Empty for the stock table.
    var overrides: [Action: ShortcutSet] { get }

    /// The table's name as an app writes it — the modifier that sets it —
    /// for a report of two overrides on one chord.
    static var modifierName: String { get }
}

extension ShortcutTable {
    /// The chord → action map a key is dispatched through.
    ///
    /// Defaults first, then the overrides on top: an override that names a
    /// chord one of TUIkit's defaults holds takes it, and the default yields.
    /// Two overrides on one chord are reported through `report`, and the
    /// action `Action` declares first keeps the chord, whatever order the
    /// dictionary was written in.
    package func triggerTable(
        commandKey: CommandKeyBinding, onClash report: (String) -> Void
    ) -> [KeyboardShortcut.Trigger: Action] {
        var byTrigger: [KeyboardShortcut.Trigger: Action] = [:]
        // The chords an override has claimed, keyed by the chord each one
        // RESOLVES to rather than by how it was written: ⌘E and Ctrl-E are one
        // key where ⌘ stands for Control, and comparing the written shortcuts
        // let the later of two such overrides take the chord in silence.
        var claimedByOverride: [KeyboardShortcut.Trigger: Action] = [:]
        // Defaults first, then the overrides on top: an app that binds Ctrl-A to
        // something else means it, and the default that used to hold that chord
        // yields rather than fighting over it.
        for pass in [false, true] {
            for action in Action.allCases {
                let set = overrides[action] ?? .default
                let shortcuts = pass ? set.explicit : (set.includesDefaults ? action.defaultShortcuts : [])
                for shortcut in shortcuts {
                    guard let resolved = shortcut.resolved(commandKey: commandKey) else { continue }
                    // Two OVERRIDES on one chord is a mistake only the app can
                    // fix, so say so — and still resolve it the same way every
                    // run (the declaration order of `Action`), never by
                    // whichever way the dictionary happened to hash.
                    let clash = pass ? claimedByOverride[resolved.trigger] : nil
                    if let existing = clash, existing != action {
                        report(
                            "\(Self.modifierName) binds \(resolved.displayString ?? "?") to both "
                                + "\(existing) and \(action); \(existing), which \(Action.self) "
                                + "declares first, keeps it")
                        continue
                    }
                    byTrigger[resolved.trigger] = action
                    if pass { claimedByOverride[resolved.trigger] = action }
                }
            }
        }
        return byTrigger
    }

    /// The keys that reach `action`, each once, in ``KeyboardShortcut``'s own
    /// order — only the chords a key press would dispatch to it (see
    /// ``triggerTable(commandKey:onClash:)``).
    package func boundShortcuts(for action: Action, commandKey: CommandKeyBinding) -> [KeyboardShortcut] {
        // The table a key is dispatched through, not a second copy of its rule:
        // which chord goes to which action is decided in one place. Built
        // without a report, so a listing is not a second place a debug build
        // stops for a mistake the table itself reports.
        let dispatch = triggerTable(commandKey: commandKey, onClash: { _ in })
        let written = (overrides[action] ?? .default).resolved(defaults: action.defaultShortcuts)
        // A Set, because two spellings (⌘E, Ctrl-E) resolve to one chord.
        let resolved = Set(written.compactMap { $0.resolved(commandKey: commandKey) })
        return resolved.filter { dispatch[$0.trigger] == action }.sorted()
    }

    /// The chord to *show* for `action` among `candidates` (its bound keys, or
    /// some of them) — the framework's own binding if one is there, else the
    /// first in order. Adding an alias should not quietly rename the hint the
    /// user has learned.
    package func hint(
        for action: Action, among candidates: [KeyboardShortcut], commandKey: CommandKeyBinding
    ) -> String? {
        hintShortcut(for: action, among: candidates, commandKey: commandKey)?.displayString
    }

    /// The shortcut ``hint(for:among:commandKey:)`` names, before it is
    /// written: for a caller that writes it some other way.
    func hintShortcut(
        for action: Action, among candidates: [KeyboardShortcut], commandKey: CommandKeyBinding
    ) -> KeyboardShortcut? {
        let stock = action.defaultShortcuts.compactMap { $0.resolved(commandKey: commandKey) }
        return candidates.first { stock.contains($0) } ?? candidates.first
    }
}
