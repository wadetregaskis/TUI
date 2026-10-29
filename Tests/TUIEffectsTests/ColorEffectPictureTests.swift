//  🖥️ TUI — A Terminal UI framework for Swift
//  ColorEffectPictureTests.swift
//
//  A colour effect over a picture the terminal draws: the picture's cells
//  name their image in their foreground, so they draw a recoloured copy of it
//  rather than having that id rewritten as a colour.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIEffects
@testable import TUIFoundation
@testable import TUITestSupport

/// Draws the lines it is given, as they are.
private struct Lines: View, Renderable {
    let lines: [String]
    var body: Never { fatalError("Lines renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: lines)
    }
}

@MainActor
@Suite("Colour effects over pictures")
struct ColorEffectPictureTests {
    /// A store holding a red picture 4 × 1 cells, and the row that draws it,
    /// followed by a red `x`.
    private func redPicture() throws -> (store: TerminalImageStore, row: String, id: KittyGraphics.ImageID) {
        let store = TerminalImageStore()
        let red: [UInt8] = [255, 0, 0, 255]
        let pixels = Array([[UInt8]](repeating: red, count: 4 * DerivedImages.pixelsAcross * DerivedImages.pixelsDown)
            .joined())
        let id = try #require(store.backdrop(pixels: pixels, columns: 4, rows: 1))
        let row = KittyGraphics.placeholderRows(id: id, columns: 4, rows: 1)[0] + "\u{1B}[38;2;255;0;0mx\u{1B}[0m"
        return (store, row, id)
    }

    /// The picture cells of `line`, read back.
    private func pictureCells(_ line: String) -> [KittyGraphics.PlaceholderCell?] {
        FrameBuffer.cells(in: line, through: line.strippedLength, defaultForeground: .white, surface: .black).map { cell in
            guard let cell, let ink = cell.foreground?.rgbComponents else { return nil }
            return KittyGraphics.placeholderCell(cell.character, foreground: ink)
        }
    }

    private func drawn(_ view: some View, images: TerminalImageStore?) -> String {
        var context = makeRenderContext(width: 8, height: 1)
        context.environment.terminalImageStore = images
        return renderToBuffer(view, context: context).lines.first ?? ""
    }

    /// Every effect but a multiply by a tint with no RGB has a form for
    /// pictures; `.grayscale(1)` drew a blank strip in Ghostty, which draws a
    /// gradient as a picture, and `.colorMultiply` an unchanged one.
    @Test(
        "A picture under a colour effect draws a copy recoloured by it, and text beside it is recoloured as before",
        arguments: [
            ImageTransform.Recolour.saturation(0), .brightness(19), .contrast(26), .hueRotation(120), .invert,
            .multiply(0x50A0FF),
        ])
    func pictureDrawsRecolouredCopy(recolour: ImageTransform.Recolour) throws {
        let (store, row, id) = try redPicture()
        let line = drawn(Self.effected(row, as: recolour), images: store)
        let cells = pictureCells(line)
        let expected = try #require(
            store.derived(.init(id: id, row: 0, column: 0), by: ImageTransform(recolouring: recolour)))
        #expect(expected.id != id)
        #expect(cells.prefix(4).map { $0?.id } == Array(repeating: expected.id, count: 4), "\(line.debugDescription)")
        #expect(cells.prefix(4).map { $0?.column } == [0, 1, 2, 3])
        // The x after the picture is text, recoloured as it is on its own.
        let text = "\u{1B}[38;2;255;0;0mx\u{1B}[0m"
        let alone = drawn(Self.effected(text, as: recolour), images: store)
        let ink = { (line: String, column: Int) in
            FrameBuffer.cells(in: line, through: line.strippedLength, defaultForeground: .white, surface: .black)[column]?
                .foreground
        }
        #expect(cells[4] == nil)
        #expect(ink(line, 4) == ink(alone, 0), "\(line.debugDescription)")
    }

    /// `row` under the effect the test's `recolour` stands for.
    private static func effected(_ row: String, as recolour: ImageTransform.Recolour) -> AnyView {
        let lines = Lines(lines: [row])
        return switch recolour {
        case .saturation: AnyView(lines.grayscale(1))
        case .brightness: AnyView(lines.brightness(0.3))
        case .contrast: AnyView(lines.contrast(0.4))
        case .hueRotation: AnyView(lines.hueRotation(.degrees(120)))
        case .invert: AnyView(lines.colorInvert())
        case .multiply: AnyView(lines.colorMultiply(.rgb(80, 160, 255)))
        }
    }

    @Test("A greyed copy's pixels are grey")
    func greyedPixelsAreGrey() {
        let pixels = DerivedImages.applying(
            ImageTransform(recolouring: .saturation(0)), to: [200, 40, 40, 255], width: 1, height: 1)
        #expect(pixels[0] == pixels[1] && pixels[1] == pixels[2] && pixels[3] == 255, "\(pixels)")
        let inverted = DerivedImages.applying(
            ImageTransform(recolouring: .invert), to: [200, 40, 40, 255], width: 1, height: 1)
        #expect(inverted == [55, 215, 215, 255])
    }

    @Test("With no store to copy from, a picture under an effect is drawn as it is, not blanked")
    func noStoreKeepsThePicture() throws {
        let (_, row, id) = try redPicture()
        let line = drawn(Lines(lines: [row]).grayscale(1), images: nil)
        #expect(pictureCells(line).prefix(4).map { $0?.id } == Array(repeating: id, count: 4), "\(line.debugDescription)")
    }
}
