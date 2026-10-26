//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBarMnemonicsTests.swift
//
//  The letters that open the menu bar's menus with Option: one per title, no
//  two the same, none a focused text field keeps, underlined while Option is
//  held where the terminal reports it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICommands
@testable import TUICore
@testable import TUIFoundation
import TUITextInput

// MARK: - Fixtures

/// What the menus did, reachable from an `App`.
private final class MnemonicProbe: @unchecked Sendable {
    static let shared = MnemonicProbe()
    var text = ""
}

/// Two menus whose titles start with the same letter.
private struct ClashingApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Button("PAGE") {} }
            .commandsRemoved()
            .commands {
                CommandMenu("Fig") { Button("F1") {} }
                CommandMenu("Fog") { Button("G1") {} }
            }
    }
}

/// A focused text field under a menu whose letter is one the field keeps.
private struct FieldApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            TextField(
                "Name", text: Binding(get: { MnemonicProbe.shared.text }, set: { MnemonicProbe.shared.text = $0 }))
        }
        .commandsRemoved()
        .commands { CommandMenu("Fig") { Button("F1") {} } }
    }
}

// MARK: - The Rule

@Suite("The menu bar's letters")
struct MenuBarMnemonicRuleTests {
    @Test("Each title takes its first letter not taken before it, then the next of its own")
    func uniqueInBarOrder() {
        #expect(MenuBarMnemonics.assign([nil, "File", "Format", "Edit", "Find"]) == [nil, "f", "o", "e", "i"])
    }

    @Test("Localised titles that share a first letter get letters of their own")
    func localisedClashes() {
        #expect(MenuBarMnemonics.assign(["Fichier", "Édition", "Format", "Fenêtre"]) == ["f", "d", "o", "e"])
        #expect(MenuBarMnemonics.assign(["Archivo", "Ayuda"]) == ["a", "y"])
    }

    @Test("A title with no ASCII letter left has none")
    func noLetterLeft() {
        #expect(MenuBarMnemonics.assign(["ab", "ba", "表示"]) == ["a", "b", nil])
    }

    @Test("Letters a focused field keeps move only the titles that had them")
    func keptLettersMoveOnlyTheirTitles() {
        #expect(
            MenuBarMnemonics.assign([nil, "File", "Edit", "Bookmarks", "View"], keeping: ["b", "f"])
                == [nil, "i", "e", "o", "v"])
    }
}

// MARK: - In a Running Bar

@MainActor
@Suite("The menu bar's letters, in the bar", .serialized)
struct MenuBarMnemonicsTests {
    private var now: Int64 = 0

    private mutating func frame<A: App>(_ app: HeadlessApp<A>) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private func shows<A: App>(_ text: String, _ app: HeadlessApp<A>) -> Bool {
        app.screen.dropFirst().contains { $0.stripped.contains(text) }
    }

    /// Whether `line` turns underlining on anywhere: SGR 4, alone or among
    /// other parameters.
    private func underlines(_ line: String) -> Bool {
        line.contains("\u{1B}[4m") || line.contains("\u{1B}[4;") || line.contains(";4m") || line.contains(";4;")
    }

    @Test("Of two titles sharing a first letter, the second opens with its next letter")
    mutating func clashingTitles() {
        let app = HeadlessApp(ClashingApp(), width: 40, height: 10)
        frame(app)
        app.send(KeyEvent(key: .character("o"), alt: true))
        frame(app)
        #expect(shows("G1", app), "\(app.screen.map(\.stripped))")
    }

    @Test("While a text field has the focus, it keeps Option-F, and the title that had F takes its next letter")
    mutating func fieldKeepsItsLetters() {
        MnemonicProbe.shared.text = "one two"
        let app = HeadlessApp(FieldApp(), width: 40, height: 10)
        frame(app)
        frame(app)
        app.send(KeyEvent(key: .character("f"), alt: true))
        frame(app)
        #expect(!shows("F1", app), "Option-F is the field's: \(app.screen.map(\.stripped))")
        app.send(KeyEvent(key: .character("i"), alt: true))
        frame(app)
        #expect(shows("F1", app), "\(app.screen.map(\.stripped))")
    }

    @Test("Where the terminal reports Option held alone, the titles' letters are underlined while it is held")
    mutating func underlinedWhileOptionHeld() {
        let app = HeadlessApp(ClashingApp(), width: 40, height: 10)
        app.keyboardReporting = KeyboardReporting(flags: .requested)
        frame(app)
        #expect(!underlines(app.screen[0]), "\(app.screen[0].debugDescription)")
        #expect(!app.send(ModifierKeyState(shift: true)), "Shift alone asks for no frame")
        #expect(app.send(ModifierKeyState(option: true)), "Option asks for a frame")
        frame(app)
        #expect(underlines(app.screen[0]), "\(app.screen[0].debugDescription)")
        #expect(app.screen[0].stripped.hasPrefix(" Fig  Fog "), "\(app.screen[0].stripped)")
        app.send(ModifierKeyState())
        frame(app)
        #expect(!underlines(app.screen[0]), "\(app.screen[0].debugDescription)")
    }

    @Test("Where the terminal does not report modifier keys, nothing is underlined")
    mutating func nothingUnderlinedInALegacyTerminal() {
        let app = HeadlessApp(ClashingApp(), width: 40, height: 10)
        frame(app)
        app.send(ModifierKeyState(option: true))
        frame(app)
        #expect(!underlines(app.screen[0]), "\(app.screen[0].debugDescription)")
    }
}
