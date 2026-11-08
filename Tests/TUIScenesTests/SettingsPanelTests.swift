//  🖥️ TUI — A Terminal UI framework for Swift
//  SettingsPanelTests.swift
//
//  The settings panel on F2 (the owner, 2026-11-08): in every app, menu bar
//  or not; the app's own F2 first; the `Settings` scene's tab view's tabs,
//  then TUI's View and Accessibility after a divider, which the app may hide
//  or replace; the Accessibility tab's checks the View menu's own, and never
//  saved.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
@testable import TUIFoundation
@testable import TUIScenes
import TUITabs
import TUITesting

// MARK: - Fixtures

/// What the page read, written by the view that reads it.
@MainActor
private final class MotionProbe {
    var reduceMotion: Bool?
}

/// Reads Reduce Motion, and offers a button the app may put on F2.
private struct MotionPage: View {
    let probe: MotionProbe
    var bindsF2 = false
    @State private var presses = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        probe.reduceMotion = reduceMotion
        return VStack {
            Text(verbatim: "motion \(reduceMotion ? "reduced" : "full") presses=\(presses)")
            if bindsF2 {
                Button("mine") { presses += 1 }
                    .keyboardShortcut(KeyEquivalent("\u{F705}"), modifiers: [])
            }
        }
    }
}

/// An app with a menu bar and no `Settings` scene.
private struct PlainApp: App {
    let probe: MotionProbe
    var bindsF2 = false

    init() { self.init(probe: MotionProbe()) }

    init(probe: MotionProbe, bindsF2: Bool = false) {
        self.probe = probe
        self.bindsF2 = bindsF2
    }

    var body: some Scene {
        WindowGroup { MotionPage(probe: probe, bindsF2: bindsF2) }
            .commands { CommandMenu("Note") {} }
    }
}

/// An app whose settings are a tab view.
private struct TabbedSettingsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE") }
        Settings {
            TabView {
                Tab("General", systemImage: "gear") { Text("GENERAL SETTINGS") }
                Tab("Advanced", systemImage: "star") { Text("ADVANCED SETTINGS") }
            }
        }
    }
}

/// An app that leaves out TUI's View tab, replaces its Accessibility tab and
/// moves the panel to F3.
private struct CustomizedApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE") }
            .builtInSettingsTab(.view, visibility: .hidden)
            .builtInSettingsTab(.accessibility) { Text("MY ACCESSIBILITY") }
            .settingsPanelKey(.f3)
    }
}

/// An app with no tab for the panel at all.
private struct NoTabsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE") }
            .builtInSettingsTab(.view, visibility: .hidden)
            .builtInSettingsTab(.accessibility, visibility: .hidden)
    }
}

// MARK: - Tests

@MainActor
@Suite("The settings panel", .serialized)
struct SettingsPanelTests {
    private var now: Int64 = 0

    private mutating func press(_ key: Key, in app: TestApp) {
        app.send(KeyEvent(key: key))
        frame(app)
    }

    private mutating func frame(_ app: TestApp) {
        now += 20_000_000
        app.frame(atNanos: now)
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private mutating func launched<A: App>(_ app: A) -> TestApp {
        let headless = TestApp(app, width: 70, height: 22)
        frame(headless)
        return headless
    }

    private func screen(_ app: TestApp) -> String {
        app.screen.lines.joined(separator: "\n")
    }

    /// The rows of the View menu, opened from the bar and closed again.
    private mutating func viewMenu(_ app: TestApp) -> [String] {
        let titles = app.screen.lines[0].split(separator: " ").map(String.init)
        let rights = titles.firstIndex(of: "View") ?? 0
        for key: Key in [.f10] + Array(repeating: .right, count: rights) + [.down] { press(key, in: app) }
        let rows = app.screen.lines
        press(.escape, in: app)
        press(.escape, in: app)
        return rows
    }

    @Test("F2 opens the panel in an app with no Settings scene, with TUI's tabs, and F2 or Escape closes it")
    mutating func f2OpensAndCloses() {
        let app = launched(PlainApp())
        #expect(!app.scenes.isPresentingSettings)
        press(.f2, in: app)
        #expect(app.scenes.isPresentingSettings)
        let text = screen(app)
        #expect(text.contains("View │ Accessibility"), "\(text)")
        #expect(text.contains("Palette") && text.contains("Border Style") && text.contains("Control Style"), "\(text)")
        press(.f2, in: app)
        #expect(!app.scenes.isPresentingSettings)
        press(.f2, in: app)
        press(.escape, in: app)
        #expect(!app.scenes.isPresentingSettings)
        #expect(app.quitsRequested == 0)
    }

    @Test("An app's own F2 comes first, and the panel is still reached another way")
    mutating func appsF2Wins() {
        let app = launched(PlainApp(probe: MotionProbe(), bindsF2: true))
        press(.f2, in: app)
        #expect(!app.scenes.isPresentingSettings)
        #expect(screen(app).contains("presses=1"), "\(screen(app))")
        app.scenes.actions.openSettings()
        frame(app)
        #expect(app.scenes.isPresentingSettings, "openSettings, SettingsLink and Settings… still open it")
    }

    @Test("Toggling in the Accessibility tab changes what views read, matches the View menu, and isn't kept")
    mutating func accessibilityTab() {
        let probe = MotionProbe()
        let app = launched(PlainApp(probe: probe))
        #expect(probe.reduceMotion == false)
        #expect(!viewMenu(app).contains { $0.contains("Reduce Motion") && $0.contains("■") })
        press(.f2, in: app)
        press(.right, in: app)  // the strip's cursor to Accessibility
        press(.space, in: app)  // chosen
        #expect(screen(app).contains("Differentiate Without Color"), "\(screen(app))")
        press(.tab, in: app)  // Differentiate Without Color
        press(.tab, in: app)  // Reduce Motion
        press(.space, in: app)
        #expect(probe.reduceMotion == true)
        press(.escape, in: app)
        #expect(screen(app).contains("motion reduced"), "\(screen(app))")
        let menu = viewMenu(app)
        #expect(menu.contains { $0.contains("Reduce Motion") && $0.contains("■") }, "\(menu.joined(separator: "\n"))")

        let probe2 = MotionProbe()
        let next = launched(PlainApp(probe: probe2))
        #expect(probe2.reduceMotion == false, "the next run starts from the settings")
        withExtendedLifetime(next) {}
    }

    @Test("A Settings scene's tab view gives a tab each, before TUI's, after a divider")
    mutating func tabViewTabs() {
        let app = launched(TabbedSettingsApp())
        press(.f2, in: app)
        let text = screen(app)
        let strip = app.screen.lines.first { $0.contains("Accessibility") } ?? ""
        #expect(strip.contains("General │") && strip.contains("Advanced ┃ View │ Accessibility"), "\(text)")
        #expect(text.contains("GENERAL SETTINGS"), "the app's first tab is shown first: \(text)")
        press(.right, in: app)
        press(.space, in: app)
        #expect(screen(app).contains("ADVANCED SETTINGS"), "\(screen(app))")
    }

    @Test("TUI's tabs can be hidden or replaced, and the key moved")
    mutating func customized() {
        let app = launched(CustomizedApp())
        press(.f2, in: app)
        #expect(!app.scenes.isPresentingSettings, "the key moved to F3")
        press(.f3, in: app)
        #expect(app.scenes.isPresentingSettings)
        let text = screen(app)
        #expect(text.contains("MY ACCESSIBILITY"), "\(text)")
        #expect(!text.contains("Palette"), "the View tab is left out: \(text)")
    }

    @Test("With no tab at all, the panel has nothing to show and nothing opens it")
    mutating func noTabs() {
        let app = launched(NoTabsApp())
        press(.f2, in: app)
        #expect(!app.scenes.isPresentingSettings)
        #expect(!OpenSettingsAction(handler: app.scenes.actions).isAvailable)
    }

    @Test("F1's list names F2, and names the app's F2 instead where the app binds it")
    mutating func listedInF1() {
        let app = launched(PlainApp())
        press(.f1, in: app)
        let rows = app.screen.lines
        #expect(rows.contains { $0.contains("F2") && $0.contains("Settings…") }, "\(rows.joined(separator: "\n"))")
        press(.escape, in: app)

        let binding = launched(PlainApp(probe: MotionProbe(), bindsF2: true))
        press(.f1, in: binding)
        let listed = binding.screen.lines
        #expect(listed.contains { $0.contains("F2") && $0.contains("mine") }, "\(listed.joined(separator: "\n"))")
        #expect(!listed.contains { $0.contains("F2") && $0.contains("Settings…") })
    }
}
