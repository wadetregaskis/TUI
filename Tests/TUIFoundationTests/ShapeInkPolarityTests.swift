//  🖥️ TUI — A Terminal UI framework for Swift
//  ShapeInkPolarityTests.swift
//
//  Shape-aware conversion inks a cell by its brightness, as every charset's
//  ramp does: a glyph is drawn in the cell's colour on the terminal's dark
//  field, so turning shape matching on changes the glyphs and never which
//  parts of the picture are drawn. It once inked by darkness, which turned a
//  white ground into spaces showing the terminal's black.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIImage
@testable import TUITestSupport

@MainActor
@Suite("Shape-aware conversion inks what the ramp inks")
struct ShapeInkPolarityTests {
    private func flat(_ value: UInt8) -> RGBAImage {
        RGBAImage(width: 40, height: 40, pixels: [RGBA](repeating: RGBA(r: value, g: value, b: value), count: 1600))
    }

    private func glyphs(_ image: RGBAImage, _ set: ASCIICharacterSet, shapeAware: Bool) -> String {
        ASCIIConverter(characterSet: set, shapeAware: shapeAware, colorMode: .mono, dithering: .none)
            .convert(image, width: 4, height: 2).lines.map(\.stripped).joined()
    }

    @Test("A white ground is ink, a black one is not, with or without shape matching", arguments: [
        ASCIICharacterSet.ascii, .unicode, .blocks(.fine),
    ])
    func groundPolarity(set: ASCIICharacterSet) {
        for shapeAware in [false, true] {
            let white = glyphs(flat(255), set, shapeAware: shapeAware)
            let black = glyphs(flat(0), set, shapeAware: shapeAware)
            #expect(white.contains { $0 != " " }, "white, shapeAware \(shapeAware): '\(white)'")
            #expect(black.allSatisfy { $0 == " " }, "black, shapeAware \(shapeAware): '\(black)'")
        }
    }
}
