//  🖥️ TUI — A Terminal UI framework for Swift
//  SettingsAllProgramsTests.swift
//
//  The settings panel's two levels (the owner's USET-EDIT, 2026-11-10): each
//  of TUI's settings with a box saying whether the level sets it, this
//  program's as the panel opens and the person's for all programs after
//  Settings for All Programs…, back with Done; a change ticks the box,
//  unticking gives the setting back. Driven by the keyboard alone, with the
//  person's file a temporary one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUIScenes
import TUITesting

// MARK: - Fixtures

/// What the page read.
@MainActor
private final class Probe {
    var reduceMotion = false
    var breathes = true
}

/// Reads Reduce Motion and Breathing Focus.
private struct ProbePage: View {
    let probe: Probe
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.focusBreathes) private var breathes

    var body: some View {
        probe.reduceMotion = reduceMotion
        probe.breathes = breathes
        return Text(verbatim: "PAGE")
    }
}

/// An app with no `Settings` scene: TUI's two tabs alone.
private struct PlainApp: App {
    let probe: Probe

    init() { self.init(probe: Probe()) }

    init(probe: Probe) {
        self.probe = probe
    }

    var body: some Scene {
        WindowGroup { ProbePage(probe: probe) }
    }
}

// MARK: - Tests

@MainActor
@Suite("The settings panel's two levels, by keyboard", .serialized)
struct SettingsAllProgramsTests {
    private var now: Int64 = 0

    private mutating func press(_ key: Key, shift: Bool = false, in app: TestApp) {
        app.send(KeyEvent(key: key, shift: shift))
        frame(app)
    }

    private mutating func frame(_ app: TestApp) {
        now += 20_000_000
        app.frame(atNanos: now)
        now += 20_000_000
        app.frame(atNanos: now)
    }

    /// Presses Tab until the control `id` has the focus.
    private mutating func tab(to id: String, in app: TestApp) throws {
        for _ in 0..<40 where app.focusedID != id { press(.tab, in: app) }
        try #require(app.focusedID == id, "\(id): \(app.screen.lines.joined(separator: "\n"))")
    }

    private func screen(_ app: TestApp) -> String {
        app.screen.lines.joined(separator: "\n")
    }

    /// The styling `label` is drawn with: the escape sequences just before it
    /// on its row.
    private func styling(of label: String, in app: TestApp) -> Substring? {
        guard let line = app.screen.styledLines.first(where: { $0.contains(label) }),
            let at = line.range(of: label)
        else { return nil }
        let before = line[..<at.lowerBound]
        guard let escape = before.range(of: "\u{1B}[", options: .backwards) else { return nil }
        return before[escape.lowerBound...]
    }

    @Test("For this program: a change ticks the box and is kept; unticking gives it back")
    mutating func thisProgram() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tui-panel-\(UUID().uuidString)")
        let store = JSONFileStorage(fileURL: folder.appendingPathComponent("settings.json"))
        let probe = Probe()
        let app = TestApp(PlainApp(probe: probe), width: 80, height: 30)
        app.headless.keepSettings(
            programStore: store, allProgramsFile: AllProgramsSettingsFile(url: folder.appendingPathComponent("TUI/defaults.json")))
        let overrides = app.headless.viewPreferenceOverrides
        frame(app)
        press(.f2, in: app)
        #expect(screen(app).contains("A ticked box keeps the setting for this program."), "\(screen(app))")

        try tab(to: "tui.settings.focusBreathing", in: app)
        press(.space, in: app)
        #expect(!probe.breathes)
        #expect(overrides.isSetForProgram(.preference(.focusBreathing)), "a change ticks its box")
        #expect(store.value(forKey: "TUISettings.focusBreathing") == false, "and is kept for the program")

        press(.tab, shift: true, in: app)
        #expect(app.focusedID == "tui.settings.setHere.focusBreathing", "the box is just before the value")
        press(.space, in: app)
        #expect(probe.breathes, "given back: TUI's default again")
        #expect(!overrides.isSetForProgram(.preference(.focusBreathing)))
        #expect(store.value(forKey: "TUISettings.focusBreathing") as Bool? == nil)

        press(.space, in: app)
        #expect(overrides.isSetForProgram(.preference(.focusBreathing)), "ticking keeps the value shown")
        #expect(store.value(forKey: "TUISettings.focusBreathing") == true)
        #expect(probe.breathes)
    }

    @Test("Settings for All Programs… shows them with their boxes; a change ticks, unticking gives back, Done returns")
    mutating func allPrograms() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tui-panel-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("TUI/defaults.json")
        let file = AllProgramsSettingsFile(url: url)
        let probe = Probe()
        let app = TestApp(PlainApp(probe: probe), width: 80, height: 30)
        app.headless.keepSettings(programStore: nil, allProgramsFile: file)
        let overrides = app.headless.viewPreferenceOverrides
        frame(app)
        press(.f2, in: app)
        try tab(to: "tui.settings.allPrograms", in: app)
        press(.space, in: app)
        let text = screen(app)
        #expect(text.contains("Settings for All Programs"), "the title says which: \(text)")
        #expect(text.contains("A ticked box sets it for every program."), "\(text)")
        #expect(!text.contains("Settings for All Programs…"), "no way further in: \(text)")

        try tab(to: "tui.settings.focusBreathing", in: app)
        press(.space, in: app)
        #expect(file.read().isOn(.focusBreathing) == false, "written to the person's file")
        #expect(overrides.allPrograms.isOn(.focusBreathing) == false)
        #expect(!probe.breathes, "and this program, which sets nothing of its own, follows it")

        press(.tab, shift: true, in: app)
        #expect(app.focusedID == "tui.settings.setHere.focusBreathing")
        let setHere = styling(of: "Breathing Focus", in: app)
        press(.space, in: app)
        #expect(file.read().isOn(.focusBreathing) == nil, "given back: the key leaves the file")
        #expect(probe.breathes)
        let inherited = styling(of: "Breathing Focus", in: app)
        #expect(setHere != nil && inherited != setHere, "an inherited value is drawn fainter")
        press(.space, in: app)
        #expect(file.read().isOn(.focusBreathing) == true, "ticked again: the value inherited, now set here")

        press(.escape, in: app)
        #expect(app.scenes.isPresentingSettings, "Done leaves the settings for all programs, not the panel")
        #expect(screen(app).contains("A ticked box keeps the setting for this program."), "\(screen(app))")
        #expect(!overrides.isSetForProgram(.preference(.focusBreathing)), "this program keeps nothing of it")
        press(.escape, in: app)
        #expect(!app.scenes.isPresentingSettings)
    }
}
