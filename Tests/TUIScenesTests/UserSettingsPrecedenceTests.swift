//  🖥️ TUI — A Terminal UI framework for Swift
//  UserSettingsPrecedenceTests.swift
//
//  The seven layers that decide each of TUI's settings (the owner's
//  USET-ORDER, 2026-11-10), highest first: this run's choice; the `TUI_*`
//  variable; the program's code; the person's settings for this program; for
//  all programs; the computer's setting; TUI's default. And the older
//  relations kept: code adds an aid even under the variable's `0`, and
//  `Scene.focusFollowsPointer(_:)` wins over its variable. A table of cases,
//  each run in an app with every layer it names set.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

// MARK: - Fixtures

/// What the page read of each preference.
@MainActor
private final class LayersProbe {
    var values: [ViewPreference: Bool] = [:]
    var palette: String?
}

/// Reads every preference.
private struct LayersReader: View {
    let probe: LayersProbe
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.focusBreathes) private var breathes
    @Environment(\.keyNotation) private var notation
    @Environment(\.focusFollowsPointer) private var followsPointer
    @Environment(\.arrowFocus) private var arrowFocus
    @Environment(\.palette) private var palette

    var body: some View {
        probe.values = [
            .reduceMotion: reduceMotion, .reduceTransparency: reduceTransparency,
            .differentiateWithoutColor: differentiateWithoutColor, .increaseContrast: contrast == .increased,
            .focusBreathing: breathes, .spelledOutKeys: notation == .spelledOut,
            .focusFollowsPointer: followsPointer ?? false, .arrowsFollowLayout: arrowFocus == .geometric,
        ]
        probe.palette = palette.id
        return Text(verbatim: "PAGE")
    }
}

/// What the program's code states: the one-way aids, which a `false` leaves
/// as they are.
private struct CodeStatements {
    var reducesMotion = false
    var holdsBreath = false
    var spellsKeys = false
}

/// An app stating `code` at its scene.
private struct LayersApp: App {
    let probe: LayersProbe
    let code: CodeStatements

    init() { self.init(probe: LayersProbe(), code: CodeStatements()) }

    init(probe: LayersProbe, code: CodeStatements) {
        self.probe = probe
        self.code = code
    }

    var body: some Scene {
        WindowGroup { LayersReader(probe: probe) }
            .reduceMotion(code.reducesMotion)
            .focusBreathing(!code.holdsBreath)
            .keyNotation(code.spellsKeys ? .spelledOut : .symbols)
    }
}

/// An app whose scene says whether the focus follows the pointer.
private struct FollowingApp: App {
    let probe: LayersProbe
    let follows: Bool

    init() { self.init(probe: LayersProbe(), follows: true) }

    init(probe: LayersProbe, follows: Bool) {
        self.probe = probe
        self.follows = follows
    }

    var body: some Scene {
        WindowGroup { LayersReader(probe: probe) }
            .focusFollowsPointer(follows)
    }
}

/// An app whose scene states its own palette.
private struct OwnPaletteApp: App {
    let probe: LayersProbe

    init() { self.init(probe: LayersProbe()) }

    init(probe: LayersProbe) {
        self.probe = probe
    }

    var body: some Scene {
        WindowGroup { LayersReader(probe: probe) }
            .palette(SystemPalette(.violet))
    }
}

/// Every layer one case sets, `nil` where it sets none.
private struct Layers {
    var run: Bool?
    var variable: Bool?
    var code = CodeStatements()
    var program: Bool?
    var allPrograms: Bool?
    var system = false
}

// MARK: - Tests

@MainActor
@Suite("Which of TUI's settings wins", .serialized)
struct UserSettingsPrecedenceTests {
    private var now: Int64 = 0

    private mutating func frame(_ app: TestApp) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private func scratchFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tui-layers-\(UUID().uuidString)", isDirectory: true)
    }

    /// `app` with every layer `layers` names set for `preference`, as a
    /// running app reads them, drawn.
    private mutating func run<A: App>(_ app: A, _ preference: ViewPreference, _ layers: Layers) -> TestApp {
        let folder = scratchFolder()
        let store = JSONFileStorage(fileURL: folder.appendingPathComponent("settings.json"))
        if let program = layers.program {
            store.setValue(program, forKey: UserSetting.preference(preference).programStoreKey)
        }
        let file = AllProgramsSettingsFile(url: folder.appendingPathComponent("TUI/defaults.json"))
        if let all = layers.allPrograms { file.write(.bool(all), for: .preference(preference)) }
        let test = TestApp(app, width: 40, height: 6)
        test.headless.keepSettings(programStore: store, allProgramsFile: file)
        if let variable = layers.variable { test.headless.statedByVariables = [preference: variable] }
        if layers.system, let accessibility = preference.accessibility {
            test.headless.hostAccessibility = accessibility
        }
        frame(test)
        if let run = layers.run {
            test.headless.viewPreferenceOverrides[preference] = run
            frame(test)
        }
        return test
    }

    /// The table: each preference through the layers, one more set in each
    /// row, so each row's answer is the new layer's.
    private static let cases: [(ViewPreference, Layers, expected: Bool)] = [
        // Reduce Motion: every layer, and code adding the aid under `0`.
        (.reduceMotion, Layers(), false),
        (.reduceMotion, Layers(system: true), true),
        (.reduceMotion, Layers(allPrograms: false, system: true), false),
        (.reduceMotion, Layers(program: true, allPrograms: false, system: true), true),
        (.reduceMotion, Layers(code: CodeStatements(reducesMotion: true), program: false, allPrograms: false), true),
        (.reduceMotion, Layers(variable: false, program: true, allPrograms: true, system: true), false),
        (.reduceMotion, Layers(variable: false, code: CodeStatements(reducesMotion: true)), true),
        (.reduceMotion, Layers(run: false, variable: true, code: CodeStatements(reducesMotion: true)), false),
        // The three no code states.
        (.increaseContrast, Layers(system: true), true),
        (.increaseContrast, Layers(allPrograms: false, system: true), false),
        (.increaseContrast, Layers(program: true, allPrograms: false), true),
        (.increaseContrast, Layers(variable: false, program: true), false),
        (.increaseContrast, Layers(run: true, variable: false), true),
        (.differentiateWithoutColor, Layers(allPrograms: true), true),
        (.differentiateWithoutColor, Layers(variable: false, allPrograms: true, system: true), false),
        (.reduceTransparency, Layers(program: true), true),
        (.reduceTransparency, Layers(run: false, program: true, system: true), false),
        // Breathing Focus: on by default, code holding it still.
        (.focusBreathing, Layers(), true),
        (.focusBreathing, Layers(allPrograms: false), false),
        (.focusBreathing, Layers(program: true, allPrograms: false), true),
        (.focusBreathing, Layers(code: CodeStatements(holdsBreath: true), program: true), false),
        (.focusBreathing, Layers(variable: false, program: true), false),
        (.focusBreathing, Layers(run: true, variable: false, code: CodeStatements(holdsBreath: true)), true),
        // Spell Out Keys: code asking for the names.
        (.spelledOutKeys, Layers(allPrograms: true), true),
        (.spelledOutKeys, Layers(program: false, allPrograms: true), false),
        (.spelledOutKeys, Layers(code: CodeStatements(spellsKeys: true), program: false), true),
        (.spelledOutKeys, Layers(variable: true, program: false), true),
        (.spelledOutKeys, Layers(run: false, code: CodeStatements(spellsKeys: true)), false),
        // Arrows Follow Layout: no code, no computer setting.
        (.arrowsFollowLayout, Layers(), false),
        (.arrowsFollowLayout, Layers(allPrograms: true), true),
        (.arrowsFollowLayout, Layers(program: false, allPrograms: true), false),
        (.arrowsFollowLayout, Layers(variable: true, program: false), true),
        (.arrowsFollowLayout, Layers(run: false, variable: true), false),
        // Focus Follows Pointer, where the scene says nothing.
        (.focusFollowsPointer, Layers(), false),
        (.focusFollowsPointer, Layers(allPrograms: true), true),
        (.focusFollowsPointer, Layers(program: false, allPrograms: true), false),
        (.focusFollowsPointer, Layers(variable: true, program: false), true),
        (.focusFollowsPointer, Layers(run: false, variable: true), false),
    ]

    @Test("Each layer wins over those beneath it, and code only ever adds an aid")
    mutating func matrix() {
        for (index, (preference, layers, expected)) in Self.cases.enumerated() {
            let probe = LayersProbe()
            let app = run(LayersApp(probe: probe, code: layers.code), preference, layers)
            #expect(probe.values[preference] == expected, "case \(index): \(preference) with \(layers)")
            withExtendedLifetime(app) {}
        }
    }

    @Test("The scene's Focus Follows Pointer wins over its variable and over both saved levels, as before")
    mutating func focusFollowsPointerCode() {
        let cases: [(follows: Bool, Layers, expected: Bool)] = [
            (false, Layers(program: true, allPrograms: true), false),
            (true, Layers(program: false), true),
            (false, Layers(variable: true), false),
            (false, Layers(run: true, variable: true), true),
        ]
        for (index, (follows, layers, expected)) in cases.enumerated() {
            let probe = LayersProbe()
            let app = run(FollowingApp(probe: probe, follows: follows), .focusFollowsPointer, layers)
            #expect(probe.values[.focusFollowsPointer] == expected, "case \(index)")
            withExtendedLifetime(app) {}
        }
    }

    @Test("A palette: this run's, else this program's, else all programs', else TUI's; the scene's own over all")
    mutating func palette() throws {
        let folder = scratchFolder()
        let file = AllProgramsSettingsFile(url: folder.appendingPathComponent("TUI/defaults.json"))
        let store = JSONFileStorage(fileURL: folder.appendingPathComponent("settings.json"))
        let probe = LayersProbe()
        let app = TestApp(LayersApp(probe: probe, code: CodeStatements()), width: 40, height: 6)
        app.headless.keepSettings(programStore: store, allProgramsFile: file)
        frame(app)
        #expect(probe.palette == DisplayOption.palette.defaultIdentifier)

        let overrides = app.headless.viewPreferenceOverrides
        overrides.setForAllPrograms(.display(.palette), .identifier("amber"))
        frame(app)
        #expect(probe.palette == "amber")
        store.setValue("red", forKey: UserSetting.display(.palette).programStoreKey)
        app.headless.keepSettings(programStore: store, allProgramsFile: file)
        frame(app)
        #expect(probe.palette == "red", "this program's, over all programs'")
        overrides.choose(.display(.palette), .identifier("blue"))
        frame(app)
        #expect(probe.palette == "blue")
        overrides.giveBack(.display(.palette))
        frame(app)
        #expect(probe.palette == "amber", "given back, all programs' again")

        let stated = LayersProbe()
        let own = TestApp(OwnPaletteApp(probe: stated), width: 40, height: 6)
        own.headless.keepSettings(programStore: store, allProgramsFile: file)
        own.headless.viewPreferenceOverrides.choose(.display(.palette), .identifier("blue"))
        frame(own)
        #expect(stated.palette == "violet", "the scene's own palette decides it")
    }

    @Test("A choice this run is saved for the program, and the next run reads it beneath the variable")
    mutating func savedForTheNextRun() {
        let folder = scratchFolder()
        let store = JSONFileStorage(fileURL: folder.appendingPathComponent("settings.json"))
        let first = TestApp(LayersApp(), width: 40, height: 6)
        first.headless.keepSettings(programStore: store, allProgramsFile: nil)
        first.headless.viewPreferenceOverrides[.reduceMotion] = true
        #expect(store.value(forKey: "TUISettings.reduceMotion") == true)

        let probe = LayersProbe()
        let next = TestApp(LayersApp(probe: probe, code: CodeStatements()), width: 40, height: 6)
        next.headless.keepSettings(programStore: store, allProgramsFile: nil)
        frame(next)
        #expect(probe.values[.reduceMotion] == true, "the next run starts from it")
        #expect(next.headless.viewPreferenceOverrides[.reduceMotion] == nil, "as the program's, not this run's")

        let underVariable = LayersProbe()
        let launch = TestApp(LayersApp(probe: underVariable, code: CodeStatements()), width: 40, height: 6)
        launch.headless.keepSettings(programStore: store, allProgramsFile: nil)
        launch.headless.statedByVariables = [.reduceMotion: false]
        frame(launch)
        #expect(underVariable.values[.reduceMotion] == false, "TUI_REDUCE_MOTION=0 still means this once")
    }
}
