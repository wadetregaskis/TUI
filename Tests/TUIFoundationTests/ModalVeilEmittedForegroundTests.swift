//  🖥️ TUI — A Terminal UI framework for Swift
//  ModalVeilEmittedForegroundTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("Modal veil emitted foreground tracking")
struct ModalVeilEmittedForegroundTests {
    @Test("Background-only change updates foreground when contrast adjustment is no longer needed")
    func backgroundChangeUpdatesForeground() {
        ColorDepth.withCurrent(.palette256) {
            let palette = EnvironmentValues().palette
            let dark = "\u{1B}[38;2;60;60;60;48;2;50;50;50mText1"
            let blackBg = "\u{1B}[48;2;0;0;0mText2"
            let buffer = FrameBuffer(lines: [dark + blackBg])
            let veiled = buffer.veiledAsBackdrop(by: .rgb(10, 10, 10), surface: .black, palette: palette)
            let line = veiled.lines[0]

            let text2Index = line.range(of: "Text2")?.lowerBound
            #expect(text2Index != nil)
            if let text2Index {
                let text1End = line.range(of: "Text1")!.upperBound
                let between = line[text1End..<text2Index]
                #expect(between.contains("38;") || between.contains("38:"), "Foreground should be re-emitted: \(line.debugDescription)")
            }
        }
    }
}
