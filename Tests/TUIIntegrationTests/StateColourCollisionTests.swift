//  🖥️ TUI — A Terminal UI framework for Swift
//  StateColourCollisionTests.swift
//
//  A focused control and a disabled one look unlike the same control at rest, in
//  every palette, at every depth: where a state's colour rounds to the resting
//  colour at the terminal's depth, the control falls back to the cue it draws
//  without colour (owner, 2026-11-10, THEME-16 (b)).
//
//  The whole sweep (34 controls through the 16 shipped palettes at four depths,
//  about five minutes) runs with `TUI_COLLISION_SWEEP=1`, and prints what it finds
//  with `TUI_COLLISION_REPORT=1`; it measured the ruling's before and after. Every
//  run checks the cases it found, at 16 colours, where the states collided.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUI
@testable import TUICore
@testable import TUIStyling
import TUITesting
@testable import TUITestSupport

/// A row of a table.
private struct CollisionRow: Identifiable {
    let id: Int
    let name: String
}

/// A control that takes the focus, drawn focused, at rest, and disabled.
enum CollisionProbe: String, CaseIterable, CustomStringConvertible {
    case button, buttonViewLabel, bordered, borderedProminent, plainButton, link, inlineLink
    case checkboxOff, checkboxOn, switchOff, switchOn, toggleButton
    case radioGroup, slider, stepper, textField, menuPicker, segmentedPicker
    case list, table, datePicker
    case borderless, borderlessViewLabel, borderedViewLabel, prominentViewLabel
    case secureField, textEditor, menu, disclosureGroup, tabView, colorPicker

    var description: String { rawValue }

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .button: Button("Go") {}
        case .buttonViewLabel: Button {} label: { Text("Go") }
        case .bordered: Button("Go") {}.buttonStyle(.bordered)
        case .borderedProminent: Button("Go") {}.buttonStyle(.borderedProminent)
        case .plainButton: Button("Go") {}.buttonStyle(.plain)
        case .link: Link("Go", destination: URL(string: "https://example.com")!)
        case .inlineLink: Text("Read [the guide](https://example.com) first.")
        case .checkboxOff: Toggle("Go", isOn: .constant(false))
        case .checkboxOn: Toggle("Go", isOn: .constant(true))
        case .switchOff: Toggle("Go", isOn: .constant(false)).toggleStyle(.switch)
        case .switchOn: Toggle("Go", isOn: .constant(true)).toggleStyle(.switch)
        case .toggleButton: Toggle("Go", isOn: .constant(true)).toggleStyle(.button)
        case .radioGroup:
            Picker("Go", selection: .constant(1)) {
                Text("One").tag(1)
                Text("Two").tag(2)
            }
            .pickerStyle(.radioGroup)
        case .slider: Slider(value: .constant(0.5), in: 0...1)
        case .stepper: Stepper("Go", value: .constant(1), in: 0...5)
        case .textField: TextField("Name", text: .constant("Go"))
        case .menuPicker:
            Picker("Go", selection: .constant(1)) {
                Text("One").tag(1)
                Text("Two").tag(2)
            }
            .pickerStyle(.menu)
        case .segmentedPicker:
            Picker("Go", selection: .constant(1)) {
                Text("One").tag(1)
                Text("Two").tag(2)
            }
            .pickerStyle(.segmented)
        case .list:
            List(selection: .constant(Set([1]))) {
                Text("One").tag(1)
                Text("Two").tag(2)
            }
            .frame(height: 4)
        case .table:
            Table([CollisionRow(id: 1, name: "One"), CollisionRow(id: 2, name: "Two")]) {
                TableColumn("Name", value: \CollisionRow.name)
            }
            .frame(height: 5)
        case .datePicker:
            DatePicker(
                "Go", selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date)
        case .borderless: Button("Go") {}.buttonStyle(.borderless)
        case .borderlessViewLabel: Button {} label: { Text("Go") }.buttonStyle(.borderless)
        case .borderedViewLabel: Button {} label: { Text("Go") }.buttonStyle(.bordered)
        case .prominentViewLabel: Button {} label: { Text("Go") }.buttonStyle(.borderedProminent)
        case .secureField: SecureField("Name", text: .constant("Go"))
        case .textEditor: TextEditor(text: .constant("Go")).frame(height: 2)
        case .menu:
            Menu("Go") {
                Button("One") {}
            }
        case .disclosureGroup:
            DisclosureGroup("Go") { Text("One") }
        case .tabView:
            TabView(selection: .constant(0)) {
                Tab("One", value: 0) { Text("One") }
                Tab("Two", value: 1) { Text("Two") }
            }
            .frame(height: 4)
        case .colorPicker: ColorPicker("Go", selection: .constant(Color.rgb(200, 40, 40)))
        }
    }
}

/// A screen as the cells it shows: what each column draws and in what, as far as it
/// can be seen, so two spellings of one picture compare equal.
private func shown(_ lines: [String]) -> [[String]] {
    lines.map { line in paintedCells(line).map { "\($0.glyph)|\($0.visibleState)" } }
}

@MainActor
@Suite("A state's colour that rounds to the resting colour falls back to the colour-free cue")
struct StateColourCollisionTests {
    nonisolated static let depths: [ColorDepth] = [.basic16, .palette256, .truecolor, .noColor]

    /// Controls whose disabled look is the enabled one at every depth, whatever the
    /// palette: not a colour that rounds, so not this suite's to measure.
    static let disabledAtEveryDepth: Set<CollisionProbe> = [.tabView, .colorPicker]

    /// What the sweep found at 16 colours before the ruling: the focus drawn as rest.
    nonisolated static let focusFound: [(String, CollisionProbe)] =
        [CollisionProbe.tabView, .slider, .stepper, .buttonViewLabel, .borderedProminent, .toggleButton,
         .borderedViewLabel, .prominentViewLabel, .menu].map { ("Silver Aerogel", $0) }
        + [("Man Page", .slider), ("Man Page", .stepper), ("Amber", .tabView), ("Blue", .tabView), ("Pro", .tabView),
           ("Solid Colors", .textField), ("Solid Colors", .secureField)]

    /// What it found at 16 colours: disabled drawn as enabled.
    nonisolated static let disabledFound: [(String, CollisionProbe)] =
        ["Red", "Violet", "White", "Basic", "Novel", "Ocean"].flatMap { palette in
            [CollisionProbe.button, .bordered, .borderedViewLabel, .menu].map { (palette, $0) }
        }
        + ["Violet", "Blue"].flatMap { palette in
            [CollisionProbe.textField, .secureField, .textEditor].map { (palette, $0) }
        }
        + [("White", .disclosureGroup), ("Novel", .disclosureGroup), ("Red Sands", .disclosureGroup),
           ("White", .borderlessViewLabel), ("Man Page", .link), ("Silver Aerogel", .link),
           ("Man Page", .borderless), ("Silver Aerogel", .borderless), ("Man Page", .toggleButton),
           ("Ocean", .toggleButton), ("Man Page", .prominentViewLabel), ("Red Sands", .slider)]

    /// The shipped palette called `name`.
    private static func palette(named name: String) -> any Palette {
        (PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles).first { $0.name == name }!
    }

    /// The probe's rows focused (at the breath's dim end, where `TestApp` draws it, and
    /// held still at its bright end) and at rest, with the focus on a button below.
    private func focusRows(
        _ probe: CollisionProbe, _ palette: any Palette
    ) -> (dim: [[String]], still: [[String]], resting: [[String]])? {
        func drawn(still: Bool) -> (focused: [[String]], resting: [[String]])? {
            let app = TestApp(width: 50, height: 12) {
                VStack(alignment: .leading) {
                    probe.view
                    Spacer()
                    Button("Anchor") {}.focusID("anchor")
                }
                .palette(palette)
                .selectionIndicatorStyle(still ? .none : .pulse)
                // A text input's focus is its caret, which keeps its own clock.
                .textCursor(.block, animation: still ? .none : .pulse)
            }
            guard app.focusedID != nil, app.focusedID != "anchor" else { return nil }
            let focused = app.screen.styledLines
            var presses = 0
            while app.focusedID != "anchor", presses < 4 {
                app.press(.tab)
                presses += 1
            }
            guard app.focusedID == "anchor" else { return nil }
            let resting = app.screen.styledLines
            let rows = focused.count - 1
            return (shown(Array(focused.prefix(rows))), shown(Array(resting.prefix(rows))))
        }
        guard let breathing = drawn(still: false), let held = drawn(still: true) else { return nil }
        return (breathing.focused, held.focused, breathing.resting)
    }

    /// The probe's rows disabled and enabled, below a button that holds the focus.
    private func disabledRows(_ probe: CollisionProbe, _ palette: any Palette) -> (disabled: [[String]], enabled: [[String]]) {
        func drawn(_ disabled: Bool) -> [[String]] {
            let app = TestApp(width: 50, height: 12) {
                VStack(alignment: .leading) {
                    Button("Anchor") {}.focusID("anchor")
                    probe.view.disabled(disabled)
                }
                .palette(palette)
            }
            return shown(Array(app.screen.styledLines.dropFirst()))
        }
        return (drawn(true), drawn(false))
    }

    /// Every (probe, palette, depth) whose focus, breathing, draws exactly as its rest
    /// at both ends of the breath, or whose still focus does; and whose disabled look
    /// draws exactly as its enabled one.
    private func collisions(at depth: ColorDepth) -> (focus: [String], still: [String], disabled: [String]) {
        var focus: [String] = []
        var still: [String] = []
        var disabled: [String] = []
        ColorDepth.withCurrent(depth) {
            for palette in PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles {
                for probe in CollisionProbe.allCases {
                    if let rows = focusRows(probe, palette) {
                        if rows.dim == rows.resting && rows.still == rows.resting {
                            focus.append("\(palette.name)/\(probe)")
                        }
                        if rows.still == rows.resting { still.append("\(palette.name)/\(probe)") }
                    }
                    // A link in a `Text` is no control while disabled, and is drawn as text.
                    guard probe != .inlineLink, !Self.disabledAtEveryDepth.contains(probe) else { continue }
                    let drawn = disabledRows(probe, palette)
                    if drawn.disabled == drawn.enabled { disabled.append("\(palette.name)/\(probe)") }
                }
            }
        }
        return (focus, still, disabled)
    }

    @Test(
        "A focus whose colour rounds to rest at 16 colours shows, breathing and held still",
        arguments: focusFound)
    func focusShows(_ palette: String, _ probe: CollisionProbe) throws {
        let rows = try #require(
            ColorDepth.withCurrent(.basic16) { focusRows(probe, Self.palette(named: palette)) },
            "the premise: \(probe) takes the focus")
        #expect(rows.dim != rows.resting || rows.still != rows.resting, "\(probe) in \(palette): the focus is not drawn")
        #expect(rows.still != rows.resting, "\(probe) in \(palette): a still focus is not drawn")
    }

    @Test("A grey that rounds to the enabled colour at 16 colours is drawn faint", arguments: disabledFound)
    func disabledShows(_ palette: String, _ probe: CollisionProbe) {
        let drawn = ColorDepth.withCurrent(.basic16) { disabledRows(probe, Self.palette(named: palette)) }
        #expect(drawn.disabled != drawn.enabled, "\(probe) in \(palette): disabled looks enabled")
    }

    @Test(
        "A focused or disabled control looks unlike the same control at rest, every control, palette and depth",
        .enabled(if: ProcessInfo.processInfo.environment["TUI_COLLISION_SWEEP"] != nil), arguments: depths)
    func statesShow(_ depth: ColorDepth) {
        let found = collisions(at: depth)
        if ProcessInfo.processInfo.environment["TUI_COLLISION_REPORT"] != nil {
            print("COLLISIONS \(depth): focus \(found.focus.count) still \(found.still.count) disabled \(found.disabled.count)")
            for entry in found.focus { print("  focus \(depth) \(entry)") }
            for entry in found.still { print("  still \(depth) \(entry)") }
            for entry in found.disabled { print("  disabled \(depth) \(entry)") }
        }
        #expect(found.focus.isEmpty, "\(depth): the focus is not drawn on \(found.focus)")
        #expect(found.still.isEmpty, "\(depth): a still focus is not drawn on \(found.still)")
        #expect(found.disabled.isEmpty, "\(depth): disabled looks enabled on \(found.disabled)")
    }
}
