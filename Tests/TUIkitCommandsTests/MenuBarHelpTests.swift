//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuBarHelpTests.swift
//
//  The scene's own Help menu: Show Tooltips, whether tooltips show at all,
//  and Show All Tooltips (⌥?), every one on the screen at once — each enabled
//  only where a view on the screen has help.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCommands
@testable import TUIkitFoundation
import TUIkitTextInput

// MARK: - Fixtures

/// A focused button with help, and a text with help, under a menu bar.
private struct HelpfulApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            VStack {
                Button("PAGE") {}.help("Explains the button")
                Text("LABEL").help("Explains the label")
            }
        }
        .commands { CommandMenu("Note") {} }
    }
}

/// The same with no help anywhere.
private struct HelplessApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Button("PAGE") {} }
            .commands { CommandMenu("Note") {} }
    }
}

/// What a field typed, reachable from an `App`.
private final class FieldProbe: @unchecked Sendable {
    static let shared = FieldProbe()
    var text = ""
}

/// A focused text field with help.
private struct FieldHelpApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            TextField("Name", text: Binding(get: { FieldProbe.shared.text }, set: { FieldProbe.shared.text = $0 }))
                .help("Explains the field")
        }
        .commands { CommandMenu("Note") {} }
    }
}

// MARK: - Tests

@MainActor
@Suite("The Help menu's tooltips", .serialized)
struct MenuBarHelpTests {
    private var now: Int64 = 0

    private mutating func frame<A: App>(_ app: HeadlessApp<A>) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private func shows<A: App>(_ text: String, _ app: HeadlessApp<A>) -> Bool {
        app.screen.contains { $0.stripped.contains(text) }
    }

    private mutating func launched<A: App>(_ app: A) -> HeadlessApp<A> {
        let headless = HeadlessApp(app, width: 60, height: 16)
        frame(headless)
        frame(headless)
        return headless
    }

    /// Opens the Help menu, the bar's last, and chooses its item `downs`
    /// places past the first enabled one.
    private mutating func chooseHelp<A: App>(item downs: Int, in app: HeadlessApp<A>) {
        app.send(KeyEvent(key: .f10))
        frame(app)
        app.send(KeyEvent(key: .left))
        frame(app)
        for _ in 0..<downs {
            app.send(KeyEvent(key: .down))
            frame(app)
        }
        app.send(KeyEvent(key: .enter))
        frame(app)
        frame(app)
    }

    @Test("The bar has a Help menu holding Show Tooltips, checked, and Show All Tooltips with ⌥?")
    mutating func helpMenu() {
        let app = launched(HelpfulApp())
        #expect(app.screen[0].stripped.contains("Help"), "\(app.screen[0].stripped)")
        app.send(KeyEvent(key: .f10))
        frame(app)
        app.send(KeyEvent(key: .left))
        frame(app)
        let rows = app.screen.map(\.stripped)
        #expect(rows.contains { $0.contains("Show Tooltips") && $0.contains("■") }, "\(rows)")
        #expect(rows.contains { $0.contains("Show All Tooltips") && $0.contains("⌥?") }, "\(rows)")
    }

    @Test("Show All Tooltips shows every view's help at once, and then reads Hide All Tooltips")
    mutating func showAll() {
        let app = launched(HelpfulApp())
        app.services.tooltipState.showsAllTooltips = false
        #expect(!shows("Explains the label", app), "sanity: no tooltip yet")
        chooseHelp(item: 1, in: app)
        #expect(shows("Explains the label", app) && shows("Explains the button", app), "\(app.screen.map(\.stripped))")
        app.send(KeyEvent(key: .f10))
        frame(app)
        app.send(KeyEvent(key: .left))
        frame(app)
        #expect(shows("Hide All Tooltips", app), "\(app.screen.map(\.stripped))")
        app.send(KeyEvent(key: .escape))
        frame(app)
    }

    @Test("⌥? shows every tooltip, and again hides them; ? alone still reveals the focused view's")
    mutating func optionHelpKey() {
        let app = launched(HelpfulApp())
        #expect(app.send(KeyEvent(key: .character("?"), alt: true)))
        frame(app)
        #expect(shows("Explains the label", app), "\(app.screen.map(\.stripped))")
        app.send(KeyEvent(key: .character("?"), alt: true))
        frame(app)
        frame(app)
        #expect(!shows("Explains the label", app), "\(app.screen.map(\.stripped))")
        app.send(KeyEvent(key: .character("?")))
        frame(app)
        #expect(shows("Explains the button", app), "\(app.screen.map(\.stripped))")
        #expect(!shows("Explains the label", app), "\(app.screen.map(\.stripped))")
    }

    @Test("Inside a text field, which types ?, ⌥? still shows every tooltip, typing nothing")
    mutating func optionHelpKeyInAField() {
        FieldProbe.shared.text = ""
        let app = launched(FieldHelpApp())
        #expect(app.send(KeyEvent(key: .character("?"), alt: true)))
        frame(app)
        #expect(shows("Explains the field", app), "\(app.screen.map(\.stripped))")
        #expect(FieldProbe.shared.text.isEmpty)
    }

    @Test("With Show Tooltips off, the help key reveals nothing, and ⌥? shows nothing")
    mutating func showTooltipsOff() {
        let app = launched(HelpfulApp())
        chooseHelp(item: 0, in: app)
        #expect(!app.services.tooltipState.showsTooltips)
        app.send(KeyEvent(key: .character("?")))
        frame(app)
        #expect(!shows("Explains the button", app), "\(app.screen.map(\.stripped))")
        #expect(!app.send(KeyEvent(key: .character("?"), alt: true)), "nothing to show: the key falls through")
        chooseHelp(item: 0, in: app)
        #expect(app.services.tooltipState.showsTooltips, "Show Tooltips stays enabled to turn them back on")
    }

    @Test("With no view on the screen having help, both items are disabled and ⌥? does nothing")
    mutating func nothingToShow() {
        let app = launched(HelplessApp())
        chooseHelp(item: 0, in: app)
        #expect(app.services.tooltipState.showsTooltips, "Show Tooltips was disabled")
        #expect(!app.services.tooltipState.showsAllTooltips)
        #expect(!app.send(KeyEvent(key: .character("?"), alt: true)))
    }
}
