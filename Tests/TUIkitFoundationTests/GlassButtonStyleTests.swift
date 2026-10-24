//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassButtonStyleTests.swift
//
//  `.glass`, `.glass(_:)` and `.glassProminent`: the bordered button, its
//  lines the glass's highlighted rim, on glass in its border shape.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

@MainActor
@Suite("Glass button styles")
struct GlassButtonStyleTests {

    private func context(width: Int = 12, height: Int = 3) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, _ in
            environment.palette = SystemPalette.green
        }
    }

    private func screen(_ view: some View, context: RenderContext? = nil) -> FrameBuffer {
        ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context ?? self.context()) }
    }

    /// The ink `colour` is drawn in at 24-bit depth, as a cell reads it back.
    private func ink(_ colour: Color) -> SGRState.Colour? {
        colour.resolve(with: SystemPalette.green).rgbComponents.map { .rgb(Int($0.red), Int($0.green), Int($0.blue)) }
    }

    /// `view` drawn unfocused: a focused button's face breathes the accent,
    /// glass or not.
    private func unfocused(_ view: some View) -> FrameBuffer {
        let context = context()
        context.environment.focusManager?.register(FocusSentinel())
        return screen(view, context: context)
    }

    @Test("In lines, a glass button is the bordered button, its caps in the glass's rim")
    func capsAreTheRim() {
        let glass = unfocused(Button("OK") {}.buttonStyle(.glass).controlStyle(.lines))
        let bordered = unfocused(Button("OK") {}.buttonStyle(.bordered).controlStyle(.lines))
        #expect(glass.lines.map(\.stripped) == bordered.lines.map(\.stripped))
        let environment = context().environment
        let cap = paintedCells(glass.lines[0])[0]
        #expect(cap.glyph == "(")
        #expect(cap.ink == ink(Glass.regular.rimInk(hovered: false, in: environment)))
        #expect(cap.ink != paintedCells(bordered.lines[0])[0].ink, "a highlight, not the border")
    }

    @Test("Under the default control style a glass button keeps its glass's rim, where other buttons are filled")
    func defaultKeepsTheRim() {
        let glass = unfocused(Button("OK") {}.buttonStyle(.glass))
        let lines = unfocused(Button("OK") {}.buttonStyle(.glass).controlStyle(.lines))
        #expect(glass.lines == lines.lines)
        let bordered = unfocused(Button("OK") {}.buttonStyle(.bordered))
        #expect(paintedCells(bordered.lines[0])[0].glyph == TerminalSymbols.openCap, "the others are filled")
    }

    @Test("In filled faces, a glass button's face is the bordered button's own")
    func solidFaceIsTheBorderedOne() {
        let glass = unfocused(Button("OK") {}.buttonStyle(.glass).controlStyle(.block))
        let bordered = unfocused(Button("OK") {}.buttonStyle(.bordered).controlStyle(.block))
        #expect(glass.lines.map(\.stripped) == bordered.lines.map(\.stripped))
        let cap = paintedCells(glass.lines[0])[0]
        #expect(cap.glyph == TerminalSymbols.openCap)
        #expect(cap.ink == paintedCells(bordered.lines[0])[0].ink)
    }

    @Test("In lines, a glass button's label sits on the glass: what is behind shows through, tinted")
    func labelOnGlass() {
        func field(_ view: some View) -> String {
            paintedCells(screen(view.controlStyle(.lines)).lines[0])[2].background
        }
        let glass = field(Button("OK") {}.buttonStyle(.glass).background(Color.red))
        let material = field(
            Button("OK") {}.buttonStyle(.bordered).background(Color.palette.background.opacity(0.65)).background(Color.red))
        #expect(glass == material)
        let clear = field(Button("OK") {}.buttonStyle(.glass(.clear)).background(Color.red))
        let thin = field(
            Button("OK") {}.buttonStyle(.bordered).background(Color.palette.background.opacity(0.35)).background(Color.red))
        #expect(clear == thin)
        #expect(clear != glass)
    }

    @Test("A prominent glass button is on glass tinted the accent, its label bold")
    func prominent() {
        let drawn = screen(Button("OK") {}.buttonStyle(.glassProminent))
        let field = paintedCells(drawn.lines[0])[2].background
        let tinted = paintedCells(
            screen(
                Button("OK") {}.buttonStyle(.bordered).controlStyle(.lines)
                    .background(Color.palette.accent.opacity(0.65))
            ).lines[0])[2]
            .background
        #expect(field == tinted)
        let bold = /\u{1B}\[(?:[0-9]+;)*1(?:;[0-9]+)*m/
        #expect(drawn.lines[0].contains(bold), "\(drawn.lines[0].debugDescription)")
    }

    @Test("Focused, a prominent glass button's label keeps its colour on the tint; the accent would vanish into it")
    func prominentLabelDoesNotBreatheIntoTheTint() {
        func labelInk(focused: Bool) -> SGRState.Colour? {
            let context = context()
            if !focused { context.environment.focusManager?.register(FocusSentinel()) }
            return paintedCells(screen(Button("OK") {}.buttonStyle(.glassProminent), context: context).lines[0])[2].ink
        }
        let focused = labelInk(focused: true)
        #expect(focused == labelInk(focused: false))
        #expect(focused != ink(.palette.accent))
    }

    @Test("A glass button is still a button: one focus stop, and the keyboard triggers it")
    func stillAButton() throws {
        var count = 0
        let context = context()
        _ = screen(Button("OK") { count += 1 }.buttonStyle(.glass), context: context)
        let focus = try #require(context.environment.focusManager)
        #expect(focus.currentFocusedID != nil)
        #expect(focus.dispatchKeyEvent(KeyEvent(key: .enter)))
        #expect(count == 1)
    }

    @Test("The styles compare as their glass")
    func equality() {
        #expect(GlassButtonStyle() == .glass)
        #expect(GlassButtonStyle(.clear) == .glass(.clear))
        #expect(GlassButtonStyle(.clear) != GlassButtonStyle())
        #expect(GlassProminentButtonStyle() == .glassProminent)
    }
}
