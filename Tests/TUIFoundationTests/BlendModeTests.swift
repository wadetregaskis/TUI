//  🖥️ TUI — A Terminal UI framework for Swift
//  BlendModeTests.swift
//
//  `.blendMode(_:)`: each mode's arithmetic against what macOS draws, and the
//  composite's answers for one cell — over a field, over text, over nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

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

    // MARK: - ShapeStyle.blendMode

    @Test("A blended background multiplies its field, under the letters too, and leaves their ink")
    func blendedBackground() {
        let line = drawn(
            ZStack {
                Self.backdrop
                Text("ab").foregroundStyle(.white).background(Self.source.blendMode(.multiply))
            })
        let product = expectedField(Self.source.blending(.multiply, at: 1, over: Self.backdrop))
        // " ab ", centred in the four columns: the letters at 1 and 2.
        #expect(line.stripped == " ab ", "\(line.debugDescription)")
        #expect(field(line, at: 1) == product, "under a letter: \(line.debugDescription)")
        #expect(field(line, at: 2) == product, "under a letter: \(line.debugDescription)")
        #expect(field(line, at: 0) == expectedField(Self.backdrop), "beside the view: \(line.debugDescription)")
        let white = Color.white.foregroundCodes().joined(separator: ";")
        #expect(line.ansiSGRStateAt(visibleColumn: 1).rendered.contains(white), "the ink was blended: \(line.debugDescription)")
    }

    @Test("A blended shape fill multiplies the cells it fills")
    func blendedShapeFill() {
        let line = drawn(
            ZStack {
                Self.backdrop
                Rectangle().fill(Self.source.blendMode(.multiply))
            })
        let product = expectedField(Self.source.blending(.multiply, at: 1, over: Self.backdrop))
        #expect(field(line, at: 1) == product, "\(line.debugDescription)")
    }

    @Test("A blended foreground style multiplies the letters' ink into the field behind them")
    func blendedForeground() {
        let line = drawn(
            ZStack {
                Self.backdrop
                Text("abcd").foregroundStyle(Self.source.blendMode(.multiply))
            })
        let product = Self.source.blending(.multiply, at: 1, over: Self.backdrop)
        let ink = product.foregroundCodes().joined(separator: ";")
        #expect(line.ansiSGRStateAt(visibleColumn: 1).rendered.contains(ink), "\(line.debugDescription)")
    }

    // MARK: - What a mode blends against

    /// SwiftUI's yellow, blue and cyan as macOS 15.8 draws them in the light scheme
    /// (`Tools/SwiftUIProbes/Blend modes/blendbackdrops.out`).
    private static let yellow = Color.rgb(255, 204, 0)
    private static let blue = Color.rgb(0, 122, 255)
    private static let cyan = Color.rgb(85, 190, 240)

    /// Whether `line`'s cell at `column` is drawn in `color`'s ink.
    private func inks(_ line: String, at column: Int, _ color: Color) -> Bool {
        line.ansiSGRStateAt(visibleColumn: column).rendered.contains(color.foregroundCodes().joined(separator: ";"))
    }

    /// The red, green and blue of a 24-bit field spelled `ESC[48;2;r;g;bm`.
    private func components(ofField field: String) -> [Int] {
        let parameters = field.dropFirst(2).dropLast().split(separator: ";").compactMap { Int($0) }
        return parameters.count == 5 && parameters[0] == 48 && parameters[1] == 2 ? Array(parameters[2...]) : []
    }

    @Test("A mode over a fade blends with the fade as it shows over the page, not with its opaque colour")
    func modeOverAFade() {
        // SwiftUI multiplies the yellow into the blue at one half over the page, never
        // into the opaque blue: over white (128, 151, 0), not (0, 98, 0).
        let line = drawn(
            ZStack {
                Self.blue.opacity(0.5)
                Self.yellow.blendMode(.multiply)
            })
        let behind = Self.blue.blending(.normal, at: 0.5, over: palette().background)
        let product = components(Self.yellow.blending(.multiply, at: 1, over: behind))
        // Within rounding: the blue at one half is a cell's colour, in whole levels, before it is multiplied.
        let read = components(ofField: field(line, at: 1))
        #expect(close(read, product), "\(read), \(product) due: \(line.debugDescription)")
        // Never the yellow times the opaque blue.
        #expect(!close(read, components(Self.yellow.blending(.multiply, at: 1, over: Self.blue))))
    }

    @Test("A mode over a fade over a white page draws what SwiftUI draws")
    func modeOverAFadeOverWhite() {
        let line = drawn(
            ZStack {
                Color.rgb(255, 255, 255)
                Self.blue.opacity(0.5)
                Self.yellow.blendMode(.multiply)
            })
        let read = components(ofField: field(line, at: 1))
        #expect(close(read, [128, 151, 0]), "\(read): \(line.debugDescription)")
    }

    @Test("Blended letters over their own background multiply into its fill, which stays as it is")
    func blendedTextOverItsBackground() {
        let text = Text("ab").foregroundStyle(Self.cyan).blendMode(.multiply).background(Self.yellow)
        let product = Self.cyan.blending(.multiply, at: 1, over: Self.yellow)
        for (name, line) in [("over the page", drawn(text)), ("over blue", drawn(ZStack { Self.blue; text }))] {
            // At the left over the page, centred over the blue.
            let first = line.stripped.firstIndex(of: "a").map { line.stripped.distance(from: line.stripped.startIndex, to: $0) }
            guard let first, line.stripped.contains("ab") else {
                Issue.record("\(name): the letters went: \(line.debugDescription)")
                continue
            }
            #expect(inks(line, at: first, product), "\(name), the ink: \(line.debugDescription)")
            #expect(inks(line, at: first + 1, product), "\(name), the ink: \(line.debugDescription)")
            #expect(field(line, at: first) == expectedField(Self.yellow), "\(name), the fill: \(line.debugDescription)")
        }
    }

    @Test("A blended fill over its own background multiplies into it; the background beside it is unblended")
    func blendedFillOverItsBackground() {
        let view = Self.cyan.frame(width: 2, height: 1).blendMode(.multiply).padding(.horizontal, 1).background(Self.yellow)
        let product = expectedField(Self.cyan.blending(.multiply, at: 1, over: Self.yellow))
        for (name, line) in [("over the page", drawn(view)), ("over blue", drawn(ZStack { Self.blue; view }))] {
            #expect(field(line, at: 1) == product, "\(name): \(line.debugDescription)")
            #expect(field(line, at: 2) == product, "\(name): \(line.debugDescription)")
            #expect(field(line, at: 0) == expectedField(Self.yellow), "\(name), beside: \(line.debugDescription)")
            #expect(field(line, at: 3) == expectedField(Self.yellow), "\(name), beside: \(line.debugDescription)")
        }
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
