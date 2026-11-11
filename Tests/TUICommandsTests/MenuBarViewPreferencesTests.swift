//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBarViewPreferencesTests.swift
//
//  The View menu's accessibility and display preferences, in every menu bar:
//  the display options' submenus, then each preference a check showing
//  whether it is on, which the person turns on or off for the rest of the
//  run, over the host's setting, the `TUI_*` variable and the app's own scene
//  modifiers, kept for the program in its own store — the settings panel's View and Accessibility
//  tabs, item for item.
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

/// What the views read, written by the view that reads it.
@MainActor
private final class PreferencesProbe {
    var reduceMotion: Bool?
    var differentiateWithoutColor: Bool?
    var contrast: ColorSchemeContrast?
    var breathes: Bool?
    var notation: KeyNotation?
}

/// Reads the preferences, and shows the one the menu tests choose.
private struct PreferencesReader: View {
    let probe: PreferencesProbe
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.focusBreathes) private var breathes
    @Environment(\.keyNotation) private var notation

    var body: some View {
        probe.reduceMotion = reduceMotion
        probe.differentiateWithoutColor = differentiateWithoutColor
        probe.contrast = contrast
        probe.breathes = breathes
        probe.notation = notation
        return Text(verbatim: reduceMotion ? "MOTION REDUCED" : "MOTION FULL")
    }
}

/// An app that asks for less motion and for keys by name itself, under a
/// menu bar of the scene's own commands.
private struct PreferencesApp: App {
    let probe: PreferencesProbe

    init() { self.init(probe: PreferencesProbe()) }

    init(probe: PreferencesProbe) {
        self.probe = probe
    }

    var body: some Scene {
        WindowGroup { PreferencesReader(probe: probe) }
            .reduceMotion(true)
            .keyNotation(.spelledOut)
            .focusBreathing(false)
            .commands { CommandMenu("Note") {} }
    }
}

/// The same app with the preferences group replaced by nothing.
private struct ReplacingApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE") }
            .commands {
                CommandMenu("Note") {}
                CommandGroup(replacing: .accessibility) {}
            }
    }
}

/// An app that offers the display options itself, at the top of View.
private struct DisplayCommandsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE") }
            .commands { DisplayCommands() }
    }
}

/// Shows how the arrows move the focus, over two buttons on a row: Tab order
/// and geometry part on Down, which has nothing below.
private struct ArrowsPage: View {
    var body: some View {
        HStack {
            Button("LEFT") {}
            Button("RIGHT") {}
        }
    }
}

/// An app with a menu bar over ``ArrowsPage``.
private struct ArrowsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { ArrowsPage() }
            .commands { CommandMenu("Note") {} }
    }
}

/// An app that declares one menu of its own and leaves the scene's commands.
private struct PlainApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE") }
            .commands { CommandMenu("Note") {} }
    }
}

// MARK: - Tests

@MainActor
@Suite("The View menu's preferences", .serialized)
struct MenuBarViewPreferencesTests {
    private var now: Int64 = 0

    private mutating func frame(_ app: TestApp) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private mutating func launched<A: App>(_ app: A) -> TestApp {
        let headless = TestApp(app, width: 70, height: 20)
        frame(headless)
        frame(headless)
        return headless
    }

    /// The bar's titles, in order, from its row.
    private func titles(_ app: TestApp) -> [String] {
        app.screen.lines[0].split(separator: " ").map(String.init)
    }

    /// Opens View and, unless `choosing` is `nil`, chooses its item that many
    /// rows down; returns the rows the open menu showed.
    @discardableResult
    private mutating func view(choosing item: Int?, in app: TestApp) -> [String] {
        let rights = titles(app).firstIndex(of: "View") ?? 0
        for key: Key in [.f10] + Array(repeating: .right, count: rights) + [.down] {
            app.send(KeyEvent(key: key))
            frame(app)
        }
        let shown = app.screen.lines
        let keys: [Key] = item.map { Array(repeating: .down, count: $0) + [.enter] } ?? [.escape, .escape]
        for key in keys {
            app.send(KeyEvent(key: key))
            frame(app)
        }
        frame(app)
        return shown
    }

    @Test("Every menu bar's View menu offers the preferences, each checked while it is on")
    mutating func offered() {
        let probe = PreferencesProbe()
        let app = launched(PreferencesApp(probe: probe))
        #expect(titles(app).contains("View"), "\(app.screen.lines[0])")
        let menu = view(choosing: nil, in: app).joined(separator: "\n")
        let titles = [
            "Palette", "Border Style", "Control Style",
            "Breathing Focus", "Spell Out Keys", "Focus Follows Pointer", "Arrows Follow Layout",
            "Differentiate Without Color", "Reduce Motion", "Reduce Transparency", "Increase Contrast",
        ]
        // All of them, in the settings panel's order: its View tab's, then
        // its Accessibility tab's.
        let rows = titles.map { title in menu.split(separator: "\n").firstIndex { $0.contains(title) } }
        #expect(!rows.contains(nil), "\(menu)")
        #expect(rows.compactMap { $0 } == rows.compactMap { $0 }.sorted(), "in order: \(menu)")
        // The app's own `.reduceMotion(true)` and `.keyNotation(.spelledOut)`
        // show checked, its `.focusBreathing(false)` not, the rest not.
        let checked = menu.split(separator: "\n").filter { $0.contains("■") }
        #expect(checked.contains { $0.contains("Reduce Motion") }, "\(menu)")
        #expect(checked.contains { $0.contains("Spell Out Keys") }, "\(menu)")
        #expect(!checked.contains { $0.contains("Breathing Focus") }, "\(menu)")
        #expect(!checked.contains { $0.contains("Increase Contrast") }, "\(menu)")
    }

    @Test("Choosing one changes the value every view reads, over the app's own modifier, and back")
    mutating func choosing() {
        let probe = PreferencesProbe()
        let app = launched(PreferencesApp(probe: probe))
        #expect(app.screen.contains("MOTION REDUCED"))
        // Palette, Border Style, Control Style; then Breathing Focus, Spell
        // Out Keys, Focus Follows Pointer, Arrows Follow Layout; then
        // Differentiate Without Color, Reduce Motion, …
        view(choosing: Self.reduceMotionRow, in: app)
        #expect(app.screen.contains("MOTION FULL"), "\(app.screen)")
        #expect(probe.reduceMotion == false)
        view(choosing: Self.reduceMotionRow, in: app)
        #expect(app.screen.contains("MOTION REDUCED"), "\(app.screen)")

        view(choosing: 3, in: app)  // Breathing Focus, which the app held still
        #expect(probe.breathes == true)
        view(choosing: 4, in: app)  // Spell Out Keys, which the app asked for
        #expect(probe.notation == .symbols)
        view(choosing: Self.reduceMotionRow - 1, in: app)  // Differentiate Without Color
        #expect(probe.differentiateWithoutColor == true)
    }

    @Test("A choice wins over the user's variable and the host's setting, either way")
    func overVariableAndHost() {
        let probe = PreferencesProbe()
        // As `TUI_DIFFERENTIATE_WITHOUT_COLOR=1` and `TUI_INCREASE_CONTRAST=0`
        // reach the loop, with Reduce Motion on in the host's settings.
        let loop = RenderLoopHarness().loop(
            PreferencesApp(probe: probe), accessibility: [.differentiateWithoutColor],
            declinedAccessibility: [.increaseContrast])
        loop.hostAccessibility = [.reduceMotion, .increaseContrast]
        loop.render()
        #expect(probe.differentiateWithoutColor == true && probe.contrast == .standard)

        loop.viewPreferenceOverrides[.differentiateWithoutColor] = false
        loop.viewPreferenceOverrides[.increaseContrast] = true
        loop.viewPreferenceOverrides[.reduceMotion] = false
        loop.render()
        #expect(probe.differentiateWithoutColor == false)
        #expect(probe.contrast == .increased)
        #expect(probe.reduceMotion == false, "over the host's setting and the app's own .reduceMotion(true)")
    }

    @Test("A choice lasts the run and no longer: the next run starts from the settings")
    mutating func notKept() {
        let probe = PreferencesProbe()
        let app = launched(PreferencesApp(probe: probe))
        view(choosing: Self.reduceMotionRow, in: app)
        #expect(probe.reduceMotion == false)

        // Another run of the same app in the same process: nothing the first
        // chose was written anywhere this one reads.
        let again = PreferencesProbe()
        let rerun = launched(PreferencesApp(probe: again))
        #expect(again.reduceMotion == true, "\(rerun.screen)")
        #expect(rerun.screen.contains("MOTION REDUCED"))
    }

    /// Reduce Motion's row in View: after the three submenus, the View tab's
    /// four checks and Differentiate Without Color.
    private static let reduceMotionRow = 8

    @Test("Arrows Follow Layout is off by default, and turns the geometric arrows on and off for the run")
    mutating func arrowsFollowLayout() {
        let app = launched(ArrowsApp())
        #expect(app.arrowFocus == .tabOrder, "the experiment stays off unless asked for")
        if app.focusedID == nil {
            app.send(KeyEvent(key: .tab))
            frame(app)
        }
        #expect(app.focusedID != nil)
        let rows = view(choosing: nil, in: app)
        #expect(rows.contains { $0.contains("Arrows Follow Layout") && !$0.contains("■") }, "\(rows)")
        view(choosing: 6, in: app)
        #expect(app.arrowFocus == .geometric)
        #expect(view(choosing: nil, in: app).contains { $0.contains("Arrows Follow Layout") && $0.contains("■") })
        // Up and Down, with nothing above or below either button, leave the
        // focus where it is; in Tab order one of them goes to the other.
        #expect(Set(arrowStops(in: app)).count == 1, "geometric: nothing lies above or below")
        view(choosing: 6, in: app)
        #expect(app.arrowFocus == .tabOrder)
        #expect(Set(arrowStops(in: app)).count == 2, "Tab order: on to the other button")
    }

    /// Where the focus is before and after Up, then Down.
    private mutating func arrowStops(in app: TestApp) -> [String?] {
        var stops = [app.focusedID]
        for key: Key in [.up, .down] {
            app.send(KeyEvent(key: key))
            frame(app)
            stops.append(app.focusedID)
        }
        return stops
    }

    @Test("DisplayCommands takes the display options' place: they are listed once, at the top")
    mutating func displayCommandsOnce() {
        let own = view(choosing: nil, in: launched(PlainApp()))
        #expect(own.filter { $0.contains("Palette") }.count == 1, "\(own.joined(separator: "\n"))")
        let app = launched(DisplayCommandsApp())
        let rows = view(choosing: nil, in: app)
        let palette = rows.firstIndex { $0.contains("Palette") }
        let breathing = rows.firstIndex { $0.contains("Breathing Focus") }
        #expect(rows.filter { $0.contains("Palette") }.count == 1, "\(rows.joined(separator: "\n"))")
        #expect(palette != nil && breathing != nil && palette! < breathing!, "\(rows.joined(separator: "\n"))")
    }

    @Test("CommandGroup(replacing: .accessibility) takes them away")
    mutating func replaced() {
        let plain = launched(PlainApp())
        #expect(view(choosing: nil, in: plain).contains { $0.contains("Reduce Motion") })
        let app = launched(ReplacingApp())
        let menu = titles(app).contains("View") ? view(choosing: nil, in: app) : []
        #expect(!menu.contains { $0.contains("Reduce Motion") }, "\(menu)")
        #expect(!app.screen.contains("Reduce Motion"))
    }
}
