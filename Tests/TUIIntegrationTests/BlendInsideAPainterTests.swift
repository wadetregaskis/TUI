//  🖥️ TUI — A Terminal UI framework for Swift
//  BlendInsideAPainterTests.swift
//
//  A blend mode inside a painter blends with the painter's field, which is what
//  is behind it, and leaves that field alone: SwiftUI multiplies blended letters
//  into their `.background`'s fill and draws the fill unblended
//  (`Tools/SwiftUIProbes/Blend modes/blendbackdrops.out`). Before, an opaque
//  painter let the mode's claim travel on, and it met the painter's field as the
//  blended view's own: over nothing at the root the letters were not blended at
//  all, and over another view the fill was multiplied into that view (H-67).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITabsTestSupport
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("A blend mode inside a painter blends with the painter's field")
struct BlendInsideAPainterTests {

    /// SwiftUI's light cyan as macOS 15.8 draws it.
    private static let cyan = Color.rgb(85, 190, 240)

    /// The colour of a written cell's field, where it has an RGB.
    private static func colour(_ field: SGRState.Colour?) -> Color? {
        guard case .rgb(let red, let green, let blue) = field else { return nil }
        return .rgb(UInt8(red), UInt8(green), UInt8(blue))
    }

    /// Cyan letters multiplied inside each painter: every probe cell keeps the field the
    /// unblended letters are drawn on, and the letters' ink is the cyan multiplied into
    /// that field. A cell whose field is the page is over nothing, where a mode leaves
    /// the view as it is (`Opacity as composition.md` §110), and is held only to its field.
    @Test(
        "Inside every painter, multiplied letters take the field's colour and leave the field",
        arguments: FieldPainter.allCases.filter { $0 != .none })
    func multipliedLettersInsideEveryPainter(painter: FieldPainter) throws {
        let probe = Text("xyab").foregroundStyle(Self.cyan)
        let bare = writtenRows(of: painter.view(probe))
        let blended = writtenRows(of: painter.view(probe.blendMode(.multiply)))
        try #require(bare.count == blended.count)
        let page = EnvironmentValues().palette.background.resolve(with: EnvironmentValues().palette).rgbComponents
        var multiplied = 0
        for (row, cells) in bare.enumerated() {
            let starts = cells.indices.filter { start in
                start + 3 < cells.count && cells[start..<(start + 4)].map(\.glyph) == ["x", "y", "a", "b"]
            }
            for column in starts.flatMap({ $0..<($0 + 4) }) {
                let under = cells[column]
                let drawn = blended[row][column]
                #expect(drawn.glyph == under.glyph, "\(painter) row \(row) column \(column): \(drawn.shown)")
                #expect(
                    drawn.shownField == under.shownField,
                    "\(painter) row \(row) column \(column): the field moved, \(drawn.shown) for \(under.shown)")
                guard !under.state.reversesVideo, let field = Self.colour(under.state.backgroundColour),
                    field.rgbComponents.map({ [$0.red, $0.green, $0.blue] }) != page.map({ [$0.red, $0.green, $0.blue] })
                else { continue }
                let product = try #require(Self.cyan.blending(.multiply, at: 1, over: field).rgbComponents)
                #expect(
                    drawn.ink == .rgb(Int(product.red), Int(product.green), Int(product.blue)),
                    "\(painter) row \(row) column \(column): \(drawn.shown), the cyan times \(under.shown)")
                multiplied += 1
            }
        }
        // Not vacuous: every painter but the stripes puts a colour under all four letters.
        #expect(multiplied >= 2, "\(painter): \(multiplied) letters over a colour")
    }
}
