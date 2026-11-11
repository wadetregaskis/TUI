//  🖥️ TUI — A Terminal UI framework for Swift
//  ExampleSettingsPanelTests.swift
//
//  The settings panel as the owner met it in the Example (2026-11-10): drawn
//  in a box, and its View tab's Palette and Control Style live, choosing into
//  the app's own state as the View menu does.
//
//  Created by Wade Tregaskis
//  License: MIT

// Only where the package can depend on the app (see Package.swift).
#if canImport(Example)

import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("The Example's settings panel", .serialized)
struct ExampleSettingsPanelTests {
    /// The Example with its settings panel up, on TUI's View tab: the strip's
    /// cursor moved one along from the app's own tab, and chosen.
    private func viewTab() -> TestApp {
        let app = TestApp(ExampleApp(), width: 100, height: 40)
        app.press(.f2)
        app.press(.right)
        app.press(.space)
        return app
    }

    @Test("The panel is drawn in a box, titled")
    func bordered() throws {
        let app = viewTab()
        let title = try #require(app.screen.line(containing: "Settings"), "\(app.screen)")
        #expect(title.contains("─"), "the title sits in the top border: \(app.screen)")
        let done = try #require(app.screen.line(containing: "Done"), "\(app.screen)")
        #expect(done.contains("│"), "inside the box: \(app.screen)")
    }

    @Test("Palette and Control Style are live: the app's state, handed to DisplayCommands, is the panel's too")
    func paletteAndControlStyleLive() {
        let app = viewTab()
        #expect(app.screen.contains("Palette") && app.screen.contains("Control Style"), "\(app.screen)")
        #expect(!app.screen.contains("The app sets this itself"), "\(app.screen)")
    }
}

#endif
