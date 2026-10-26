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
@testable import TUIApp
@testable import TUIFoundation

@MainActor
@Suite("The Example's menu bar", .serialized)
struct ExampleMenuBarTests {
    private var now: Int64 = 0

    private mutating func frame(_ app: HeadlessApp<ExampleApp>) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private func rows(_ app: HeadlessApp<ExampleApp>) -> [String] { app.screen.map(\.stripped) }

    /// The Example's string for `key`: in this process its strings are not
    /// registered (another suite reads the keys themselves), so the key.
    private func text(_ key: String) -> String { L(key) }

    private mutating func launched() -> HeadlessApp<ExampleApp> {
        let app = HeadlessApp(ExampleApp(), width: 120, height: 40)
        frame(app)
        frame(app)
        return app
    }

    /// Opens the menu titled `title` with a click on it.
    private mutating func open(_ title: String, in app: HeadlessApp<ExampleApp>) throws {
        let bar = rows(app)[0]
        let x = try #require(bar.range(of: " \(title) ")).lowerBound.utf16Offset(in: bar) + 1
        app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: 0))
        app.send(MouseEvent(button: .left, phase: .released, x: x, y: 0))
        frame(app)
    }

    /// The Example opens several windows, so its File menu holds Close and
    /// Close All (owner ruling O9, 2026-10-26).
    @Test("The bar has File, View and Go, and Go shows its keys")
    mutating func goMenu() throws {
        let app = launched()
        let bar = rows(app)[0]
        #expect(bar.contains(" View ") && bar.contains(" \(text("commands.go")) "), "\(bar)")
        #expect(bar.contains(" File "), "\(bar)")
        try open(text("commands.go"), in: app)
        let menu = rows(app)
        #expect(menu.contains { $0.contains(text("commands.previousPage")) && $0.contains("⌃B") }, "\(menu)")
        #expect(menu.contains { $0.contains(text("commands.nextPage")) && $0.contains("⌃T") }, "\(menu)")
        app.send(KeyEvent(key: .escape))
        frame(app)
    }

    @Test("⌃T goes to the next page, and ⌃B back")
    mutating func goKeys() {
        let app = launched()
        let before = rows(app).joined(separator: "\n")
        app.send(KeyEvent(key: .character("t"), ctrl: true))
        frame(app)
        frame(app)
        let next = rows(app).joined(separator: "\n")
        #expect(next != before, "a page other than the main menu")
        app.send(KeyEvent(key: .character("b"), ctrl: true))
        frame(app)
        frame(app)
        #expect(rows(app).joined(separator: "\n") == before, "back on the main menu")
    }

    @Test("View holds TUI's display commands and the text styling toggles, each a submenu")
    mutating func viewSubmenus() throws {
        let app = launched()
        try open("View", in: app)
        let menu = rows(app)
        let titles = ["Palette", "Border Style", "Control Style", text("commands.textStyling")]
        for title in titles + ["Customize Toolbar"] {
            #expect(menu.contains { $0.contains(title) }, "\(title): \(menu)")
        }
        app.send(KeyEvent(key: .escape))
        frame(app)
    }

    /// Opens View with a click, goes to the submenu `row` rows down (a menu
    /// opened by a click has no row highlighted: Down highlights the first),
    /// opens it, and returns its rows; then chooses its `item`th option (from
    /// 0), or closes it where `item` is nil.
    private mutating func submenu(row: Int, choosing item: Int?, in app: HeadlessApp<ExampleApp>) throws -> [String] {
        try open("View", in: app)
        for _ in 0...row {
            app.send(KeyEvent(key: .down))
            frame(app)
        }
        app.send(KeyEvent(key: .right))
        frame(app)
        let shown = rows(app)
        guard let item else {
            app.send(KeyEvent(key: .escape))
            frame(app)
            app.send(KeyEvent(key: .escape))
            frame(app)
            return shown
        }
        for _ in 0..<item {
            app.send(KeyEvent(key: .down))
            frame(app)
        }
        app.send(KeyEvent(key: .enter))
        frame(app)
        frame(app)
        return shown
    }

    @Test("View ▸ Palette and Control Style choose into the app's own state; Border Style through the manager")
    mutating func viewSubmenusChoose() throws {
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
    mutating func customizeToolbar() throws {
        let app = launched()
        try open("View", in: app)
        let menu = rows(app)
        let line = try #require(menu.firstIndex { $0.contains("Customize Toolbar") }, "\(menu)")
        let x = try #require(menu[line].range(of: "Customize")).lowerBound.utf16Offset(in: menu[line])
        app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: line))
        app.send(MouseEvent(button: .left, phase: .released, x: x, y: line))
        frame(app)
        frame(app)
        frame(app)
        let panel = rows(app)
        #expect(
            panel.contains { $0.contains(text("commands.nextPalette")) }, "the panel offers the hidden items: \(panel)")
    }
}
