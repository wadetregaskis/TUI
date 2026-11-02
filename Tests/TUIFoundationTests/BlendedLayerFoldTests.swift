//  🖥️ TUI — A Terminal UI framework for Swift
//  BlendedLayerFoldTests.swift
//
//  Folding a stack of translucent layers in cells is a speed change and nothing
//  else: every stack here is drawn both ways, the fold and one composite per
//  layer, and the two must agree on every cell of every row. Not on every byte:
//  one composite per layer leaves each base's closing escapes behind the last
//  cell, thirty layers' worth in a stack of thirty, and the fold has none to leave.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("Folding blended layers")
struct BlendedLayerFoldTests {

    private typealias Layer = (buffer: FrameBuffer, x: Int, y: Int)

    private static let width = 24
    private static let height = 6

    /// A generator that says the same thing on every platform and every run, so a
    /// failure can be repeated.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    private func composite(linearLight: Bool = false) -> CompositeEnvironment {
        CompositeEnvironment(palette: makeRenderContext(width: 8, height: 1).environment.palette, linearLight: linearLight)
    }

    private func blank() -> FrameBuffer {
        FrameBuffer(lines: Array(repeating: String.spaces(Self.width), count: Self.height))
    }

    /// One composite per layer: what the fold has to come to.
    private func oneAtATime(_ layers: [Layer], in composite: CompositeEnvironment) -> FrameBuffer {
        var result = blank()
        for layer in layers {
            result = result.compositedCarryingClaimsOverNothing(with: layer.buffer, at: (x: layer.x, y: layer.y), in: composite)
        }
        return result
    }

    /// `FrameBuffer.layered`'s loop, with `composite` said here rather than read from
    /// an environment, and how many layers it folded.
    private func folded(_ layers: [Layer], in composite: CompositeEnvironment) -> (buffer: FrameBuffer, count: Int) {
        var result = blank()
        var count = 0
        var next = 0
        while next < layers.count {
            let taken = result.foldingBlendedLayers(layers[next...], width: Self.width, height: Self.height, in: composite)
            count += taken
            next += taken
            let layer = layers[next]
            result = result.compositedCarryingClaimsOverNothing(with: layer.buffer, at: (x: layer.x, y: layer.y), in: composite)
            next += 1
        }
        return (result, count)
    }

    /// A line of plain cells, every colour its own and, where `glyphs`, letters among
    /// the blanks.
    private func plainLine(using random: inout Seeded, glyphs: Bool) -> String {
        var line = ""
        for _ in 0..<Self.width {
            let parts = (0..<6).map { _ in String(Int.random(in: 0...255, using: &random)) }
            line += "\u{1B}[38;2;\(parts[0]);\(parts[1]);\(parts[2]);48;2;\(parts[3]);\(parts[4]);\(parts[5])m"
            line.append(glyphs && Bool.random(using: &random) ? "x" : " ")
        }
        return line + "\u{1B}[0m"
    }

    /// A whole-canvas layer of `lines`, under one claim.
    private func layer(_ lines: [String], _ claim: (Int, Int) -> OpacityRegion) -> Layer {
        var buffer = FrameBuffer(lines: lines)
        buffer.opacityRegions = [claim(Self.width, Self.height)]
        return (buffer, 0, 0)
    }

    /// `count` whole-canvas layers of plain cells, with alphas spread over the range and
    /// its ends.
    private func plainLayers(count: Int, seed: UInt64, mode: BlendMode, glyphs: Bool, sameRows: Bool = false) -> [Layer] {
        var random = Seeded(state: seed)
        let ladder = [0.02, 0.3, 0.5, 0.75, 0, 1, 0.49, 0.99]
        return (0..<count).map { index in
            let first = plainLine(using: &random, glyphs: glyphs)
            let lines = (0..<Self.height).map { _ in sameRows ? first : plainLine(using: &random, glyphs: glyphs) }
            return layer(lines) { width, height in
                OpacityRegion(
                    offsetX: 0, offsetY: 0, width: width, height: height, opacity: ladder[index % ladder.count],
                    inkOpacity: index.isMultiple(of: 3) ? 0.6 : 1, fieldOpacity: index.isMultiple(of: 4) ? 0.7 : 1, blendMode: mode)
            }
        }
    }

    /// What `line` draws, a cell at a time, and the state it leaves behind it: what a
    /// terminal could tell two lines apart by.
    private func drawing(of line: String) -> [String] {
        // One column past the canvas, for a line that is too long. The two colours only
        // answer for a reversed cell, which then shows them in both drawings.
        let cells = FrameBuffer.cells(
            in: line, through: Self.width + 1, defaultForeground: .rgb(1, 2, 3), surface: .rgb(4, 5, 6))
        var state = SGRState()
        _ = line.forEachANSISegment { segment in
            if case .ansi(let sequence, _) = segment { state.apply(sequence) }
            return true
        }
        return cells.map { cell in
            guard let cell else { return "none" }
            return "\(cell.character) \(cell.style.rendered(changingFrom: SGRState())) \(cell.isReversed)"
        } + ["ends \(state.rendered(changingFrom: SGRState()))"]
    }

    /// Both ways of drawing `layers` at 24-bit colour agree, and answers how many
    /// layers the fold took, for a test to say it was not idle.
    @discardableResult
    private func expectSameDrawing(_ layers: [Layer], linearLight: Bool = false, sourceLocation: SourceLocation = #_sourceLocation) -> Int {
        ColorDepth.withCurrent(.truecolor) {
            let composite = composite(linearLight: linearLight)
            let expected = oneAtATime(layers, in: composite)
            let (actual, count) = folded(layers, in: composite)
            #expect(actual.lines.map(drawing) == expected.lines.map(drawing), sourceLocation: sourceLocation)
            #expect(actual.opacityRegions == expected.opacityRegions, sourceLocation: sourceLocation)
            #expect(actual.width == expected.width, sourceLocation: sourceLocation)
            return count
        }
    }

    @Test("Every mode that mixes colours, over blanks and letters", arguments: [
        BlendMode.normal, .multiply, .screen, .overlay, .darken, .lighten, .colorDodge, .colorBurn, .softLight,
        .hardLight, .difference, .exclusion, .hue, .saturation, .color, .luminosity, .plusDarker, .plusLighter,
    ])
    func everyArithmeticMode(mode: BlendMode) {
        let count = expectSameDrawing(plainLayers(count: 12, seed: 1, mode: mode, glyphs: true))
        // The first lands on nothing and the second on a claim; the last is the composite's.
        #expect(count == 9)
    }

    @Test("Blanks alone")
    func blanksAlone() {
        #expect(expectSameDrawing(plainLayers(count: 12, seed: 2, mode: .screen, glyphs: false)) == 9)
    }

    @Test("Rows that repeat, where the fold asks once, and a row that stops repeating")
    func repeatingRows() {
        var layers = plainLayers(count: 12, seed: 3, mode: .screen, glyphs: false, sameRows: true)
        #expect(expectSameDrawing(layers) == 9)
        // A layer whose rows differ, at each place in the stack the rows matched before.
        var random = Seeded(state: 33)
        let lines = (0..<Self.height).map { _ in plainLine(using: &random, glyphs: true) }
        layers[6] = layer(lines) { OpacityRegion(offsetX: 0, offsetY: 0, width: $0, height: $1, opacity: 0.4, blendMode: .screen) }
        #expect(expectSameDrawing(layers) == 9)
    }

    @Test("In linear light")
    func inLinearLight() {
        #expect(expectSameDrawing(plainLayers(count: 12, seed: 4, mode: .normal, glyphs: true), linearLight: true) == 9)
        #expect(expectSameDrawing(plainLayers(count: 12, seed: 5, mode: .screen, glyphs: true), linearLight: true) == 9)
    }

    /// Whatever follows the fold is laid over the lines it spelled and the layer it left
    /// to the composite, and any of them could show a difference there.
    @Test("Whatever follows a run")
    func whateverFollows() {
        let run = plainLayers(count: 8, seed: 6, mode: .screen, glyphs: true)
        let narrow = FrameBuffer(lines: Array(repeating: "\u{1B}[31mhi\u{1B}[0m", count: 2))
        var fadedNarrow = narrow
        fadedNarrow.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 0, width: 2, height: 2, opacity: 0.5)]
        var leavesItsField = FrameBuffer(lines: Array(repeating: String(repeating: "y", count: Self.width), count: Self.height))
        leavesItsField.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: Self.width, height: Self.height, opacity: 0.6, blendMode: .screen)
        ]
        let followers: [Layer] = [
            (narrow, 3, 2),
            (fadedNarrow, 5, 1),
            (FrameBuffer(lines: ["plain text"]), 0, 0),
            (leavesItsField, 0, 0),
        ]
        for follower in followers {
            #expect(expectSameDrawing(run + [follower]) == 5)
        }
    }

    /// Each of these breaks the rule the fold relies on, in the middle of a stack.
    @Test("Layers the fold has to leave", arguments: [
        ("bold", "\u{1B}[1;38;2;1;2;3;48;2;4;5;6m"),
        ("256 colours", "\u{1B}[38;5;100;48;5;200m"),
        ("named colours", "\u{1B}[31;44m"),
        ("reversed", "\u{1B}[7;38;2;1;2;3;48;2;4;5;6m"),
        ("the terminal's field", "\u{1B}[38;2;1;2;3;49m"),
        ("no field", "\u{1B}[38;2;1;2;3m"),
        ("no ink", "\u{1B}[48;2;4;5;6m"),
        ("nothing", ""),
    ])
    func notPlain(name: String, opening: String) {
        var layers = plainLayers(count: 12, seed: 7, mode: .screen, glyphs: true)
        let lines = Array(repeating: opening + String(repeating: "z", count: Self.width) + "\u{1B}[0m", count: Self.height)
        layers[6] = layer(lines) { OpacityRegion(offsetX: 0, offsetY: 0, width: $0, height: $1, opacity: 0.6, blendMode: .screen) }
        // Before it and after it the fold still runs, up to the layer before it.
        #expect(expectSameDrawing(layers) < 9, "\(name)")
    }

    @Test("A wide glyph and a picture's placeholder")
    func wideGlyphs() {
        var layers = plainLayers(count: 8, seed: 8, mode: .screen, glyphs: true)
        for character in ["日", String(Unicode.Scalar.terminalImagePlaceholder)] {
            let opening = "\u{1B}[38;2;1;2;3;48;2;4;5;6m"
            let cells = character == "日" ? String(repeating: "日", count: Self.width / 2) : String(repeating: character, count: Self.width)
            let lines = Array(repeating: opening + cells + "\u{1B}[0m", count: Self.height)
            layers[4] = layer(lines) { OpacityRegion(offsetX: 0, offsetY: 0, width: $0, height: $1, opacity: 0.6, blendMode: .screen) }
            #expect(expectSameDrawing(layers) < 5, "\(character)")
        }
    }

    @Test("A claim that does not cover the canvas, or decides which side shows")
    func claimsItLeaves() {
        let inset = plainLayers(count: 12, seed: 9, mode: .screen, glyphs: true)
        var layers = inset
        layers[6].buffer.opacityRegions = [
            OpacityRegion(offsetX: 2, offsetY: 1, width: Self.width - 4, height: Self.height - 2, opacity: 0.5, blendMode: .screen)
        ]
        #expect(expectSameDrawing(layers) < 9)
        for mode in [BlendMode.sourceAtop, .destinationOver, .destinationOut] {
            var layers = inset
            layers[6].buffer.opacityRegions = [
                OpacityRegion(offsetX: 0, offsetY: 0, width: Self.width, height: Self.height, opacity: 0.5, blendMode: mode)
            ]
            #expect(expectSameDrawing(layers) < 9, "\(mode)")
        }
    }

    @Test("Two claims over one layer fold as the composite folds them")
    func twoClaims() {
        var layers = plainLayers(count: 8, seed: 10, mode: .normal, glyphs: true)
        for index in layers.indices {
            layers[index].buffer.opacityRegions.append(
                OpacityRegion(offsetX: 0, offsetY: 0, width: Self.width, height: Self.height, opacity: 0.8, blendMode: .multiply))
        }
        #expect(expectSameDrawing(layers) == 5)
    }

    @Test("Below 24-bit colour a spelled colour is quantised, so nothing folds", arguments: [ColorDepth.palette256, .basic16, .noColor])
    func lowerDepths(depth: ColorDepth) {
        let layers = plainLayers(count: 8, seed: 11, mode: .screen, glyphs: true)
        ColorDepth.withCurrent(depth) {
            let (_, taken) = folded(layers, in: composite())
            #expect(taken == 0)
        }
    }

    /// The real thing, through the views and the compositor's own loop: the comparison's
    /// `lat-blend`, at the size a test can afford.
    @Test("A stack of blended gradients, drawn by a ZStack", arguments: [
        (UnitPoint.leading, UnitPoint.trailing), (.top, .bottom), (.topLeading, .bottomTrailing),
    ])
    func gradientsInAZStack(start: UnitPoint, end: UnitPoint) {
        ColorDepth.withCurrent(.truecolor) {
            let context = makeRenderContext(width: Self.width, height: Self.height)
            let layers: [Layer] = (0..<12).map { index in
                let view = Rectangle()
                    .fill(LinearGradient(colors: [Color.red, Color.blue], startPoint: start, endPoint: end))
                    .opacity(0.02 + Double(index % 10) / 100)
                    .blendMode(.screen)
                return (renderToBuffer(view, context: context), 0, 0)
            }
            let expected = oneAtATime(layers, in: CompositeEnvironment(context.environment))
            let drawn = FrameBuffer.layered(
                layers, width: Self.width, height: Self.height, splitsOverhang: false, wakeToken: "test", context: context)
            #expect(drawn.lines.map(drawing) == expected.lines.map(drawing))
            // The escapes it does not leave behind are why it may differ in bytes at all.
            #expect(drawn.lines.joined().utf8.count < expected.lines.joined().utf8.count)
            #expect(folded(layers, in: CompositeEnvironment(context.environment)).count == 9)
        }
    }
}
