//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasDemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Only where the package can depend on the app (see Package.swift).
#if canImport(Example)

import Foundation
import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("The Shapes page's Canvas section")
struct CanvasDemoTests {
    @Test("Each canvas draws: its text, its symbols, and something in every sample's frame")
    func drawsEverySample() throws {
        let app = TestApp(width: 100, height: 40) { CanvasDemo() }
        if ProcessInfo.processInfo.environment["CANVAS_DUMP"] != nil { print(app.screen) }
        let screen = app.screen
        #expect(screen.contains("12s"), "the clock's text, a fifth of a minute round: \(screen)")
        #expect(screen.contains("★"), "the symbol: \(screen)")
        for caption in ["fill, stroke, draw", "clip, drawLayer", "resolveSymbol", ".halfBlocks", ".quadrants", ".braille", "setPixel"] {
            #expect(screen.contains(caption), "\(caption): \(screen)")
        }
        // Each grain spells the same wave in its own glyphs.
        let wave = screen.lines.joined()
        #expect(wave.contains { ("\u{2801}"..."\u{28FF}").contains(String($0)) }, "braille dots: \(screen)")
        #expect(wave.contains { "▘▝▖▗▚▞▙▛▜▟".contains($0) }, "quadrants: \(screen)")
    }

    @Test("The hand turns from the keyboard")
    func keyboardTurnsTheHand() {
        let app = TestApp(width: 100, height: 40) { CanvasDemo() }
        let before = app.screen.lines
        #expect(app.screen.contains("12s"))
        app.press(.right)
        #expect(app.screen.contains("13s"), "\(app.screen)")
        #expect(app.screen.lines != before)
    }
}

#endif
