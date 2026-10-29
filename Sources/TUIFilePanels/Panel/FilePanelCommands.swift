//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelCommands.swift
//
//  A file panel's Finder chords — the views, the preview, up and down, the
//  Go menu's places, New Folder, hidden files and cancel — each through the
//  app's `commandKey`. The owner asked for them on 2026-10-28.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation

/// One of a file panel's chords: the keys Finder and a macOS open or save
/// panel give the same things, written with ⌘ as macOS writes them and
/// resolved through the app's ``EnvironmentValues/commandKey`` (⌃ by
/// default), as a ⌘ shortcut is (``KeyboardShortcut``).
///
/// | Chord | Under `.control` | Does |
/// |---|---|---|
/// | ⌘2, ⌘3 | ⌃2, ⌃3 | the list view, the column view (Finder's numbers; ⌘1 and ⌘4, the icon and gallery views, have none to choose) |
/// | ⇧⌘P | ⌃⇧P | shows or hides the preview (Finder's View ▸ Show Preview) |
/// | ⌘↑ | ⌃↑ | the enclosing folder |
/// | ⌘↓ | ⌃↓ | opens the folder selected, or chooses the file, as Return does |
/// | ⇧⌘G | ⌃⇧G | the go-to field (`/`) |
/// | ⇧⌘H, ⇧⌘D, ⌥⌘L, ⇧⌘O, ⇧⌘A | ⌃⇧H, ⌃⇧D, ⌥⌃L, ⌃⇧O, ⌃⇧A | home, Desktop, Downloads, Documents, Applications — where the folder exists |
/// | ⇧⌘N | ⌃⇧N | New Folder, where the panel makes folders (`+`) |
/// | ⇧⌘. | ⌃⇧. | shows or hides the hidden files |
/// | ⌘. | ⌃. | cancels, as Escape does (or closes the go-to field) |
///
/// Not every one can arrive. In a terminal's legacy encodings a Control
/// letter is a C0 byte, which has no case, so Shift is lost on it and ⌃⇧P
/// arrives as ⌃P (`KeyboardReporting.reportsShiftedKeys`); ⌃2, ⌃3 and ⌃.
/// have no byte of their own, and by xterm's convention, which TUI has not
/// measured (Documentation/Terminals/Terminal compatibility survey.md), many
/// terminals send ⌃2 as NUL (dropped), ⌃3 as Escape (which cancels) and ⌃.
/// as a plain `.`; and macOS takes ⌃↑ and ⌃↓ for Mission Control in every
/// terminal, as Apple Terminal strips the modifiers from ↑ and ↓ (the
/// survey's "Keys a sheet's grabber uses"). Under the kitty keyboard protocol they all arrive. So the panel's
/// typed keys — Backspace, `~`, `/`, `+` and Escape — stay its portable
/// route, and the status bar names these chords only where the protocol is
/// on (``FilePanel/statusItems(viewMode:createsFolders:chords:)``).
enum FilePanelCommand: CaseIterable {
    case listView, columnsView, togglePreview, enclosingFolder, openSelection, goToFolder
    case home, desktop, downloads, documents, applications, newFolder, toggleHiddenFiles, cancel

    /// The chords, as macOS writes them: ⌘ and all, for `commandKey` to
    /// resolve. Hidden files has two spellings of ⇧⌘.: a terminal says Shift
    /// on a key that types a character by the character, so under the kitty
    /// keyboard protocol with its alternate keys it arrives as ⌘> (on a US
    /// keyboard), and without them as `.` with the Shift bit, which only a
    /// key that types no capital keeps (``trigger(for:)``).
    var shortcuts: [KeyboardShortcut] {
        switch self {
        case .listView: [KeyboardShortcut("2")]
        case .columnsView: [KeyboardShortcut("3")]
        case .togglePreview: [KeyboardShortcut("p", modifiers: [.command, .shift])]
        case .enclosingFolder: [KeyboardShortcut(.upArrow)]
        case .openSelection: [KeyboardShortcut(.downArrow)]
        case .goToFolder: [KeyboardShortcut("g", modifiers: [.command, .shift])]
        case .home: [KeyboardShortcut("h", modifiers: [.command, .shift])]
        case .desktop: [KeyboardShortcut("d", modifiers: [.command, .shift])]
        case .downloads: [KeyboardShortcut("l", modifiers: [.command, .option])]
        case .documents: [KeyboardShortcut("o", modifiers: [.command, .shift])]
        case .applications: [KeyboardShortcut("a", modifiers: [.command, .shift])]
        case .newFolder: [KeyboardShortcut("n", modifiers: [.command, .shift])]
        case .toggleHiddenFiles: [KeyboardShortcut(">"), KeyboardShortcut(".", modifiers: [.command, .shift])]
        case .cancel: [KeyboardShortcut(".")]
        }
    }

    /// The commands under `commandKey`, by the trigger an event fires
    /// (``trigger(for:)``); empty under ``CommandKeyBinding/unavailable``.
    static func table(commandKey: CommandKeyBinding) -> [KeyboardShortcut.Trigger: Self] {
        var table: [KeyboardShortcut.Trigger: Self] = [:]
        for command in allCases {
            for shortcut in command.shortcuts {
                if let resolved = shortcut.resolved(commandKey: commandKey) { table[resolved.trigger] = command }
            }
        }
        return table
    }

    /// The trigger `event` fires, as a shortcut matches it
    /// (`KeyboardShortcut.trigger(for:)`), but with the Shift bit kept on a
    /// key that has no capital to carry it: the only way a terminal without
    /// the kitty protocol's alternate keys says ⇧⌘., which would otherwise
    /// read as ⌘., cancel.
    static func trigger(for event: KeyEvent) -> KeyboardShortcut.Trigger? {
        guard let trigger = KeyboardShortcut.trigger(for: event) else { return nil }
        if event.shift, case .key(let key, let modifiers) = trigger, !key.character.isLetter,
            case .character = event.key
        {
            return .key(key, modifiers.union(.shift))
        }
        return trigger
    }

    /// The first chord as the status bar names it under `commandKey` (`⌃⇧P`),
    /// or `nil` where no key stands in for ⌘.
    func displayString(commandKey: CommandKeyBinding) -> String? {
        shortcuts.first?.resolved(commandKey: commandKey)?.displayString
    }

    /// The folder a Go chord goes to — in `home`, or for Applications the
    /// system's — where it exists; `nil` where it does not (Applications on
    /// Linux), and for the other commands.
    func place(home: URL) -> URL? {
        let place: URL? =
            switch self {
            case .home: home
            case .desktop: home.appendingPathComponent("Desktop", isDirectory: true)
            case .downloads: home.appendingPathComponent("Downloads", isDirectory: true)
            case .documents: home.appendingPathComponent("Documents", isDirectory: true)
            case .applications: URL(fileURLWithPath: "/Applications", isDirectory: true)
            default: nil
            }
        var isDirectory: ObjCBool = false
        guard let place, FileManager.default.fileExists(atPath: place.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return place
    }
}

extension View {
    /// The panel's chords (``FilePanelCommand``) on this view, heard while
    /// the focus is on it or inside it, and before the app's shortcuts.
    /// `perform` answers whether it took the key.
    ///
    /// Most once the focused control has let the key go — the stage
    /// `onExitCommand` is heard at — so a field keeps a chord it reads as its
    /// own (an Emacs ⌃D in the name field, where ⇧⌘D's Shift is lost), where
    /// an `onKeyPress` on the panel would have taken it first. But ⌘↑ and ⌘↓
    /// before it, as an `onKeyPress` is heard: a table or a list reads ⌃↑
    /// and ⌃↓ as ↑ and ↓ where it has no row to move, and never let them go.
    ///
    /// A press, not a release; and a repeat only for ⌘↑, which climbs as
    /// Backspace does, where a held ⇧⌘P would flicker the pane.
    func filePanelCommands(_ perform: @escaping (FilePanelCommand) -> Bool) -> some View {
        let arrows: Set<FilePanelCommand> = [.enclosingFolder, .openSelection]
        let commands = FocusPathModifier(content: self, stage: .command) { context in
            FilePanelCommand.handler(context: context, perform: perform) { !arrows.contains($0) }
        }
        return FocusPathModifier(content: commands, stage: .keyPress) { context in
            FilePanelCommand.handler(context: context, perform: perform) { arrows.contains($0) }
        }
    }
}

extension FilePanelCommand {
    /// The key handler for the commands `taking` accepts, resolved through
    /// `context`'s `commandKey`: ``View/filePanelCommands(_:)``'s, at either
    /// stage.
    @MainActor
    static func handler(
        context: RenderContext, perform: @escaping (Self) -> Bool, taking: @escaping (Self) -> Bool
    ) -> (KeyEvent) -> Bool {
        let table = table(commandKey: context.environment.commandKey)
        return { event in
            guard event.phase != .release, let trigger = trigger(for: event), let command = table[trigger],
                taking(command), event.phase == .press || command == .enclosingFolder
            else { return false }
            return perform(command)
        }
    }
}
