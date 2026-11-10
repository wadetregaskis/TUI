//  🖥️ TUI — A Terminal UI framework for Swift
//  DisabledLooksDisabledTests.swift
//
//  A disabled control looks disabled in every palette at every colour depth.
//
//  Found by sweeping every control kind through the palettes and depths in a
//  `TestApp`: a disabled `List` or `Table` drew exactly as an enabled one
//  without the focus at any colour depth. They have no ink of their own to
//  grey, and their faint was kept for no colour.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUI
import TUITesting

/// A row of a table.
private struct Row: Identifiable {
    let id: Int
    let name: String
}

/// A control kind, drawn enabled or disabled.
enum DisabledProbe: String, CaseIterable, CustomStringConvertible {
    case list, table, tabView, button, toggle, textField

    var description: String { rawValue }

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .list:
            List(selection: .constant(Set([1]))) {
                Text("One").tag(1)
                Text("Two").tag(2)
            }
            .frame(height: 4)
        case .table:
            Table([Row(id: 1, name: "One"), Row(id: 2, name: "Two")]) { TableColumn("Name", value: \Row.name) }
                .frame(height: 5)
        case .tabView:
            TabView(selection: .constant(0)) {
                Tab("One", value: 0) { Text("One") }
                Tab("Two", value: 1) { Text("Two") }
            }
            .frame(height: 4)
        case .button: Button("Go") {}
        case .toggle: Toggle("Go", isOn: .constant(true))
        case .textField: TextField("Name", text: .constant("Go"))
        }
    }
}

@MainActor
@Suite("A disabled control looks disabled in every palette and at every depth")
struct DisabledLooksDisabledTests {
    /// The rows the control draws, below a button that holds the focus, so the
    /// enabled control is drawn at rest.
    private func rows(_ probe: DisabledProbe, palette: any Palette, disabled: Bool) -> [String] {
        let app = TestApp(width: 40, height: 8) {
            VStack(alignment: .leading) {
                Button("Anchor") {}
                probe.view.disabled(disabled)
            }
            .palette(palette)
        }
        return Array(app.screen.styledLines.dropFirst())
    }

    @Test("A disabled List, Table or TabView is told from an enabled one at every colour depth", arguments: [
        DisabledProbe.list, .table, .tabView,
    ])
    func containers(_ probe: DisabledProbe) {
        for depth in [ColorDepth.basic16, .palette256, .truecolor] {
            for palette in PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles {
                ColorDepth.withCurrent(depth) {
                    #expect(
                        rows(probe, palette: palette, disabled: true) != rows(probe, palette: palette, disabled: false),
                        "\(probe) in \(palette.name) at \(depth) looks enabled")
                }
            }
        }
    }
}
