//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SemanticShapeStyleTests.swift
//
//  The shape styles that name a role: the content levels, with and without a
//  foreground style above them, and the roles' palette answers.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

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

    private func ink(_ colour: Color) -> String {
        colour.foregroundCodes().joined(separator: ";")
    }

    // MARK: - Levels

    @Test("With no foreground style, the levels are the palette's tiers")
    func paletteTiers() {
        let environment = environment()
        let palette = environment.palette
        #expect(HierarchicalShapeStyle.primary.paint(in: environment) == .color(palette.foreground))
        #expect(HierarchicalShapeStyle.secondary.paint(in: environment) == .color(palette.foregroundSecondary))
        #expect(HierarchicalShapeStyle.tertiary.paint(in: environment) == .color(palette.foregroundTertiary))
        #expect(HierarchicalShapeStyle.quaternary.paint(in: environment) == .color(palette.foregroundQuaternary))
    }

    @Test("Under a foreground style, the levels are it at falling opacity")
    func levelsOfTheForeground() {
        var environment = environment()
        environment.foregroundStyle = .color(.red)
        #expect(HierarchicalShapeStyle.primary.paint(in: environment) == .color(.red))
        #expect(HierarchicalShapeStyle.secondary.paint(in: environment) == .color(Color.red.opacity(0.5)))
        #expect(HierarchicalShapeStyle.tertiary.paint(in: environment) == .color(Color.red.opacity(0.26)))
    }

    @Test("A named level answers for itself and fades for the ones past it")
    func namedLevels() {
        var environment = environment()
        environment.foregroundStyle = .color(.red)
        environment.secondaryForegroundStyle = .color(.blue)
        #expect(HierarchicalShapeStyle.secondary.paint(in: environment) == .color(.blue))
        #expect(HierarchicalShapeStyle.tertiary.paint(in: environment) == .color(Color.blue.opacity(0.5)))
        environment.tertiaryForegroundStyle = .color(.green)
        #expect(HierarchicalShapeStyle.tertiary.paint(in: environment) == .color(.green))
    }

    @Test("A style's own levels fade it: .red.secondary is red at half strength")
    func levelsOfAStyle() {
        #expect(Color.red.secondary.paint(in: environment()) == .color(Color.red.opacity(0.5)))
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

    // MARK: - Roles

    @Test("The roles answer from the palette and the environment")
    func roles() {
        var environment = environment()
        let palette = environment.palette
        #expect(ForegroundStyle().paint(in: environment) == .color(palette.foreground))
        #expect(SeparatorShapeStyle().paint(in: environment) == .color(palette.border))
        #expect(FillShapeStyle().paint(in: environment) == .color(palette.fieldBackground))
        #expect(PlaceholderTextShapeStyle().paint(in: environment) == .color(palette.foregroundTertiary))
        #expect(WindowBackgroundShapeStyle().paint(in: environment) == .color(palette.background))
        #expect(TintShapeStyle().paint(in: environment) == .color(palette.accent))
        environment.tint = .rgb(1, 2, 3)
        environment.foregroundStyle = .color(.red)
        #expect(TintShapeStyle().paint(in: environment) == .color(.rgb(1, 2, 3)))
        #expect(SelectionShapeStyle().paint(in: environment) == .color(.rgb(1, 2, 3)))
        #expect(ForegroundStyle().paint(in: environment) == .color(.red))
    }

    @Test("The named colours are reachable as shape styles")
    func namedColours() {
        let style: some ShapeStyle = .teal
        #expect(style.paint(in: environment()) == Color.teal.paint(in: environment()))
    }
}
