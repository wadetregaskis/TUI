//  🖥️ TUI — A Terminal UI framework for Swift
//  StillFocusIndicatorTests.swift
//
//  A focus held still — `TUI_BREATHING=0`, the View menu's Breathing Focus
//  turned off, `Scene.focusBreathing(false)` — sits at its breath's bright end.
//  For a control whose resting look IS that end — a checked checkbox's mark, a
//  switch that is on, a link's label, a link inside a `Text`, the selected
//  option of a radio group — the focused control and the resting one were the
//  same cells, so nothing on the screen said where the keys would go. Those
//  controls now reverse their label while the focus holds still, as they do
//  without colour. A link inside a `Text` had no cue without colour either.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUI
@testable import TUIStyling
import TUITesting

/// One of the controls whose focus was told by its breath alone.
enum BreathOnlyControl: String, CaseIterable, CustomStringConvertible {
    case checkedCheckbox, switchOn, link, inlineLink, radioGroup

    var description: String { rawValue }

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .checkedCheckbox: Toggle("Go", isOn: .constant(true))
        case .switchOn: Toggle("Go", isOn: .constant(true)).toggleStyle(.switch)
        case .link: Link("Go", destination: URL(string: "https://example.com")!)
        case .inlineLink: Text("Read [the guide](https://example.com) first.")
        case .radioGroup:
            Picker("Go", selection: .constant(1)) {
                Text("One").tag(1)
                Text("Two").tag(2)
            }
            .pickerStyle(.radioGroup)
        }
    }
}

/// `control` above a button, in `palette`, under a scene that holds the focus
/// still.
private struct StillFocusApp: App {
    var control = BreathOnlyControl.checkedCheckbox
    var palette: any Palette = PaletteRegistry.all[0]
    var still = true

    init() {}

    init(control: BreathOnlyControl, palette: any Palette, still: Bool) {
        self.control = control
        self.palette = palette
        self.still = still
    }

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading) {
                control.view
                Spacer()
                Button("Anchor") {}.focusID("anchor")
            }
            .palette(palette)
        }
        .focusBreathing(!still)
    }
}

@MainActor
@Suite("A focus held still still shows, on every control and in every palette")
struct StillFocusIndicatorTests {
    /// The rows above the anchor, with the focus on the control and then on
    /// the anchor below it.
    private func rows(
        _ control: BreathOnlyControl, _ palette: any Palette, still: Bool = true
    ) -> (focused: [String], resting: [String]) {
        let app = TestApp(StillFocusApp(control: control, palette: palette, still: still), width: 40, height: 8)
        let focused = app.screen.styledLines
        #expect(app.focusedID != "anchor", "the premise: \(control) takes the focus first")
        app.press(.tab)
        #expect(app.focusedID == "anchor", "the premise: Tab moves it to the anchor")
        let resting = app.screen.styledLines
        return (Array(focused.prefix(3)), Array(resting.prefix(3)))
    }

    @Test(
        "A focused control looks unlike the same control at rest, with the focus held still",
        arguments: BreathOnlyControl.allCases)
    func focusShows(_ control: BreathOnlyControl) {
        for palette in PaletteRegistry.all {
            let drawn = rows(control, palette)
            #expect(drawn.focused != drawn.resting, "\(control) in \(palette.name): the focus is not drawn")
        }
    }

    @Test("Without colour, a breathing focus on the same controls shows too", arguments: BreathOnlyControl.allCases)
    func focusShowsWithoutColour(_ control: BreathOnlyControl) {
        let drawn = ColorDepth.withCurrent(.noColor) { rows(control, PaletteRegistry.all[0], still: false) }
        #expect(drawn.focused != drawn.resting, "\(control) without colour: the focus is not drawn")
    }

    /// The breath can't move where its colours can't be mixed: under the
    /// `Terminal` palette until the terminal reports them, it holds at the bright
    /// end whatever the setting.
    @Test(
        "Before the terminal reports its colours, a breathing focus on the same controls shows too",
        arguments: BreathOnlyControl.allCases)
    func focusShowsBeforeColoursAreReported(_ control: BreathOnlyControl) {
        let drawn = TerminalColors.withCurrent(.unknown) {
            ColorDepth.withCurrent(.truecolor) { rows(control, LiveTerminalPalette(), still: false) }
        }
        #expect(drawn.focused != drawn.resting, "\(control) under unreported colours: the focus is not drawn")
    }
}
