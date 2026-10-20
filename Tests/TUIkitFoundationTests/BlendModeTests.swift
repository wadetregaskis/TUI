//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BlendModeTests.swift
//
//  `.blendMode(_:)`: each mode's arithmetic against what macOS draws, and the
//  composite's answers for one cell — over a field, over text, over nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

@MainActor
@Suite("Blend modes")
struct BlendModeTests {

    /// What macOS 15.8 drew (`Tools/SwiftUIProbes/Blend modes/blendmodes.out`): the
    /// source (204, 102, 77) over the backdrop, opaque and at half opacity. The
    /// backdrop is the one SwiftUI drew, (51, 153, 229): its 0.9 blue lands on 229.
    private static let measured: [(BlendMode, opaque: [Int], half: [Int])] = [
        (.normal, [204, 102, 77], [128, 128, 153]),
        (.multiply, [41, 61, 69], [46, 107, 149]),
        (.screen, [214, 194, 237], [133, 173, 233]),
        (.overlay, [82, 133, 219], [66, 143, 224]),
        (.darken, [51, 102, 77], [51, 128, 153]),
        (.lighten, [204, 153, 229], [128, 153, 229]),
        (.colorDodge, [255, 255, 255], [153, 204, 255]),
        (.colorBurn, [0, 0, 168], [25, 77, 199]),
        (.softLight, [75, 141, 220], [63, 147, 224]),
        (.hardLight, [173, 122, 137], [112, 138, 183]),
        (.difference, [153, 51, 152], [102, 102, 191]),
        (.exclusion, [173, 133, 168], [112, 143, 199]),
        (.hue, [234, 92, 56], [143, 122, 143]),
        (.saturation, [74, 147, 201], [62, 150, 215]),
        (.color, [205, 103, 78], [128, 128, 153]),
        (.luminosity, [50, 152, 228], [50, 153, 228]),
        (.plusDarker, [0, 0, 51], [25, 76, 140]),
        (.plusLighter, [255, 255, 255], [153, 204, 255]),
    ]

    private static let source = Color.rgb(204, 102, 77)
    private static let backdrop = Color.rgb(51, 153, 229)

    private func components(_ color: Color) -> [Int] {
        guard let rgb = color.rgbComponents else { return [] }
        return [Int(rgb.red), Int(rgb.green), Int(rgb.blue)]
    }

    /// Within two levels a channel: macOS rounds through 8-bit buffers the
    /// arithmetic here does not.
    private func close(_ a: [Int], _ b: [Int]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= 2 }
    }

    @Test("Every arithmetic mode draws what macOS draws, opaque and at half opacity")
    func arithmeticMatchesMacOS() {
        for (mode, opaque, half) in Self.measured {
            let full = components(Self.source.blending(mode, at: 1, over: Self.backdrop))
            let halfway = components(Self.source.blending(mode, at: 0.5, over: Self.backdrop))
            #expect(close(full, opaque), "\(mode): \(full), macOS \(opaque)")
            #expect(close(halfway, half), "\(mode) at ½: \(halfway), macOS \(half)")
        }
    }

    @Test("The operators are not arithmetic")
    func operatorsAreNotArithmetic() {
        for mode in BlendMode.allCases {
            let isOperator = [BlendMode.sourceAtop, .destinationOver, .destinationOut].contains(mode)
            #expect(mode.isArithmetic == !isOperator, "\(mode)")
        }
    }

    // MARK: - The composite

    private func palette() -> any Palette {
        makeRenderContext(width: 8, height: 1).environment.palette
    }

    /// `view` drawn 4 × 1 and resolved at the root.
    private func drawn<V: View>(_ view: V) -> String {
        let context = makeRenderContext(width: 4, height: 1)
        let buffer = renderToBuffer(view, context: context)
        let palette = context.environment.palette
        return buffer.resolvingOpacity(surface: palette.background, palette: palette).lines.first ?? ""
    }

    private func field(_ line: String, at column: Int) -> String {
        line.ansiSGRStateAt(visibleColumn: column).renderedBackground
    }

    private func expectedField(_ color: Color) -> String {
        var state = SGRState()
        state.apply("\u{1B}[" + color.backgroundCodes().joined(separator: ";") + "m")
        return state.renderedBackground
    }

    @Test("A multiplied fill over a fill draws the product")
    func multipliedFieldOverAField() {
        let line = drawn(
            ZStack {
                Self.backdrop
                Self.source.blendMode(.multiply)
            })
        let product = Self.source.blending(.multiply, at: 1, over: Self.backdrop)
        #expect(field(line, at: 1) == expectedField(product), "\(line.debugDescription)")
    }

    @Test("Over nothing an arithmetic mode leaves the view as it is, and sourceAtop leaves nothing")
    func overNothing() {
        let multiplied = drawn(Self.source.blendMode(.multiply))
        #expect(field(multiplied, at: 1) == expectedField(Self.source), "\(multiplied.debugDescription)")
        let atop = drawn(Self.source.blendMode(.sourceAtop))
        #expect(field(atop, at: 1) != expectedField(Self.source), "sourceAtop over nothing drew: \(atop.debugDescription)")
    }

    @Test("A multiply highlight over text keeps the letters and tints them")
    func highlightOverText() {
        let line = drawn(
            ZStack {
                Text("abcd").foregroundStyle(Self.backdrop)
                Color.yellow.blendMode(.multiply)
            })
        #expect(line.stripped == "abcd", "the letters went: \(line.debugDescription)")
        // The ink is no longer the text's own colour: yellow multiplied into it.
        let ink = Self.backdrop.foregroundCodes().joined(separator: ";")
        #expect(!line.ansiSGRStateAt(visibleColumn: 1).rendered.contains(ink), "the ink was not blended: \(line.debugDescription)")
    }

    @Test("destinationOver keeps what is behind on top, and destinationOut erases it")
    func operatorsOverAField() {
        let over = drawn(
            ZStack {
                Self.backdrop
                Self.source.blendMode(.destinationOver)
            })
        #expect(field(over, at: 1) == expectedField(Self.backdrop), "\(over.debugDescription)")
        let out = drawn(
            ZStack {
                Self.backdrop
                Self.source.blendMode(.destinationOut)
            })
        #expect(field(out, at: 1) != expectedField(Self.backdrop), "destinationOut kept the backdrop: \(out.debugDescription)")
    }

    @Test("sourceAtop over text draws the letters in the source's colour, and no field")
    func sourceAtopColoursTheLetters() {
        let line = drawn(
            ZStack {
                Text("abcd").foregroundStyle(Self.backdrop)
                Self.source.blendMode(.sourceAtop)
            })
        #expect(line.stripped == "abcd", "the letters went: \(line.debugDescription)")
        let state = line.ansiSGRStateAt(visibleColumn: 1)
        #expect(state.rendered.contains(Self.source.foregroundCodes().joined(separator: ";")), "\(line.debugDescription)")
        #expect(!state.rendered.contains(Self.source.backgroundCodes().joined(separator: ";")), "it painted a field: \(line.debugDescription)")
    }

    @Test("A fade inside a blend keeps its alpha and takes the mode")
    func fadeInsideABlend() {
        let line = drawn(
            ZStack {
                Self.backdrop
                Self.source.opacity(0.5).blendMode(.multiply)
            })
        let half = Self.source.blending(.multiply, at: 0.5, over: Self.backdrop)
        #expect(field(line, at: 1) == expectedField(half), "\(line.debugDescription)")
    }
}
