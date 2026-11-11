//  🖥️ TUI — A Terminal UI framework for Swift
//  DisabledLabelTests.swift
//
//  A disabled control's label is drawn disabled, in the same grey every
//  control's is, and looks unlike the enabled label in every palette, at every
//  depth (the owner's evening feedback, 2026-11-10, item 22: a disabled radio
//  button's label was drawn as an enabled one's, and only its `◌` said so).
//  `StateColourCollisionTests` compares a whole control, which a glyph alone
//  can tell apart; this compares the label's own cells.
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

/// A control whose label sits beside it, labelled "Go" (and its options
/// "One" and "Two", where it has them).
enum LabelProbe: String, CaseIterable, CustomStringConvertible {
    case checkbox, toggleSwitch, radioPicker, radioGroup, radioGroupFlag, radioItem
    case stepper, slider, menuPicker, segmentedPicker, datePicker, disclosureGroup

    var description: String { rawValue }

    /// The word whose cells are compared.
    var label: String {
        switch self {
        case .radioPicker, .radioGroup, .radioGroupFlag, .radioItem: "Two"
        default: "Go"
        }
    }

    /// The control, disabled as `disabled` says: with `.disabled(_:)`, or the
    /// way the probe names.
    @MainActor @ViewBuilder
    func view(disabled: Bool) -> some View {
        switch self {
        case .checkbox: Toggle("Go", isOn: .constant(false)).disabled(disabled)
        case .toggleSwitch: Toggle("Go", isOn: .constant(false)).toggleStyle(.switch).disabled(disabled)
        case .radioPicker:
            Picker("Go", selection: .constant(1)) {
                Text("One").tag(1)
                Text("Two").tag(2)
            }
            .pickerStyle(.radioGroup)
            .disabled(disabled)
        case .radioGroup:
            RadioButtonGroup(selection: .constant(1)) {
                RadioButtonItem(1, "One")
                RadioButtonItem(2, "Two")
            }
            .disabled(disabled)
        case .radioGroupFlag:
            RadioButtonGroup(selection: .constant(1), isDisabled: disabled) {
                RadioButtonItem(1, "One")
                RadioButtonItem(2, "Two")
            }
        case .radioItem:
            RadioButtonGroup(selection: .constant(1)) {
                RadioButtonItem(1, "One")
                RadioButtonItem(2, "Two").disabled(disabled)
            }
        case .stepper: Stepper("Go", value: .constant(1), in: 0...5).disabled(disabled)
        case .slider: Slider(value: .constant(0.5), in: 0...1) { Text("Go") }.disabled(disabled)
        case .menuPicker:
            Picker("Go", selection: .constant(1)) {
                Text("One").tag(1)
                Text("Two").tag(2)
            }
            .pickerStyle(.menu)
            .disabled(disabled)
        case .segmentedPicker:
            Picker("Go", selection: .constant(1)) {
                Text("One").tag(1)
                Text("Two").tag(2)
            }
            .pickerStyle(.segmented)
            .disabled(disabled)
        case .datePicker:
            DatePicker("Go", selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date)
                .disabled(disabled)
        case .disclosureGroup: DisclosureGroup("Go") { Text("One") }.disabled(disabled)
        }
    }
}

@MainActor
@Suite("A disabled control's label is drawn disabled")
struct DisabledLabelTests {
    nonisolated static let depths: [ColorDepth] = [.truecolor, .palette256, .basic16, .noColor]

    /// The cells of the probe's label, as they can be seen: below a button
    /// that holds the focus, so the probe is drawn at rest.
    private func labelCells(_ probe: LabelProbe, disabled: Bool, palette: any Palette) -> [String] {
        let app = TestApp(width: 60, height: 10) {
            VStack(alignment: .leading) {
                Button("Anchor") {}.focusID("anchor")
                probe.view(disabled: disabled)
            }
            .palette(palette)
        }
        guard let place = app.screen.location(of: probe.label) else { return [] }
        let cells = paintedCells(app.screen.styledLines[place.y])
        let end = min(cells.count, place.x + probe.label.count)
        return cells[place.x..<end].map { "\($0.glyph)|\($0.visibleState)" }
    }

    @Test(
        "A disabled label looks unlike the enabled one, every palette and depth",
        arguments: LabelProbe.allCases, depths)
    func disabledLabelShows(_ probe: LabelProbe, _ depth: ColorDepth) {
        var same: [String] = []
        ColorDepth.withCurrent(depth) {
            for palette in PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles {
                let enabled = labelCells(probe, disabled: false, palette: palette)
                let disabled = labelCells(probe, disabled: true, palette: palette)
                #expect(!enabled.isEmpty, "the premise: \(probe) shows its label in \(palette.name)")
                if enabled == disabled { same.append(palette.name) }
            }
        }
        #expect(same.isEmpty, "\(probe) at \(depth): its disabled label looks enabled in \(same)")
    }

    @Test("Every disabled label is drawn as a disabled toggle's is", arguments: LabelProbe.allCases)
    func disabledLabelsMatch(_ probe: LabelProbe) {
        let palette = SystemPalette(.green)
        let toggle = labelCells(.checkbox, disabled: true, palette: palette)
        let drawn = labelCells(probe, disabled: true, palette: palette)
        // A label's own letters: the toggle's "Go" against this one's word, cell
        // by cell, in what they are drawn in rather than which letter.
        let states = { (cells: [String]) in Set(cells.map { $0.drop { $0 != "|" } }) }
        #expect(states(drawn) == states(toggle), "\(probe): \(drawn) against the toggle's \(toggle)")
    }
}
