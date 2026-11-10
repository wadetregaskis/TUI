//  🖥️ TUI — A Terminal UI framework for Swift
//  UnreportedColoursDisabledTests.swift
//
//  Under the `Terminal` palette before the terminal has reported its colours,
//  which a host such as GNU screen never does, the grey a disabled control is
//  drawn in can't be mixed: it came out as the plain foreground, so a disabled
//  button, text field, list or table looked enabled. They are drawn faint
//  there, as without colour.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUI
@testable import TUIStyling
import TUITesting

@MainActor
@Suite("A disabled control looks disabled before the terminal reports its colours")
struct UnreportedColoursDisabledTests {
    /// The rows the control draws, below a button that holds the focus, so the
    /// enabled control is drawn at rest.
    private func rows(_ probe: DisabledProbe, disabled: Bool) -> [String] {
        let app = TestApp(width: 40, height: 8) {
            VStack(alignment: .leading) {
                Button("Anchor") {}
                probe.view.disabled(disabled)
            }
            .palette(LiveTerminalPalette())
        }
        return Array(app.screen.styledLines.dropFirst())
    }

    @Test(
        "Under the Terminal palette, before the terminal reports its colours, a disabled control looks disabled",
        arguments: DisabledProbe.allCases)
    func unreportedTerminalColours(_ probe: DisabledProbe) {
        TerminalColors.withCurrent(.unknown) {
            ColorDepth.withCurrent(.truecolor) {
                #expect(
                    rows(probe, disabled: true) != rows(probe, disabled: false),
                    "\(probe) looks enabled")
            }
        }
    }
}
