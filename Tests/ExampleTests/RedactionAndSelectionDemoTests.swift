//  🖥️ TUI — A Terminal UI framework for Swift
//  RedactionAndSelectionDemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("The Text Styles page's Placeholders section", .serialized)
struct RedactionAndSelectionDemoTests {
    @Test("Enabling Show activity sweeps a visible glint across the placeholder lines")
    func showActivityAnimatesPlaceholder() {
        for depth: ColorDepth in [.truecolor, .palette256] {
            ColorDepth.withCurrent(depth) {
                let app = TestApp(width: 100, height: 20) {
                    RedactionAndSelectionDemo()
                        .theme(Theme(palette: SystemPalette(.green)))
                }
                app.date = Date(timeIntervalSinceReferenceDate: 0)
                let initialLines = app.screen.lines
                var sawGlintGlyphs = false
                for _ in 0..<10 {
                    app.advance(by: .milliseconds(100))
                    let current = app.screen.lines.joined(separator: "\n")
                    if current.contains("▒") || current.contains("▓") {
                        sawGlintGlyphs = true
                        // The unredacted heading stays readable.
                        #expect(current.contains("page.textStyles.redacted.heading"))
                        break
                    }
                }
                #expect(sawGlintGlyphs, "Show activity must sweep a visible glint across placeholder cells at \(depth): \(initialLines)")
            }
        }
    }
}
