//  🖥️ TUI — A Terminal UI framework for Swift
//  BrailleFieldTests.swift
//
//  Braille in colour paints its cell's background from the unlit dots, so a
//  tone below the threshold keeps its colour; and a stated ink threshold
//  replaces the measured one (the owner, 2026-10-28, afternoon list #29).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIImage
@testable import TUIStyling

@Suite("Braille's background and the ink threshold")
struct BrailleFieldTests {
    /// One braille cell, 2 × 4 pixels: its top half `top`, its bottom half
    /// `bottom`.
    private static func cell(top: RGBA, bottom: RGBA) -> RGBAImage {
        RGBAImage(width: 2, height: 4, pixels: [top, top, top, top, bottom, bottom, bottom, bottom])
    }

    private static let white = RGBA(r: 250, g: 250, b: 250)
    private static let navy = RGBA(r: 20, g: 30, b: 120)

    private func line(_ mode: ASCIIColorMode, threshold: Double? = nil) -> String {
        let converter = ASCIIConverter(
            characterSet: .blocks(.braille), colorMode: mode, inkThreshold: threshold)
        return converter.convert(Self.cell(top: Self.white, bottom: Self.navy), width: 1, height: 1).lines[0]
    }

    @Test("In colour, the lit dots are drawn in their own colour and the unlit ones paint the background")
    func colourPaintsTheField() {
        let drawn = line(.trueColor)
        #expect(drawn.contains("38;2;250;250;250"), "the dots in the white: \(drawn.debugDescription)")
        #expect(drawn.contains("48;2;20;30;120"), "the navy as the background: \(drawn.debugDescription)")
    }

    @Test("In mono there is one ink, and no background")
    func monoPaintsNoField() {
        #expect(!line(.mono).contains("48;"), "\(line(.mono).debugDescription)")
    }

    @Test("A stated threshold decides the dots: at 0 every pixel is ink, at 1 only white is")
    func statedThreshold() {
        let all = line(.trueColor, threshold: 0)
        let none = line(.trueColor, threshold: 1)
        #expect(all.contains("\u{28FF}"), "every dot lit: \(all.debugDescription)")
        #expect(none.contains("\u{2800}"), "no dot lit: \(none.debugDescription)")
    }
}
