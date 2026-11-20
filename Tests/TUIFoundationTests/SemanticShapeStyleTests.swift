//  🖥️ TUI — A Terminal UI framework for Swift
//  SemanticShapeStyleTests.swift
//
//  The shape styles that name a role: the content levels, with and without a
//  foreground style above them, and the roles' palette answers.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("Semantic shape styles")
struct SemanticShapeStyleTests {

    private func environment() -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        return environment
    }

    private func buffer<V: View>(_ view: V) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: 6, availableHeight: 1, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    /// `colour`'s ink as these renders draw it, under the palette none of them
    /// sets: a named colour is that palette's scheme's.
    private func ink(_ colour: Color) -> String {
        asDrawn(colour).foregroundCodes().joined(separator: ";")
    }

    // MARK: - Levels

    @Test("With no foreground style, the levels are the palette's tiers")
    func paletteTiers() {
        let environment = environment()
        let palette = environment.palette
        #expect(HierarchicalShapeStyle.primary.paint(in: environment) == Paint.color(palette.foreground))
        #expect(HierarchicalShapeStyle.secondary.paint(in: environment) == Paint.color(palette.foregroundSecondary))
        #expect(HierarchicalShapeStyle.tertiary.paint(in: environment) == Paint.color(palette.foregroundTertiary))
        #expect(HierarchicalShapeStyle.quaternary.paint(in: environment) == Paint.color(palette.foregroundQuaternary))
    }

    @Test("Under a foreground style, the levels are it at falling opacity")
    func levelsOfTheForeground() {
        var environment = environment()
        environment.foregroundStyle = .color(.red)
        #expect(HierarchicalShapeStyle.primary.paint(in: environment) == Paint.color(.red))
        #expect(HierarchicalShapeStyle.secondary.paint(in: environment) == Paint.color(Color.red.opacity(0.5)))
        #expect(HierarchicalShapeStyle.tertiary.paint(in: environment) == Paint.color(Color.red.opacity(0.26)))
    }

    @Test("A named level answers for itself and fades for the ones past it")
    func namedLevels() {
        var environment = environment()
        environment.foregroundStyle = .color(.red)
        environment.secondaryForegroundStyle = .color(.blue)
        #expect(HierarchicalShapeStyle.secondary.paint(in: environment) == Paint.color(.blue))
        #expect(HierarchicalShapeStyle.tertiary.paint(in: environment) == Paint.color(Color.blue.opacity(0.5)))
        environment.tertiaryForegroundStyle = .color(.green)
        #expect(HierarchicalShapeStyle.tertiary.paint(in: environment) == Paint.color(.green))
    }

    /// Painted, so resolved: red as this palette's scheme draws it, at half.
    @Test("A style's own levels fade it: .red.secondary is red at half strength")
    func levelsOfAStyle() {
        let environment = environment()
        let red = asDrawn(.red, in: environment.palette)
        #expect(Color.red.secondary.paint(in: environment) == Paint.color(red.opacity(0.5)))
    }

    @Test("foregroundStyle(_:_:) names the secondary level below it")
    func twoLevelModifier() {
        let drawn = buffer(
            VStack { Text("x") }
                .foregroundStyle(.secondary)
                .foregroundStyle(.red, .blue))
        #expect(drawn.lines[0].contains(ink(.blue)), "\(drawn.lines[0].debugDescription)")
    }

    @Test("A single foregroundStyle below clears the levels named above it")
    func singleStyleClearsLevels() {
        let drawn = buffer(
            VStack { Text("x") }
                .foregroundStyle(.secondary)
                .foregroundStyle(Color.green)
                .foregroundStyle(.red, .blue))
        #expect(!drawn.lines[0].contains(ink(.blue)), "\(drawn.lines[0].debugDescription)")
    }

    /// Measured (`Tools/SwiftUIProbes/Text foregroundStyle levels (TXTFG)/variants.out`):
    /// a view's level under a view's level replaces it, a level of the style
    /// the outer one was a level of — the plain levels under a level of none,
    /// red's under a level of red or `.red.secondary`. A shape's level too.
    @Test("A view's level under a view's level replaces it, as SwiftUI's does")
    func levelUnderALevel() {
        let outers = [HierarchicalShapeStyle.secondary, .tertiary, .quaternary]
        for outer in outers {
            for inner in [HierarchicalShapeStyle.primary, .secondary, .tertiary, .quaternary] {
                let alone = buffer(VStack { Text("x") }.foregroundStyle(inner))
                #expect(buffer(VStack { Text("x") }.foregroundStyle(inner).foregroundStyle(outer)) == alone,
                    "\(inner.level) under \(outer.level)")
                let red = buffer(VStack { Text("x") }.foregroundStyle(inner).foregroundStyle(.red))
                #expect(buffer(VStack { Text("x") }.foregroundStyle(inner).foregroundStyle(outer)
                    .foregroundStyle(.red)) == red, "\(inner.level) under \(outer.level) under red")
                #expect(buffer(VStack { Text("x") }.foregroundStyle(inner).foregroundStyle(.red.secondary)) == red,
                    "\(inner.level) under red.secondary")
            }
        }
        #expect(buffer(VStack { Text("x") }.foregroundStyle(.secondary).foregroundStyle(.red))
            != buffer(VStack { Text("x") }.foregroundStyle(.red)), "precondition: a level of red is not red")
        // Under `(.red, .blue)`: the primary red, the secondary the named blue.
        let named = VStack { Text("x") }.foregroundStyle(.secondary)
        #expect(buffer(VStack { named }.foregroundStyle(.secondary).foregroundStyle(.red, .blue))
            == buffer(VStack { Text("x") }.foregroundStyle(.blue)))
        #expect(buffer(VStack { VStack { Text("x") }.foregroundStyle(.primary) }.foregroundStyle(.secondary)
            .foregroundStyle(.red, .blue)) == buffer(VStack { Text("x") }.foregroundStyle(.red)))
        // A shape's level, likewise.
        let shape = Rectangle().fill(.secondary).frame(width: 3, height: 1)
        #expect(buffer(VStack { shape }.foregroundStyle(.secondary).foregroundStyle(.red))
            == buffer(VStack { shape }.foregroundStyle(.red)))
    }

    // MARK: - Roles

    @Test("The roles answer from the palette and the environment")
    func roles() {
        var environment = environment()
        let palette = environment.palette
        #expect(ForegroundStyle().paint(in: environment) == Paint.color(palette.foreground))
        #expect(SeparatorShapeStyle().paint(in: environment) == Paint.color(palette.border))
        #expect(FillShapeStyle().paint(in: environment) == Paint.color(palette.fieldBackground))
        #expect(PlaceholderTextShapeStyle().paint(in: environment) == Paint.color(palette.foregroundTertiary))
        #expect(WindowBackgroundShapeStyle().paint(in: environment) == Paint.color(palette.background))
        #expect(TintShapeStyle().paint(in: environment) == Paint.color(palette.accent))
        environment.tint = .rgb(1, 2, 3)
        environment.foregroundStyle = .color(.red)
        #expect(TintShapeStyle().paint(in: environment) == Paint.color(.rgb(1, 2, 3)))
        #expect(SelectionShapeStyle().paint(in: environment) == Paint.color(.rgb(1, 2, 3)))
        #expect(ForegroundStyle().paint(in: environment) == Paint.color(.red))
    }

    @Test("The named colours are reachable as shape styles")
    func namedColours() {
        let style: some ShapeStyle = .teal
        #expect(style.paint(in: environment()) == Color.teal.paint(in: environment()))
    }
}
