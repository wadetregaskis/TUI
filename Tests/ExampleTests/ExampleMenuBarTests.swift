//  🖥️ TUI — A Terminal UI framework for Swift
//  ExampleMenuBarTests.swift
//
//  The Example's menu bar: no File menu, a Go menu with its keys, the View
//  menu's submenus, and a customizable top bar.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUI
@testable import TUIFoundation
import TUITesting

@MainActor
@Suite("The Example's menu bar", .serialized)
struct ExampleMenuBarTests {
    /// The Example's string for `key`: in this process its strings are not
    /// registered (another suite reads the keys themselves), so the key.
    private func text(_ key: String) -> String { L(key) }

    private func launched() -> TestApp {
        TestApp(ExampleApp(), width: 120, height: 40)
    }

    /// Opens the menu titled `title` with a click on it: the bar is the top
    /// row, the first place it is looked for.
    private func open(_ title: String, in app: TestApp) throws {
        try app.click(" \(title) ")
    }

    /// The Example opens several windows, so its File menu holds Close and
    /// Close All (owner ruling O9, 2026-10-26).
    @Test("The bar has File, View and Go, and Go shows its keys")
    func goMenu() throws {
        let app = launched()
        let bar = app.screen.lines[0]
        #expect(bar.contains(" View ") && bar.contains(" \(text("commands.go")) "), "\(bar)")
        #expect(bar.contains(" File "), "\(bar)")
        try open(text("commands.go"), in: app)
        #expect(app.screen.line(containing: text("commands.previousPage"))?.contains("⌃B") == true, "\(app.screen)")
        #expect(app.screen.line(containing: text("commands.nextPage"))?.contains("⌃T") == true, "\(app.screen)")
        app.press(.escape)
    }

    @Test("⌃T goes to the next page, and ⌃B back")
    func goKeys() {
        let app = launched()
        let before = app.screen
        app.press(.character("t"), modifiers: .control)
        #expect(app.screen.text != before.text, "a page other than the main menu")
        app.press(.character("b"), modifiers: .control)
        #expect(app.screen.text == before.text, "back on the main menu")
    }

    @Test("View holds TUI's display commands and the text styling toggles, each a submenu")
    func viewSubmenus() throws {
        let app = launched()
        try open("View", in: app)
        let titles = ["Palette", "Border Style", "Control Style", text("commands.textStyling")]
        for title in titles + ["Customize Toolbar"] {
            #expect(app.screen.contains(title), "\(title): \(app.screen)")
        }
        app.press(.escape)
    }

    /// Opens View with a click, goes to the submenu `row` rows down (a menu
    /// opened by a click has no row highlighted: Down highlights the first),
    /// opens it, and returns its rows; then chooses its `item`th option (from
    /// 0), or closes it where `item` is nil.
    private func submenu(row: Int, choosing item: Int?, in app: TestApp) throws -> [String] {
        try open("View", in: app)
        app.press(.down, times: row + 1)
        app.press(.right)
        let shown = app.screen.lines
        guard let item else {
            app.press(.escape, times: 2)
            return shown
        }
        app.press(.down, times: item)
        app.press(.enter)
        return shown
    }

    @Test("View ▸ Palette and Control Style choose into the app's own state; Border Style through the manager")
    func viewSubmenusChoose() throws {
        let app = launched()
        let amber = PaletteRegistry.all[1].name
        let palettes = try submenu(row: 0, choosing: nil, in: app)
        #expect(!palettes.contains { $0.contains("✓") && $0.contains(amber) }, "sanity: \(palettes)")
        _ = try submenu(row: 0, choosing: 1, in: app)
        let chosen = try submenu(row: 0, choosing: nil, in: app)
        #expect(chosen.contains { $0.contains("✓") && $0.contains(amber) }, "the app's palette: \(chosen)")
        _ = try submenu(row: 2, choosing: 2, in: app)
        let styles = try submenu(row: 2, choosing: nil, in: app)
        #expect(styles.contains { $0.contains("✓") && $0.contains("Lines") }, "the app's control style: \(styles)")
        _ = try submenu(row: 1, choosing: 3, in: app)
        let borders = try submenu(row: 1, choosing: nil, in: app)
        #expect(borders.contains { $0.contains("✓") && $0.contains("Heavy") }, "the manager's border: \(borders)")
    }

    @Test("Every control-style picker offers Thick Braille, two dots thick, as the appearances do")
    func controlStylesOfferThickBraille() {
        // One list feeds View ▸ Control Style, the Theme page and the Buttons
        // page's looks grid (owner, 2026-10-24: "'Thick Braille' is missing").
        let thick = ExampleStyling.controlStyles.first { $0.style == .braille(thickness: 2) }
        #expect(thick?.key == "controlStyle.thickBraille")
        #expect(ExampleStrings.g20["en"]?["controlStyle.thickBraille"] == "Thick Braille")
    }

    @Test("The top bar is customizable: Customize Toolbar… opens its panel")
    func customizeToolbar() throws {
        let app = launched()
        try open("View", in: app)
        try app.click("Customize Toolbar")
        #expect(app.screen.contains(text("commands.nextPalette")), "the panel offers the hidden items: \(app.screen)")
    }
}
