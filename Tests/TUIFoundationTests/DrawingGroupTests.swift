//  🖥️ TUI — A Terminal UI framework for Swift
//  DrawingGroupTests.swift
//
//  `drawingGroup(opaque:colorMode:)`: a compositing group whose blends mix in
//  linear light where it asks (decisions A27).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// `view` rendered in a `width` × `height` frame, resolved as the screen shows it.
@MainActor
private func screen(_ view: some View, width: Int = 2, height: Int = 1) -> FrameBuffer {
    renderToScreen(view, context: makeRenderContext(width: width, height: height))
}

/// The field a line's first cell shows.
private func field(_ buffer: FrameBuffer) -> String {
    paintedCells(buffer.lines[0])[0].background
}

private let red = Color.rgb(220, 30, 40)
private let blue = Color.rgb(20, 40, 230)

/// Half a blue over a red.
@MainActor
private var translucentOverOpaque: some View {
    ZStack {
        red
        blue.opacity(0.5)
    }
}

@MainActor
@Suite("Drawing groups and their colour spaces")
struct DrawingGroupTests {

    @Test("A non-linear group draws what the view draws without one")
    func nonLinearIsUnchanged() {
        #expect(screen(translucentOverOpaque.drawingGroup()).lines == screen(translucentOverOpaque).lines)
        #expect(
            screen(translucentOverOpaque.drawingGroup(opaque: true, colorMode: .nonLinear)).lines
                == screen(translucentOverOpaque).lines)
    }

    @Test("A linear group mixes a translucent colour in linear light")
    func linearMixes() {
        let linear = field(screen(translucentOverOpaque.drawingGroup(colorMode: .linear)))
        #expect(linear == renderedBackground(of: blue.compositing(0.5, over: red)))
        #expect(linear != field(screen(translucentOverOpaque)))
    }

    @Test("A faded view in a linear group mixes in linear light")
    func linearFades() {
        let faded = ZStack {
            red
            blue.frame(width: 2, height: 1).opacity(0.5)
        }
        #expect(field(screen(faded.drawingGroup(colorMode: .linear))) == renderedBackground(of: blue.compositing(0.5, over: red)))
    }

    @Test("What lands outside the group mixes as it would without one")
    func outsideIsEncoded() {
        let landingOutside = ZStack {
            red
            blue.opacity(0.5).drawingGroup(colorMode: .linear)
        }
        #expect(screen(landingOutside).lines == screen(translucentOverOpaque).lines)
    }

    @Test("Extended linear is linear on a terminal's colours")
    func extendedIsLinear() {
        #expect(
            screen(translucentOverOpaque.drawingGroup(colorMode: .extendedLinear)).lines
                == screen(translucentOverOpaque.drawingGroup(colorMode: .linear)).lines)
    }

    @Test("The innermost group decides")
    func innermostDecides() {
        let inner = translucentOverOpaque.drawingGroup(colorMode: .nonLinear).drawingGroup(colorMode: .linear)
        #expect(screen(inner).lines == screen(translucentOverOpaque).lines)
        let innerLinear = translucentOverOpaque.drawingGroup(colorMode: .linear).drawingGroup()
        #expect(screen(innerLinear).lines == screen(translucentOverOpaque.drawingGroup(colorMode: .linear)).lines)
    }

    @Test("A blend mode in a linear group combines in linear light")
    func linearBlendMode() {
        let multiplied = ZStack {
            red
            blue.blendMode(.multiply)
        }
        let linear = field(screen(multiplied.drawingGroup(colorMode: .linear)))
        #expect(linear == renderedBackground(of: blue.blending(.multiply, at: 1, over: red, linearLight: true)))
        #expect(linear != field(screen(multiplied)))
    }

    @Test("Mixing in linear light is the encoded mix's ends and a lighter middle")
    func linearMixShape() {
        // The ends are the colours; between them linear light is the brighter
        // mix, which is what makes it the choice for light that adds up.
        #expect(blue.blending(.multiply, at: 0, over: red, linearLight: true) == red.opaqueSpelling)
        let encoded = Color.rgb(0, 0, 0).opacity(0.5, over: .rgb(255, 255, 255))
        let linear = Color.rgb(0, 0, 0).compositing(0.5, over: .rgb(255, 255, 255))
        #expect((linear.rgbComponents?.red ?? 0) > (encoded.rgbComponents?.red ?? 255))
    }
}
