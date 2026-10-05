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
    func perform(on manager: UndoManager) -> Bool {
        MainActor.assumeIsolated {
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

extension UndoCommand: ShortcutTableAction {}

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
    /// can deliver as themselves, TUIkit's own first, then in order; `nil`
    /// when it can deliver none. In a legacy encoding a Control chord with
    /// Shift, or on a key other than a letter or minus, arrives as another
    /// chord or not at all; under the kitty keyboard protocol each arrives as
    /// itself, one on a shifted character where the terminal reports shifted
    /// keys. An Option chord counts as deliverable, the terminal sending it
    /// where Option is Meta, which nothing can ask.
    ///
    /// What the status bar names beside "undo" and "redo".
    public func hint(
        for command: UndoCommand, on reporting: KeyboardReporting, commandKey: CommandKeyBinding = .control
    ) -> String? {
        let deliverable = shortcuts(for: command, commandKey: commandKey).filter { $0.isDeliverable(on: reporting) }
        return hint(for: command, among: deliverable, commandKey: commandKey)
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
    static var modifierName: String { "undoShortcuts" }
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
/// as the dispatchers: touched only from the main run loop.
final class AppUndoKeys: @unchecked Sendable {
    /// The table in force.
    private(set) var shortcuts = UndoShortcuts.default

    /// What ⌘ stands in for in ``shortcuts``.
    private(set) var commandKey = CommandKeyBinding.control

    /// What the terminal reports about the keyboard, for ``hint(for:)``.
    var reporting = KeyboardReporting.legacy

    /// ``shortcuts`` as the chord → command map a key is matched against,
    /// rebuilt only when the table changes.
    private var lookup = UndoShortcuts.default.lookup(commandKey: .control)

    init() {}

    /// Takes the scene's table for the next keys, rebuilding the map only
    /// when it changed — the run loop calls this every frame.
    func publish(_ shortcuts: UndoShortcuts, commandKey: CommandKeyBinding) {
        guard shortcuts != self.shortcuts || commandKey != self.commandKey else { return }
        self.shortcuts = shortcuts
        self.commandKey = commandKey
        lookup = shortcuts.lookup(commandKey: commandKey)
    }

    /// The command `event` is bound to, or `nil`. A release is never one.
    func command(for event: KeyEvent) -> UndoCommand? {
        guard event.phase != .release, let trigger = KeyboardShortcut.trigger(for: event) else { return nil }
        return lookup[trigger]
    }

    /// The key the status bar names for `command` on this terminal, or `nil`
    /// where none of its keys can be sent.
    func hint(for command: UndoCommand) -> String? {
        shortcuts.hint(for: command, on: reporting, commandKey: commandKey)
    }
}

// MARK: - Environment and the scene modifier

private struct UndoShortcutsKey: EnvironmentKey {
    static let defaultValue = UndoShortcuts.default
}

extension EnvironmentValues {
    /// The app's undo and redo keys, as a scene set them — see
    /// ``Scene/undoShortcuts(_:)``. Read by the run loop from the root
    /// environment; the keys are app-wide, so a view setting it changes
    /// nothing.
    var undoShortcuts: UndoShortcuts {
        get { self[UndoShortcutsKey.self] }
        set { self[UndoShortcutsKey.self] = newValue }
    }
}

extension Scene {
    /// Rebinds the keys that undo and redo, app-wide.
    ///
    /// TUI-specific: SwiftUI's undo is the Edit menu's ⌘Z, which no terminal
    /// sends, so the keys are TUIkit's own (``UndoCommand/defaultShortcuts``).
    /// A command not mentioned keeps its defaults; a value replaces them
    /// (`[chord]`, ``ShortcutSet/only(_:)``), adds to them
    /// (`.default.and(…)`) or removes them all (``ShortcutSet/unbound``).
    ///
    /// The case it is for: Ctrl-Z, bound to undo by default, is also the
    /// shell's suspend key. An app whose users expect Ctrl-Z to stop it takes
    /// Ctrl-Z out of undo, and Ctrl-Z suspends again, exactly as it did:
    ///
    /// ```swift
    /// WindowGroup { ContentView() }
    ///     .undoShortcuts([.undo: .only(.init("-", modifiers: .control), .init("/", modifiers: .control))])
    /// ```
    ///
    /// The status bar's "undo" and "redo" name the first key of each that the
    /// terminal can deliver; a focused text control's own Ctrl-Z and
    /// Ctrl-Shift-Z, the stand-ins for ⌘Z and ⇧⌘Z, are the control's and
    /// unaffected. See ``UndoShortcuts``.
    ///
    /// - Parameter overrides: The app's changes, by command.
    /// - Returns: A scene whose undo and redo keys are these.
    public func undoShortcuts(_ overrides: [UndoCommand: ShortcutSet]) -> some Scene {
        _EnvironmentScene(content: self) { $0.undoShortcuts = UndoShortcuts(overrides) }
    }
}
