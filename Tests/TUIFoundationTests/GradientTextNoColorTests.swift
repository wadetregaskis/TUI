//  🖥️ TUI — A Terminal UI framework for Swift
//  GradientTextNoColorTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

/// Under `NO_COLOR` a gradient has no colour to spell, so a ramped text's runs
/// open no SGR; they closed one anyway, a reset after every character.
@MainActor
@Suite("A gradient text under NO_COLOR writes no escapes")
struct GradientTextNoColorTests {

    @Test("No reset follows a run that opened nothing")
    func noStrayResets() {
        let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
        let line = withColorDepth(.noColor) {
            renderToBuffer(Text("gradient").foregroundStyle(gradient), context: makeRenderContext(width: 20, height: 1))
                .lines[0]
        }
        #expect(line == "gradient", "\(line.debugDescription)")
    }

    @Test("A bold gradient text still closes what it opened")
    func boldStillCloses() {
        let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
        let line = withColorDepth(.noColor) {
            renderToBuffer(
                Text("gradient").bold().foregroundStyle(gradient), context: makeRenderContext(width: 20, height: 1)
            ).lines[0]
        }
        #expect(line.stripped == "gradient")
        #expect(line.hasSuffix(ANSIRenderer.reset), "\(line.debugDescription)")
    }
}
