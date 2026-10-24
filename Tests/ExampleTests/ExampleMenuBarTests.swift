//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ExampleMenuBarTests.swift
//
//  The Example's menu bar: no File menu, a Go menu with its keys, the View
//  menu's submenus, and a customizable top bar.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation

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

    @Test("The bar has View and Go but no File menu, and Go shows its keys")
    mutating func goMenu() throws {
        let app = launched()
        let bar = rows(app)[0]
        #expect(bar.contains(" View ") && bar.contains(" \(text("commands.go")) "), "\(bar)")
        #expect(!bar.contains(" File "), "\(bar)")
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

    @Test("View holds the palette and border style pickers and the text styling toggles, each a submenu")
    mutating func viewSubmenus() throws {
        let app = launched()
        try open("View", in: app)
        let menu = rows(app)
        let titles = ["commands.palette", "commands.borderStyle", "commands.textStyling"].map(text)
        for title in titles + ["Customize Toolbar"] {
            #expect(menu.contains { $0.contains(title) }, "\(title): \(menu)")
        }
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
