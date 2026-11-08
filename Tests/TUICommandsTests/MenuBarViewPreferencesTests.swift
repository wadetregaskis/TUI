//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBarViewPreferencesTests.swift
//
//  The View menu's accessibility and display preferences, in every menu bar:
//  each a check showing whether it is on, which the person turns on or off
//  for the rest of the run, over the host's setting, the `TUI_*` variable
//  and the app's own scene modifiers, and never saved.
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
        for title in [
            "Differentiate Without Color", "Reduce Motion", "Reduce Transparency", "Increase Contrast",
            "Breathing Focus", "Spell Out Keys", "Focus Follows Pointer",
        ] {
            #expect(menu.contains(title), "\(title) in \(menu)")
        }
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
        view(choosing: 1, in: app)  // Reduce Motion, under Differentiate Without Color
        #expect(app.screen.contains("MOTION FULL"), "\(app.screen)")
        #expect(probe.reduceMotion == false)
        view(choosing: 1, in: app)
        #expect(app.screen.contains("MOTION REDUCED"), "\(app.screen)")

        view(choosing: 4, in: app)  // Breathing Focus, which the app held still
        #expect(probe.breathes == true)
        view(choosing: 5, in: app)  // Spell Out Keys, which the app asked for
        #expect(probe.notation == .symbols)
        view(choosing: 0, in: app)  // Differentiate Without Color
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
        view(choosing: 1, in: app)
        #expect(probe.reduceMotion == false)

        // Another run of the same app in the same process: nothing the first
        // chose was written anywhere this one reads.
        let again = PreferencesProbe()
        let rerun = launched(PreferencesApp(probe: again))
        #expect(again.reduceMotion == true, "\(rerun.screen)")
        #expect(rerun.screen.contains("MOTION REDUCED"))
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
