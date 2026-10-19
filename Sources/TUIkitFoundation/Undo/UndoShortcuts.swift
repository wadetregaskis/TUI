//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UndoShortcuts.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Undo Command

/// The app's undo and redo: the two commands ``UndoShortcuts`` binds keys to.
///
/// TUI-specific. SwiftUI's undo and redo are the Edit menu's ⌘Z and ⇧⌘Z, which
/// no terminal sends; see ``EnvironmentValues/undoManager``.
public enum UndoCommand: Hashable, CaseIterable, Sendable {
    /// Undo the app's newest step.
    case undo
    /// Redo the step undo last took back.
    case redo

    /// What TUIkit binds the command to out of the box.
    ///
    /// - **Undo:** Ctrl-Z, Ctrl-minus and Ctrl-/. In a legacy encoding
    ///   Ctrl-minus is the byte 0x1F, which most terminals also send for Ctrl-/
    ///   and Ctrl-_, and Ctrl-Shift-Z is Ctrl-Z's 0x1A, so all of those undo
    ///   there; under the kitty keyboard protocol each arrives as itself.
    /// - **Redo:** Ctrl-Shift-Z and Ctrl-_ (Ctrl-Shift-minus), which only the
    ///   kitty keyboard protocol tells from Ctrl-Z and Ctrl-minus; and
    ///   Option-_, which a terminal sending Option as Meta sends as `ESC _`.
    ///
    /// Ctrl-Z is the shell's suspend key too. Bound to undo, it undoes, and
    /// with nothing to undo it does nothing; an app that wants it to suspend
    /// unbinds it (``Scene/undoShortcuts(_:)``). Ctrl-Y is the text controls'
    /// yank, and not bound.
    public var defaultShortcuts: Set<KeyboardShortcut> {
        switch self {
        case .undo:
            return [
                KeyboardShortcut("z", modifiers: .control), KeyboardShortcut("-", modifiers: .control),
                KeyboardShortcut("/", modifiers: .control),
            ]
        case .redo:
            return [
                KeyboardShortcut("z", modifiers: [.control, .shift]), KeyboardShortcut("_", modifiers: .control),
                KeyboardShortcut("_", modifiers: .option),
            ]
        }
    }

    /// Undoes or redoes on `manager`, reporting whether there was a step to.
    ///
    /// The input chain is not isolated to the main actor, though it only ever
    /// runs there; `UndoManager` is.
    package func perform(on manager: UndoManager) -> Bool {
        let reference = MainActorUndoManager(manager)
        return MainActor.assumeIsolated {
            let manager = reference.manager
            switch self {
            case .undo:
                guard manager.canUndo else { return false }
                manager.undo()
            case .redo:
                guard manager.canRedo else { return false }
                manager.redo()
            }
            return true
        }
    }
}

extension UndoCommand: ShortcutTableAction {
    /// Ctrl-Z for undo and Ctrl-Shift-Z for redo, where a terminal can deliver
    /// them: the chords nearest the Edit menu's ⌘Z and ⇧⌘Z, which no terminal
    /// sends an app. Sorted, the hint named Ctrl-minus — the same command, and
    /// a correct hint, but not the name anyone knows undo by.
    @usableFromInline
    package var preferredHints: [KeyboardShortcut] {
        switch self {
        case .undo: [KeyboardShortcut("z", modifiers: .control)]
        case .redo: [KeyboardShortcut("z", modifiers: [.control, .shift])]
        }
    }
}

// MARK: - Undo Shortcuts

/// The keys that undo and redo, app-wide — TUIkit's, with an app's changes on
/// top. Set with ``Scene/undoShortcuts(_:)``.
///
/// ```swift
/// WindowGroup { ContentView() }
///     .undoShortcuts([
///         // Ctrl-Z suspends, as in a shell: undo keeps Ctrl-minus and Ctrl-/.
///         .undo: .only(.init("-", modifiers: .control), .init("/", modifiers: .control)),
///     ])
/// ```
///
/// A command that isn't mentioned keeps its defaults (``UndoCommand/defaultShortcuts``);
/// see ``ShortcutSet`` for the four things a value can say. The rules are
/// ``RowShortcuts``'s: an override that names a chord a default of the other
/// command holds takes it, and two overrides on one chord are a mistake — a
/// debug build stops, a release build reports it once and undo keeps the
/// chord. A shortcut written with ⌘ is resolved through the scene's
/// ``EnvironmentValues/commandKey``, as a `Button`'s is.
///
/// The keys are default bindings, at the bottom of the input chain: the
/// focused control (a text field's own Ctrl-Z is the app's undo too) and an
/// app's own keyboard shortcut on the chord come first. A key bound to undo or
/// redo is that command's whether or not there is a step to take: with nothing
/// to undo, Ctrl-Z does nothing, never "sometimes suspends". A Ctrl-Z bound to
/// neither is the shell's suspend key, as it was before TUIkit had an undo.
public struct UndoShortcuts: Hashable, Sendable {
    /// The app's changes, by command. Empty for the stock table.
    public let overrides: [UndoCommand: ShortcutSet]

    /// TUIkit's own bindings, unchanged.
    public static let `default` = Self()

    public init(_ overrides: [UndoCommand: ShortcutSet] = [:]) {
        self.overrides = overrides
    }

    /// The keys that reach `command`, each once, in ``KeyboardShortcut``'s
    /// own order — only the chords a key press would dispatch to it.
    ///
    /// - Parameters:
    ///   - command: Undo or redo.
    ///   - commandKey: What ⌘ stands in for; a shortcut written the SwiftUI
    ///     way is resolved through it.
    public func shortcuts(
        for command: UndoCommand, commandKey: CommandKeyBinding = .control
    ) -> [KeyboardShortcut] {
        boundShortcuts(for: command, commandKey: commandKey)
    }

    /// The chord to show for `command` on a terminal that reports keys as
    /// `reporting` says: of the keys that reach it, the ones such a terminal
    /// can deliver as themselves — ⌃Z for undo and ⌃⇧Z for redo first, the
    /// names they are known by, then TUIkit's own, then in order; `nil`
    /// when it can deliver none. In a legacy encoding a Control chord with
    /// Shift, or on a key other than a letter or minus, arrives as another
    /// chord or not at all; under the kitty keyboard protocol each arrives as
    /// itself, one on a shifted character where the terminal reports shifted
    /// keys. An Option chord counts as deliverable, the terminal sending it
    /// where Option is Meta, which nothing can ask.
    ///
    /// The key the status bar names beside "undo" and "redo", written as a
    /// menu writes it (``KeyboardShortcut/displayString``): `⌃Z`, `⌥_`, and
    /// `U` for a bare u. The bar itself writes a letter held with nothing but
    /// Shift in the case it types, as its own items are written — `u`, and
    /// `U` for Shift-U — because in the bar the case is the Shift.
    public func hint(
        for command: UndoCommand, on reporting: KeyboardReporting, commandKey: CommandKeyBinding = .control
    ) -> String? {
        hintShortcut(for: command, on: reporting, commandKey: commandKey)?.displayString
    }

    /// The shortcut ``hint(for:on:commandKey:)`` names, before it is written.
    func hintShortcut(
        for command: UndoCommand, on reporting: KeyboardReporting, commandKey: CommandKeyBinding
    ) -> KeyboardShortcut? {
        let deliverable = shortcuts(for: command, commandKey: commandKey).filter { $0.isDeliverable(on: reporting) }
        return hintShortcut(for: command, among: deliverable, commandKey: commandKey)
    }

    /// The chord → command map a key is dispatched through. Two overrides on
    /// one chord are reported through `onClash`, a soft trap by default.
    func lookup(
        commandKey: CommandKeyBinding, onClash report: (String) -> Void = { SoftTrap.report($0) }
    ) -> [KeyboardShortcut.Trigger: UndoCommand] {
        triggerTable(commandKey: commandKey, onClash: report)
    }
}

extension UndoShortcuts: ShortcutTable {
    // `@usableFromInline`, as a requirement of the `@usableFromInline`
    // `ShortcutTable` must be.
    @usableFromInline
    package static var modifierName: String { "undoShortcuts" }
}

// MARK: - What a terminal can deliver

extension KeyboardShortcut {
    /// Whether a terminal that reports keys as `reporting` says can deliver
    /// this chord as itself — not as another key that matches some other
    /// binding, and not as nothing.
    ///
    /// Narrower than ``isDeliverableInTerminal``, which asks only whether a
    /// chord can be named at all. In a legacy encoding a Control chord is a C0
    /// byte, which has no case and exists only for the letters (bar Ctrl-H, I,
    /// J and M, which are other keys) and for minus (0x1F): Ctrl-Shift-Z
    /// arrives as Ctrl-Z, Ctrl-_ and Ctrl-/ as Ctrl-minus. Under the kitty
    /// keyboard protocol every Control chord arrives as itself, one whose key
    /// is a shifted character only where the terminal reports the shifted key
    /// (``KeyboardReporting/reportsShiftedKeys``) — a letter's capital is
    /// always known. An Option chord is taken as deliverable: the terminal
    /// sends it where Option is Meta, which nothing can ask.
    func isDeliverable(on reporting: KeyboardReporting) -> Bool {
        guard case .key(let key, let modifiers) = trigger else { return true }
        guard modifiers.isDisjoint(with: [.command, .capsLock, .numericPad]) else { return false }
        let character = key.character
        let shifted = modifiers.contains(.shift) || Self.shiftedSymbols.contains(character)
        if modifiers.contains(.control) {
            guard reporting.disambiguatesKeys else {
                return !shifted && (Self.controlLetters.contains(character) || character == "-")
            }
            return !shifted || character.isLetter || reporting.reportsShiftedKeys
        }
        // Shift without Control is a case, and only a letter has one.
        return !modifiers.contains(.shift) || character.isLetter
    }

    /// The letters whose Control chord a legacy encoding sends as that chord.
    private static let controlLetters = Set("abcdefgklnopqrstuvwxyz")

    /// The characters a US layout types with Shift, which a Control chord can
    /// name only where the terminal reports the shifted key.
    private static let shiftedSymbols = Set("~!@#$%^&*()_+{}|:\"<>?")
}

// MARK: - The app's undo keys, between frames

/// The app's undo and redo keys as the input chain and the status bar read
/// them: the scene's ``UndoShortcuts``, resolved through its
/// ``EnvironmentValues/commandKey`` and published by the run loop each frame,
/// and what the terminal reports, which decides which key the bar can name.
///
/// One per app, held by `TUIContext`. `@unchecked Sendable` on the same footing
/// as the dispatchers: touched only from the main run loop. ``hint(for:)``
/// writes too, keeping its answer, and is asked only there, by the status
/// bar, which reads the undo manager on the main actor first.
package final class AppUndoKeys: @unchecked Sendable {
    /// The table in force.
    private(set) var shortcuts = UndoShortcuts.default

    /// What ⌘ stands in for in ``shortcuts``.
    private(set) var commandKey = CommandKeyBinding.control

    /// What the terminal reports about the keyboard, for ``hint(for:)``.
    package var reporting: KeyboardReporting { get { _reporting } set { _reporting = newValue } }

    /// ``reporting``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _reporting = KeyboardReporting.legacy

    /// ``shortcuts`` as the chord → command map a key is matched against,
    /// rebuilt only when the table changes.
    private var lookup = UndoShortcuts.default.lookup(commandKey: .control)

    /// Writes a key's name for ``hint(for:)``: `KeySymbols.statusBarName(of:)`,
    /// but in a test.
    private let writeName: (KeyboardShortcut) -> String?

    package convenience init() {
        self.init(writingNamesWith: KeySymbols.statusBarName(of:))
    }

    /// Undo keys whose hints are written by `writeName` — a parameter so a test
    /// can switch the app's language under the space bar's name, which the
    /// shared service holds and the parallel suite cannot switch (it assumes
    /// English), as `StatusBarItem.keyFromShortcut(_:spaceBarName:)` takes the
    /// name.
    init(writingNamesWith writeName: @escaping (KeyboardShortcut) -> String?) {
        self.writeName = writeName
    }

    /// Takes the scene's table for the next keys, rebuilding the map only
    /// when it changed — the run loop calls this every frame.
    package func publish(_ shortcuts: UndoShortcuts, commandKey: CommandKeyBinding) {
        guard shortcuts != self.shortcuts || commandKey != self.commandKey else { return }
        self.shortcuts = shortcuts
        self.commandKey = commandKey
        lookup = shortcuts.lookup(commandKey: commandKey)
    }

    /// The command `event` is bound to, or `nil`. A release is never one.
    package func command(for event: KeyEvent) -> UndoCommand? {
        guard event.phase != .release, let trigger = KeyboardShortcut.trigger(for: event) else { return nil }
        return lookup[trigger]
    }

    /// The key the status bar names for `command` on this terminal, or `nil`
    /// where none of its keys can be sent — written as the bar writes a key,
    /// a bare letter in the case it types (`KeySymbols.statusBarName(of:)`).
    ///
    /// Worked out for both commands at once and kept (``keptHints``) until
    /// the table, the ⌘ binding or what the terminal reports changes.
    func hint(for command: UndoCommand) -> String? {
        let key = HintKey(shortcuts: shortcuts, commandKey: commandKey, reporting: reporting)
        if let kept = keptHints, kept.key == key { return kept[command].name(writtenWith: writeName) }
        // Both at once: the bar asks for both, so the second is then kept.
        let resolve = { (command: UndoCommand) in
            KeptHint(
                key.shortcuts.hintShortcut(for: command, on: key.reporting, commandKey: key.commandKey),
                writtenWith: self.writeName)
        }
        let kept = KeptHints(key: key, undo: resolve(.undo), redo: resolve(.redo))
        keptHints = kept
        hintResolutions += 1
        return kept[command].name(writtenWith: writeName)
    }

    /// The key the menu bar's Undo or Redo shows for `command` on this
    /// terminal (TUIkitCommands): the one the status bar names, as a
    /// shortcut, or `nil` where none of its keys can be sent.
    ///
    /// Kept as the names are, until the table, the ⌘ binding or what the
    /// terminal reports changes: the menu's items are drawn every frame.
    package func shortcut(for command: UndoCommand) -> KeyboardShortcut? {
        let key = HintKey(shortcuts: shortcuts, commandKey: commandKey, reporting: reporting)
        if let kept = keptShortcuts, kept.key == key { return command == .undo ? kept.undo : kept.redo }
        let resolve = { key.shortcuts.hintShortcut(for: $0, on: key.reporting, commandKey: key.commandKey) }
        let kept = (key: key, undo: resolve(.undo), redo: resolve(.redo))
        keptShortcuts = kept
        return command == .undo ? kept.undo : kept.redo
    }

    /// What ``shortcut(for:)`` answered for each command, and the inputs it
    /// was worked out from.
    private var keptShortcuts: (key: HintKey, undo: KeyboardShortcut?, redo: KeyboardShortcut?)?

    // MARK: The kept hints

    /// What ``hint(for:)`` answered for each command, and the inputs it was
    /// worked out from — kept until one of them changes, as ``lookup`` is
    /// kept until the table does.
    ///
    /// The status bar asks for both hints whenever it lists its items, which
    /// is on every render, and an answer is not cheap: listing a command's
    /// keys builds the whole dispatch table, every command's keys, to check
    /// them against (`boundShortcuts(for:commandKey:)`).
    ///
    /// **A new input to ``hint(for:)`` must join ``HintKey``**, or the bar
    /// goes on naming the key it named before that input changed. Today they
    /// are the table, the ⌘ binding and what the terminal reports — and the
    /// app's language, which only the space bar's name reads, and which is
    /// kept out of the key by never keeping that word: a hint on the space
    /// bar keeps its shortcut and is written afresh on each read
    /// (``KeptHint/onTheSpaceBar(_:)``).
    private var keptHints: KeptHints?

    /// How many times ``hint(for:)`` has worked the hints out, rather than
    /// read the kept ones — for the tests that pin the keeping.
    private(set) var hintResolutions = 0

    /// The inputs a kept answer was worked out from: everything
    /// ``hint(for:)`` reads but the app's language (see ``keptHints``).
    private struct HintKey: Equatable {
        let shortcuts: UndoShortcuts
        let commandKey: CommandKeyBinding
        let reporting: KeyboardReporting
    }

    /// One command's kept hint.
    private enum KeptHint {
        /// The name, written once; `nil` where none of the command's keys can
        /// be sent.
        case written(String?)
        /// A shortcut whose name is in the app's language
        /// (`KeySymbols.nameIsLocalized(_:)`, the space bar's), written on
        /// each read: the language can change with nothing here hearing of it.
        case onTheSpaceBar(KeyboardShortcut)

        /// `shortcut`'s hint, its name written by `write` now unless it has
        /// the app's language in it.
        init(_ shortcut: KeyboardShortcut?, writtenWith write: (KeyboardShortcut) -> String?) {
            if let shortcut, KeySymbols.nameIsLocalized(shortcut) {
                self = .onTheSpaceBar(shortcut)
            } else {
                self = .written(shortcut.flatMap(write))
            }
        }

        /// The name the bar shows: the kept one, or the space bar's written
        /// by `write` in the language of the moment.
        func name(writtenWith write: (KeyboardShortcut) -> String?) -> String? {
            switch self {
            case .written(let name): name
            case .onTheSpaceBar(let shortcut): write(shortcut)
            }
        }
    }

    /// Both commands' hints, with the inputs they were worked out from.
    private struct KeptHints {
        let key: HintKey
        let undo: KeptHint
        let redo: KeptHint

        subscript(command: UndoCommand) -> KeptHint {
            switch command {
            case .undo: undo
            case .redo: redo
            }
        }
    }
}
