//  🖥️ TUI — A Terminal UI framework for Swift
//  GlassEffectTests.swift
//
//  Glass as a material's surface with a highlighted rim (refusal review O5
//  (b), Deliberate deviations C11): the variants, the surface, the rim in each
//  appearance's lines, the rim behind the content, interactive glass under the
//  pointer, and tinted glass as the ground of what is on it.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("Glass")
struct GlassEffectTests {

    private func context(width: Int, height: Int, appearance: Appearance = .rounded, active: Bool = true) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, _ in
            environment.palette = SystemPalette.green
            environment.appearance = appearance
            environment.appearsActive = active
        }
    }

    /// A context drawing through `tui`'s own render cache and pointer, so a
    /// hover's state write reaches the next frame — `makeRenderContext` isolates
    /// the cache from the state's invalidation.
    private func pointerContext(_ tui: TUIContext) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.palette = SystemPalette.green
        environment.mouseEventDispatcher = tui.mouseEventDispatcher
        return RenderContext(availableWidth: 6, availableHeight: 3, environment: environment, tuiContext: tui)
    }

    private func screen(
        _ view: some View, width: Int, height: Int, appearance: Appearance = .rounded, active: Bool = true
    ) -> [String] {
        ColorDepth.withCurrent(.truecolor) {
            renderToScreen(view, context: context(width: width, height: height, appearance: appearance, active: active))
                .lines
        }
    }

    private func environment(active: Bool = true) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        environment.appearsActive = active
        return environment
    }

    /// The ink `colour` is drawn in at 24-bit depth, as a cell reads it back.
    private func ink(_ colour: Color) -> SGRState.Colour? {
        colour.resolve(with: SystemPalette.green).rgbComponents.map { .rgb(Int($0.red), Int($0.green), Int($0.blue)) }
    }

    // MARK: - The type

    @Test("Glass compares as its variant, tint and interactivity")
    func equality() {
        #expect(Glass.regular == .regular)
        #expect(Glass.regular != .clear && Glass.clear != .identity && Glass.regular != .identity)
        #expect(Glass.regular.tint(.red) != .regular)
        #expect(Glass.regular.tint(.red).tint(nil) == .regular)
        #expect(Glass.regular.interactive() != .regular)
        #expect(Glass.regular.interactive().interactive(false) == .regular)
        #expect(Glass.clear.tint(.blue).interactive() == Glass.clear.interactive().tint(.blue))
    }

    @Test("Regular glass is the regular material's surface, clear glass the ultra-thin one's")
    func surfaceIsAMaterial() {
        #expect(Glass.regular.surface(in: environment()) == Color.palette.background.opacity(0.65))
        #expect(Glass.clear.surface(in: environment()) == Color.palette.background.opacity(0.35))
        #expect(Glass.regular.tint(.blue).surface(in: environment()) == Color.blue.opacity(0.65))
        #expect(Glass.clear.tint(.blue).surface(in: environment()) == Color.blue.opacity(0.35))
    }

    @Test("Glass that does not appear active is its surface at full strength, as a material is")
    func inactiveIsOpaque() {
        #expect(Glass.regular.surface(in: environment(active: false)) == Color.palette.background)
        #expect(Glass.clear.tint(.blue).surface(in: environment(active: false)) == Color.blue)
    }

    @Test("The default glass shape is a capsule")
    func defaultShape() {
        let rect = CGRect(x: 0, y: 0, width: 12, height: 6)
        #expect(DefaultGlassEffectShape().path(in: rect) == Capsule().path(in: rect))
    }

    // MARK: - The rim

    @Test("A padded view on glass is rimmed in the appearance's lines")
    func rimInEachAppearance() {
        let view = Text("Flag").padding().glassEffect()
        func rim(_ appearance: Appearance) -> [String] {
            screen(view, width: 6, height: 3, appearance: appearance).map(\.stripped)
        }
        #expect(rim(.rounded) == ["╭────╮", "│Flag│", "╰────╯"])
        // A light style takes the shape's corners: a capsule is rounded.
        #expect(rim(.line) == ["╭────╮", "│Flag│", "╰────╯"])
        #expect(rim(.heavy) == ["┏━━━━┓", "┃Flag┃", "┗━━━━┛"])
        #expect(rim(.doubleLine) == ["╔════╗", "║Flag║", "╚════╝"])
        // No rim: the surface alone, its rounded corners quadrants of it.
        let blank = rim(.blank)
        #expect(blank[1] == " Flag ")
        #expect((blank[0] + blank[2]).allSatisfy { $0 == " " || TerminalSymbols.quadrants.contains($0) }, "\(blank)")
        let braille = rim(.braille)
        #expect(braille[1].first.map(Self.isBraille) == true && braille[1].last.map(Self.isBraille) == true, "\(braille)")
        #expect(braille[0].allSatisfy { $0 == " " || Self.isBraille($0) } && braille[0].contains(where: Self.isBraille))
    }

    @Test("A square glass takes square corners in light lines")
    func squareCorners() {
        let lines = screen(Text("Flag").padding().glassEffect(in: Rectangle()), width: 6, height: 3).map(\.stripped)
        #expect(lines == ["┌────┐", "│Flag│", "└────┘"])
    }

    @Test("One row of glass is rimmed by its ends")
    func oneRow() {
        let capsule = screen(Text("Flag").padding(.horizontal).glassEffect(), width: 6, height: 1)
        #expect(capsule.map(\.stripped) == ["(Flag)"])
        let square = screen(Text("Flag").padding(.horizontal).glassEffect(in: Rectangle()), width: 6, height: 1)
        #expect(square.map(\.stripped) == ["[Flag]"])
    }

    @Test("The rim is behind the content: where the view draws a glyph, the glyph is the view's")
    func rimIsBehind() {
        #expect(screen(Text("Flag").glassEffect(), width: 4, height: 1).map(\.stripped) == ["Flag"])
    }

    @Test("Under a solid appearance the rim is a band of its colour round the surface")
    func solidBand() {
        let view = Text("Flag").padding().glassEffect(in: Rectangle())
        let lines = screen(view, width: 6, height: 3, appearance: .block)
        let rim = Glass.regular.rimInk(hovered: false, in: renderEnvironment(.block))
        let band = renderedBackground(of: rim)
        let top = paintedCells(lines[0])
        #expect(top.allSatisfy { $0.background == band }, "\(lines[0].debugDescription)")
        let middle = paintedCells(lines[1])
        #expect(middle.first?.background == band && middle.last?.background == band)
        #expect(middle[2].background != band, "the surface inside the band is the glass's")
    }

    @Test("The rim is a highlighted border: the border's ink lifted, and lifted again under the pointer")
    func rimIsHighlighted() {
        let lines = screen(Text("Flag").padding().glassEffect(), width: 6, height: 3)
        let rimInk = paintedCells(lines[0])[1].ink
        let environment = renderEnvironment(.rounded)
        let border = environment.palette.border.resolve(with: environment.palette)
        #expect(rimInk == ink(Glass.regular.rimInk(hovered: false, in: environment)))
        #expect(rimInk != ink(border), "a highlight, not the border")
        #expect(
            Glass.regular.rimInk(hovered: true, in: environment) != Glass.regular.rimInk(hovered: false, in: environment))
    }

    @Test("A shape outside the rectangle family is rimmed by its border, or in dots under Braille")
    func otherShapes() {
        let circle = Color.clear.frame(width: 10, height: 5).glassEffect(in: Circle())
        let lines = screen(circle, width: 10, height: 5).map(\.stripped)
        #expect(lines[0].contains { "▀▄█".contains($0) }, "\(lines)")
        let dotted = screen(circle, width: 10, height: 5, appearance: .braille).map(\.stripped)
        #expect(dotted[0].contains(where: Self.isBraille), "\(dotted)")
    }

    // MARK: - The surface

    @Test("The surface composites over what is behind it: tinted, not covered")
    func surfaceComposites() {
        func cell(_ view: some View) -> String {
            paintedCells(screen(view, width: 4, height: 1)[0])[1].background
        }
        let glass = cell(Text("ab").padding(.horizontal).glassEffect(in: Rectangle()).background(Color.red))
        let material = cell(
            Text("ab").padding(.horizontal).background(Color.palette.background.opacity(0.65)).background(Color.red))
        #expect(glass == material)
        #expect(glass != cell(Text("ab").padding(.horizontal).background(Color.red)), "not absent")
        #expect(
            glass != cell(Text("ab").padding(.horizontal).background(Color.palette.background).background(Color.red)),
            "not opaque")
        let inactive = paintedCells(
            screen(
                Text("ab").padding(.horizontal).glassEffect(in: Rectangle()).background(Color.red), width: 4, height: 1,
                active: false)[0])[1].background
        #expect(inactive == renderedBackground(of: SystemPalette.green.background), "flat in an inactive window")
    }

    @Test("Tinted glass is the tint, translucent")
    func tinted() {
        func cell(_ view: some View) -> String {
            paintedCells(screen(view, width: 4, height: 1)[0])[1].background
        }
        let glass = cell(Text("ab").padding(.horizontal).glassEffect(.regular.tint(.blue), in: Rectangle()))
        #expect(glass == cell(Text("ab").padding(.horizontal).background(Color.blue.opacity(0.65))))
    }

    @Test("Identity glass draws nothing")
    func identity() {
        #expect(
            screen(Text("Flag").padding().glassEffect(.identity), width: 6, height: 3)
                == screen(Text("Flag").padding(), width: 6, height: 3))
    }

    @Test("With no colour the rim is glyphs alone, and there is no surface")
    func noColour() {
        let lines = ColorDepth.withCurrent(.noColor) {
            renderToScreen(Text("Flag").padding().glassEffect(), context: context(width: 6, height: 3)).lines
        }
        #expect(lines.map(\.stripped) == ["╭────╮", "│Flag│", "╰────╯"])
        #expect(lines.allSatisfy { !$0.contains("\u{1B}[4") && !$0.contains("\u{1B}[3") && !$0.contains(";2;") })
    }

    @Test("Tinted glass is the ground of what is on it; untinted glass leaves the ground alone")
    func tintedGround() {
        var onTinted: Color??
        var onPlain: Color??
        _ = screen(SurfaceReader { onTinted = $0 }.glassEffect(.regular.tint(.blue)), width: 4, height: 1)
        _ = screen(SurfaceReader { onPlain = $0 }.glassEffect(), width: 4, height: 1)
        let environment = renderEnvironment(.rounded)
        let expected = Color.blue.opacity(0.65).resolve(with: environment.palette)
            .spendingAlpha(over: environment.enclosingSurface)
        #expect(onTinted == .some(expected))
        #expect(onPlain == .some(nil))
    }

    // MARK: - Interactive glass

    @Test("Interactive glass lifts its rim while the pointer is over it; plain glass watches no pointer")
    func interactiveHover() {
        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        let view = Text("Flag").padding().glassEffect(.regular.interactive())
        let renderContext = pointerContext(tui)
        // Whole passes, the prune at the end of each included: the pointer's
        // record has to outlive the pass it was drawn in.
        func frame() -> FrameBuffer {
            dispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let buffer = ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: renderContext) }
            tui.renderCache.removeInactive()
            tui.stateStorage.endRenderPass()
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }
        let resting = frame()
        #expect(!resting.hitTestRegions.isEmpty)
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 2, y: 1))
        let hovered = frame()
        let environment = renderEnvironment(.rounded)
        #expect(paintedCells(resting.lines[0])[1].ink == ink(Glass.regular.rimInk(hovered: false, in: environment)))
        #expect(paintedCells(hovered.lines[0])[1].ink == ink(Glass.regular.rimInk(hovered: true, in: environment)))
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 30, y: 10))
        #expect(paintedCells(frame().lines[0])[1].ink == ink(Glass.regular.rimInk(hovered: false, in: environment)))

        let plain = ColorDepth.withCurrent(.truecolor) {
            renderToScreen(Text("Flag").padding().glassEffect(), context: pointerContext(TUIContext()))
        }
        #expect(plain.hitTestRegions.isEmpty)
    }

    @Test("Joined interactive glass lifts the whole shape's rim while the pointer is over any member, each part with it")
    func interactiveHoverJoined() {
        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        let view = GlassEffectContainer {
            HStack(spacing: 0) {
                Text("A").padding().glassEffect(.regular.interactive())
                Text("B").padding().glassEffect(.regular.interactive())
            }
        }
        let renderContext = pointerContext(tui)
        func frame() -> FrameBuffer {
            dispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let buffer = ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: renderContext) }
            tui.renderCache.removeInactive()
            tui.stateStorage.endRenderPass()
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }
        let environment = renderEnvironment(.rounded)
        let (resting, lifted) = (
            ink(Glass.regular.rimInk(hovered: false, in: environment)),
            ink(Glass.regular.rimInk(hovered: true, in: environment))
        )
        func rim(_ buffer: FrameBuffer) -> [SGRState.Colour?] {
            // The top row: A's part, then B's.
            [1, 4].map { paintedCells(buffer.lines[0])[$0].ink }
        }
        #expect(frame().lines.map(\.stripped) == ["╭────╮", "│A  B│", "╰────╯"])
        #expect(rim(frame()) == [resting, resting])
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 1, y: 1))
        #expect(rim(frame()) == [lifted, lifted], "over A: B's part lifts with it")
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 30, y: 10))
        #expect(rim(frame()) == [resting, resting])
    }

    // MARK: - Helpers

    /// The environment a render under `appearance` draws its glass in.
    private func renderEnvironment(_ appearance: Appearance) -> EnvironmentValues {
        context(width: 6, height: 3, appearance: appearance).environment
    }

    private static func isBraille(_ character: Character) -> Bool {
        character.unicodeScalars.first.map { (0x2801...0x28FF).contains($0.value) } ?? false
    }
}

/// Hands `read` the surface ink lands on, where a container painted one.
private struct SurfaceReader: View, Renderable {
    let read: (Color?) -> Void
    var body: Never { fatalError("renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring { read(context.environment.surfaceBackground) }
        return FrameBuffer(text: "ab")
    }
}
