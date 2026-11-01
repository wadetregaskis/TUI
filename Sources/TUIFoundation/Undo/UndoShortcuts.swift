//  🖥️ TUI — A Terminal UI framework for Swift
//  UndoShortcuts.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUITerminalHost

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

    /// What TUI binds the command to out of the box.
    ///
    /// - **Undo:** Ctrl-Z, Ctrl-minus and Ctrl-/. In a legacy encoding
    ///   Ctrl-minus is the byte 0x1F, which most terminals also send for Ctrl-/
    ///   and Ctrl-_, and Ctrl-Shift-Z is Ctrl-Z's 0x1A, so all of those undo
    ///   there; under the kitty keyboard protocol each arrives as itself.
    /// - **Redo:** Ctrl-Y, which every terminal sends (0x19) and which is redo
    ///   on Windows and in many Linux editors; Ctrl-Shift-Z and Ctrl-_
    ///   (Ctrl-Shift-minus), which only the kitty keyboard protocol tells from
    ///   Ctrl-Z and Ctrl-minus; and Option-_, which a terminal sending Option
    ///   as Meta sends as `ESC _`.
    ///
    /// Ctrl-Z is the shell's suspend key too. Bound to undo, it undoes, and
    /// with nothing to undo it does nothing; an app that wants it to suspend
    /// unbinds it (``Scene/undoShortcuts(_:)``). Ctrl-Y is the text controls'
    /// yank too: a focused text field or editor takes it first, as it takes
    /// every key it edits with, so there it yanks, and redo is one of the
    /// others (the owner's ruling FB9-REDO, 2026-10-23). The status bar names
    /// one of those while a text control has the focus
    /// (`AppUndoKeys.hint(for:sparing:)`).
    public var defaultShortcuts: Set<KeyboardShortcut> {
        switch self {
        case .undo:
            return [
                KeyboardShortcut("z", modifiers: .control), KeyboardShortcut("-", modifiers: .control),
                KeyboardShortcut("/", modifiers: .control),
            ]
        case .redo:
            return [
                KeyboardShortcut("y", modifiers: .control),
                KeyboardShortcut("z", modifiers: [.control, .shift]), KeyboardShortcut("_", modifiers: .control),
                KeyboardShortcut("_", modifiers: .option),
            ]
        }
    }

    /// Undoes or redoes on `manager`, reporting whether there was a step to.
    ///
    @MainActor
    package func perform(on manager: UndoManager) -> Bool {
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

extension UndoCommand: ShortcutTableAction {
    /// Ctrl-Z for undo and Ctrl-Shift-Z for redo, where a terminal can deliver
    /// them: the chords nearest the Edit menu's ⌘Z and ⇧⌘Z, which no terminal
    /// sends an app. Sorted, the hint named Ctrl-minus — the same command, and
    /// a correct hint, but not the name anyone knows undo by. Then Ctrl-Y for
    /// redo, the key every terminal sends, where Ctrl-Shift-Z arrives as
    /// Ctrl-Z.
    @usableFromInline
    package var preferredHints: [KeyboardShortcut] {
        switch self {
        case .undo: [KeyboardShortcut("z", modifiers: .control)]
        case .redo: [KeyboardShortcut("z", modifiers: [.control, .shift]), KeyboardShortcut("y", modifiers: .control)]
        }
    }
}

// MARK: - Undo Shortcuts

/// The keys that undo and redo, app-wide — TUI's, with an app's changes on
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
/// neither is the shell's suspend key, as it was before TUI had an undo.
public struct UndoShortcuts: Hashable, Sendable {
    /// The app's changes, by command. Empty for the stock table.
    public let overrides: [UndoCommand: ShortcutSet]

    /// TUI's own bindings, unchanged.
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

    /// The chord to show for `command` on a terminal whose keyboard is as
    /// `terminal` says (an app passes its `\.terminalCapabilities`; a keyboard
    /// feature not known to be supported counts as missing): of the keys that
    /// reach it, the ones such a terminal can deliver as themselves — ⌃Z for undo and ⌃⇧Z for redo first, the
    /// names they are known by, then TUI's own, then in order; `nil`
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
        for command: UndoCommand, on terminal: TerminalCapabilities, commandKey: CommandKeyBinding = .control
    ) -> String? {
        hintShortcut(for: command, on: KeyboardReporting(terminal), commandKey: commandKey)?.displayString
    }

    /// The shortcut ``hint(for:on:commandKey:)`` names, before it is written.
    func hintShortcut(
        for command: UndoCommand, on reporting: KeyboardReporting, commandKey: CommandKeyBinding
    ) -> KeyboardShortcut? {
        hintShortcuts(for: command, on: reporting, commandKey: commandKey).first
    }

    /// The keys of `command` a terminal that reports keys as `reporting` says
    /// can deliver, in the order a hint is chosen from them
    /// (`rankedHintShortcuts(for:among:commandKey:)`):
    /// ``hintShortcut(for:on:commandKey:)`` is the first.
    func hintShortcuts(
        for command: UndoCommand, on reporting: KeyboardReporting, commandKey: CommandKeyBinding
    ) -> [KeyboardShortcut] {
        let deliverable = shortcuts(for: command, commandKey: commandKey).filter { $0.isDeliverable(on: reporting) }
        return rankedHintShortcuts(for: command, among: deliverable, commandKey: commandKey)
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
/// One per app, held by `TUIContext`. Not `Sendable`, like the dispatchers:
/// touched only from the main run loop. ``hint(for:)``
/// writes too, keeping its answer, and is asked only there, by the status
/// bar, which reads the undo manager on the main actor first.
package final class AppUndoKeys {
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
    /// Not a key the focused control `focus` takes for itself, which never
    /// reaches the undo keys while it has the focus: in a text field ⌃Y
    /// yanks, so redo is named by its next key there (the owner's ruling
    /// FB9-REDO, 2026-10-23: the hint follows the focus). `nil` where every
    /// key is the control's.
    ///
    /// Worked out for both commands at once and kept (``ranked``) until the
    /// table, the ⌘ binding or what the terminal reports changes; the focus
    /// is asked about the few keys kept, each time.
    func hint(for command: UndoCommand, sparing focus: (any TextInputFocusHandler)? = nil) -> String? {
        firstKey(for: command, sparing: focus).flatMap(name(of:))
    }

    /// The key the menu bar's Undo or Redo shows for `command` on this
    /// terminal (TUICommands): the one the status bar names, as a
    /// shortcut, or `nil` where none of its keys can be sent — the focus
    /// spared as ``hint(for:sparing:)`` spares it.
    ///
    /// Kept as the names are, until the table, the ⌘ binding or what the
    /// terminal reports changes: the menu's items are drawn every frame.
    package func shortcut(
        for command: UndoCommand, sparing focus: (any TextInputFocusHandler)? = nil
    ) -> KeyboardShortcut? {
        firstKey(for: command, sparing: focus)
    }

    /// The first of `command`'s keys in hint order that `focus` does not take
    /// for itself.
    private func firstKey(for command: UndoCommand, sparing focus: (any TextInputFocusHandler)?) -> KeyboardShortcut? {
        let ranked = rankedShortcuts(for: command)
        guard let focus else { return ranked.first }
        return ranked.first { shortcut in
            // Already resolved, so the binding is never read.
            guard let event = shortcut.keyEvent(commandKey: .control) else { return true }
            return !focus.keepsFromUndoKeys(event)
        }
    }

    /// `command`'s deliverable keys in the order a hint is chosen from them,
    /// worked out for both commands at once and kept until an input changes.
    private func rankedShortcuts(for command: UndoCommand) -> [KeyboardShortcut] {
        let key = HintKey(shortcuts: shortcuts, commandKey: commandKey, reporting: reporting)
        if let ranked, ranked.key == key { return ranked[command] }
        let resolve = { key.shortcuts.hintShortcuts(for: $0, on: key.reporting, commandKey: key.commandKey) }
        let fresh = Ranked(key: key, undo: resolve(.undo), redo: resolve(.redo))
        ranked = fresh
        hintResolutions += 1
        // Both names at once, as the bar asks for both — but the space bar's,
        // which is written on each read (``name(of:)``).
        writtenNames.removeAll(keepingCapacity: true)
        for first in [fresh.undo.first, fresh.redo.first].compactMap(\.self)
        where !KeySymbols.nameIsLocalized(first) {
            writtenNames[first] = writeName(first)
        }
        return fresh[command]
    }

    /// `shortcut`'s name in the bar, written once and kept — but the space
    /// bar's, a word in the app's language (`KeySymbols.nameIsLocalized(_:)`),
    /// which is written on each read: the language can change with nothing
    /// here hearing of it.
    private func name(of shortcut: KeyboardShortcut) -> String? {
        if KeySymbols.nameIsLocalized(shortcut) { return writeName(shortcut) }
        if let kept = writtenNames[shortcut] { return kept }
        let written = writeName(shortcut)
        writtenNames[shortcut] = written
        return written
    }

    /// Each command's deliverable keys in hint order, and the inputs they
    /// were worked out from — kept until one of them changes, as ``lookup``
    /// is kept until the table does.
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
    /// kept out of the key by never keeping that word (``name(of:)``).
    private var ranked: Ranked?

    /// The names written for the shortcuts in ``ranked``, by shortcut.
    private var writtenNames: [KeyboardShortcut: String?] = [:]

    /// How many times ``hint(for:)`` has worked the hints out, rather than
    /// read the kept ones — for the tests that pin the keeping.
    private(set) var hintResolutions = 0

    /// The inputs a kept answer was worked out from: everything
    /// ``hint(for:)`` reads but the app's language (see ``ranked``).
    private struct HintKey: Equatable {
        let shortcuts: UndoShortcuts
        let commandKey: CommandKeyBinding
        let reporting: KeyboardReporting
    }

    /// Both commands' deliverable keys in hint order, with the inputs they
    /// were worked out from.
    private struct Ranked {
        let key: HintKey
        let undo: [KeyboardShortcut]
        let redo: [KeyboardShortcut]

        subscript(command: UndoCommand) -> [KeyboardShortcut] {
            switch command {
            case .undo: undo
            case .redo: redo
            }
        }
    }
}
