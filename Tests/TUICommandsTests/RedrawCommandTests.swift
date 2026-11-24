//  🖥️ TUI — A Terminal UI framework for Swift
//  RedrawCommandTests.swift
//
//  H-72 (WRITER-2), the owner's O-15 (a), 2026-11-21: View ▸ Redraw, on F5,
//  throws away the frame writer's picture of the screen and repaints every
//  row on the next frame, as a resize does, for a screen something else has
//  written over (a stray `print`, a library's stderr).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
@testable import TUIFoundation
import TUITesting

// MARK: - Fixtures

/// A page of lines, under a menu bar.
private struct BarApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { RedrawPage() }
            .commands { CommandMenu("Note") {} }
    }
}

/// The same page with no menu bar.
private struct BarlessApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { RedrawPage() }
    }
}

/// An app that binds F5 itself: its key, not the redraw.
private struct OwnF5App: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading) {
                RedrawPage()
                Button("Refresh") { RedrawProbe.shared.refreshes += 1 }
                    .keyboardShortcut(KeyEquivalent("\u{F708}"), modifiers: [])
            }
        }
        .commands { CommandMenu("Note") {} }
    }
}

/// What the app's own F5 did, reachable from an `App`.
private final class RedrawProbe: @unchecked Sendable {
    static let shared = RedrawProbe()
    var refreshes = 0
}

private struct RedrawPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<12, id: \.self) { Text(verbatim: "line \($0) of a page that is drawn once") }
        }
    }
}

// MARK: - Tests

@MainActor
@Suite("View ▸ Redraw and F5 repaint every row", .serialized)
struct RedrawCommandTests {
    private var now: Int64 = 0

    private mutating func frame(_ app: TestApp) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private mutating func launched<A: App>(_ app: A) -> TestApp {
        let headless = TestApp(app, width: 60, height: 30)
        frame(headless)
        frame(headless)
        return headless
    }

    /// The bytes `act` and the next frames write.
    private mutating func bytes(of app: TestApp, after act: (TestApp) -> Void) -> Int {
        let before = app.bytesWritten
        act(app)
        frame(app)
        frame(app)
        return app.bytesWritten - before
    }

    /// The bytes of a frame with every row rewritten: a resize to the same
    /// size, which throws the writer's picture away as `SIGWINCH` does.
    private mutating func repaintBytes(of app: TestApp) -> Int {
        bytes(of: app) { $0.resize(width: 60, height: 30) }
    }

    @Test("F5 rewrites every row on the next frame, as a resize does, and nothing after")
    mutating func f5Repaints() {
        let app = launched(BarlessApp())
        let repaint = repaintBytes(of: app)
        let idle = bytes(of: app) { _ in }
        #expect(idle * 10 < repaint, "a frame with nothing new writes little: \(idle) of \(repaint)")
        let screen = app.screen.lines
        let redraw = bytes(of: app) { $0.send(KeyEvent(key: .f5)) }
        #expect(redraw * 10 >= repaint * 9, "F5 wrote \(redraw) bytes; a full repaint writes \(repaint)")
        #expect(app.screen.lines == screen, "the same page, drawn again")
        #expect(bytes(of: app) { _ in } * 10 < repaint, "once")
    }

    @Test("The View menu offers Redraw, showing F5, and choosing it repaints every row")
    mutating func menuItem() {
        let app = launched(BarApp())
        let repaint = repaintBytes(of: app)
        let titles = app.screen.lines[0].split(separator: " ").map(String.init)
        let rights = titles.firstIndex(of: "View") ?? 0
        for key: Key in [.f10] + Array(repeating: .right, count: rights) + [.down] {
            app.send(KeyEvent(key: key))
            frame(app)
        }
        let menu = app.screen.lines
        let row = menu.first { $0.contains("Redraw") }
        #expect(row?.contains("F5") == true, "\(menu.joined(separator: "\n"))")
        // Redraw is the View menu's last item: past Palette, Border Style and
        // Control Style, the four View preferences and the four
        // Accessibility ones.
        for _ in 0..<Self.redrawRow {
            app.send(KeyEvent(key: .down))
            frame(app)
        }
        app.send(KeyEvent(key: .enter))
        frame(app)
        // The frame that closes the menu repaints what it covered; the
        // redraw is the frame after it, once the menu is gone.
        let redraw = bytes(of: app) { _ in }
        #expect(redraw * 10 >= repaint * 9, "Redraw wrote \(redraw) bytes; a full repaint writes \(repaint)")
        #expect(!app.screen.contains("Redraw"), "the menu closed:\n\(app.screen)")
    }

    @Test("F1's list names F5 under General, with no menu bar to show it")
    mutating func listed() {
        let app = launched(BarlessApp())
        app.send(KeyEvent(key: .f1))
        frame(app)
        frame(app)
        let row = app.screen.lines.first { $0.contains("Redraw") }
        #expect(row?.contains("F5") == true, "\(app.screen)")
    }

    /// Rows down from View's first item to Redraw.
    private static let redrawRow = 11

    @Test("An app's own F5 comes first, and the menu then names no key for Redraw")
    mutating func appsOwnF5() {
        RedrawProbe.shared.refreshes = 0
        let app = launched(OwnF5App())
        let repaint = repaintBytes(of: app)
        let pressed = bytes(of: app) { $0.send(KeyEvent(key: .f5)) }
        #expect(RedrawProbe.shared.refreshes == 1)
        #expect(pressed * 10 < repaint, "the app's key, no repaint: \(pressed) of \(repaint)")
        let titles = app.screen.lines[0].split(separator: " ").map(String.init)
        let rights = titles.firstIndex(of: "View") ?? 0
        for key: Key in [.f10] + Array(repeating: .right, count: rights) + [.down] {
            app.send(KeyEvent(key: key))
            frame(app)
        }
        let row = app.screen.lines.first { $0.contains("Redraw") }
        #expect(row != nil && row?.contains("F5") == false, "\(app.screen)")
    }
}
