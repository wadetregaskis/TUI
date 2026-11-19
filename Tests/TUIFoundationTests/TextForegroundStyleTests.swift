//  🖥️ TUI — A Terminal UI framework for Swift
//  TextForegroundStyleTests.swift
//
//  `Text`'s own `foregroundStyle(_:) -> Text`, generic over `ShapeStyle` as
//  SwiftUI's is: a content level resolves where the text is drawn, against the
//  style in force there and not a level `foregroundStyle(_:_:)` names (measured
//  on macOS 15.8.3: `Tools/SwiftUIProbes/Text foregroundStyle levels (TXTFG)/`),
//  and any other style resolves there too, the text still a `Text`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("Text's own foregroundStyle resolves where the text is drawn")
struct TextForegroundStyleTests {

    private func drawn<V: View>(_ view: V) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: 12, availableHeight: 1, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    // MARK: - Content levels

    /// SwiftUI draws #FF9C96, red at the secondary level, where the swatch of
    /// `.red.secondary` is #FF9C97. Before, `.secondary` here was
    /// `Color.secondary`, the palette's fixed tier, whatever the style above.
    @Test("Under a style, a text's own .secondary is that style at the secondary level")
    func secondaryOfTheStyleAbove() {
        let own = drawn(VStack { Text("Subtitle").foregroundStyle(.secondary) }.foregroundStyle(.red))
        let expected = drawn(VStack { Text("Subtitle") }.foregroundStyle(.red.secondary))
        let tier = drawn(VStack { Text("Subtitle").foregroundStyle(Color.secondary) }.foregroundStyle(.red))
        #expect(expected != tier, "precondition: the secondary red is not the palette's tier")
        #expect(own == expected, "\(own.lines) against \(expected.lines)")
    }

    @Test("Each level fades the style above as macOS's label colours do")
    func everyLevel() {
        let levels: [(own: HierarchicalShapeStyle, expected: AnyShapeStyle)] = [
            (.primary, AnyShapeStyle(Color.red)), (.tertiary, AnyShapeStyle(Color.red.tertiary)),
            (.quaternary, AnyShapeStyle(Color.red.quaternary)), (.quinary, AnyShapeStyle(Color.red.quinary)),
        ]
        for (own, expected) in levels {
            let text = drawn(VStack { Text("Level").foregroundStyle(own) }.foregroundStyle(.red))
            let reference = drawn(VStack { Text("Level") }.foregroundStyle(expected))
            #expect(text == reference, "level \(own.level): \(text.lines) against \(reference.lines)")
        }
    }

    /// The view modifier's `.secondary` draws the named blue; the text's own
    /// draws the primary at the secondary level, as SwiftUI's does (#FF9C96).
    @Test("A secondary named by foregroundStyle(_:_:) plays no part in a text's own level")
    func namedSecondaryIgnored() {
        let own = drawn(VStack { Text("Subtitle").foregroundStyle(.secondary) }.foregroundStyle(.red, .blue))
        let expected = drawn(VStack { Text("Subtitle") }.foregroundStyle(.red.secondary))
        let viewModifier = drawn(VStack { Text("Subtitle").padding(0).foregroundStyle(.secondary) }
            .foregroundStyle(.red, .blue))
        #expect(own == expected, "\(own.lines) against \(expected.lines)")
        #expect(own.lines != viewModifier.lines, "the view modifier's .secondary is the named blue")
    }

    @Test("With no style above, a text's own level is the palette's tier, as before")
    func paletteTierWithNoStyle() {
        #expect(drawn(Text("Subtitle").foregroundStyle(.secondary))
            == drawn(Text("Subtitle").foregroundStyle(Color.secondary)))
        #expect(drawn(Text("Subtitle").foregroundStyle(.tertiary))
            == drawn(Text("Subtitle").foregroundStyle(Color.palette.foregroundTertiary)))
    }

    @Test("A fragment's own level is a level of the style the text draws in")
    func fragmentLevel() {
        let red = asDrawn(.red)
        let own = drawn(VStack { Text("Plain \(Text("second").foregroundStyle(.secondary))") }.foregroundStyle(.red))
        let expected = drawn(
            VStack { Text("Plain \(Text("second").foregroundStyle(red.opacity(0.5)))") }.foregroundStyle(.red))
        #expect(own == expected, "\(own.lines) against \(expected.lines)")
        let plain = drawn(Text("Plain \(Text("second").foregroundStyle(.secondary))"))
        let tier = drawn(Text("Plain \(Text("second").foregroundStyle(Color.secondary))"))
        #expect(plain == tier, "with no style above, the palette's tier")
    }

    // MARK: - Other styles

    @Test("Any other style is resolved where the text is drawn, and the text is still a Text")
    func otherStylesStayText() {
        let tinted = Text("Tint").foregroundStyle(.tint) as Text
        #expect(drawn(VStack { tinted }.tint(.green)) == drawn(VStack { Text("Tint").foregroundStyle(.green) }))
        let joined = Text("Plain \(Text("tint").foregroundStyle(.tint))") as Text
        #expect(drawn(VStack { joined }.tint(.green))
            == drawn(VStack { Text("Plain \(Text("tint").foregroundStyle(.green))") }))
    }

    @Test("A gradient on a text draws as the view modifier draws it, a ramp across the text")
    func gradientRamp() {
        let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
        let own = drawn(Text("Gradient").foregroundStyle(gradient))
        let modifier = drawn(Group { Text("Gradient") }.foregroundStyle(gradient))
        #expect(own == modifier, "\(own.lines) against \(modifier.lines)")
    }

    /// Every kind of style a text can carry draws as the view modifier draws
    /// it around the text, under a stated style, tint and background style for
    /// the ones that read them. Each is passed as its own type, so a level
    /// takes the level's path. (An image is `ImagePaintTests`'.)
    @Test("Every other style on a text draws as the view modifier draws it")
    func everyStyleAsTheModifier() {
        func check(_ name: String, _ style: some ShapeStyle) {
            func around(_ text: some View) -> some View {
                VStack { text }.foregroundStyle(.red).tint(.green).backgroundStyle(.blue)
            }
            let own = drawn(around(Text("Styled").foregroundStyle(style)))
            let modifier = drawn(around(Group { Text("Styled") }.foregroundStyle(style)))
            #expect(own == modifier, "\(name): \(own.lines) against \(modifier.lines)")
        }
        let colors: [Color] = [.red, .blue]
        check("angular", AngularGradient(colors: colors, center: .center))
        check("elliptical", EllipticalGradient(colors: colors))
        check("radial", RadialGradient(colors: colors, center: .center, startRadius: 0, endRadius: 4))
        check("secondary", HierarchicalShapeStyle.secondary)
        check("quinary", HierarchicalShapeStyle.quinary)
        check("green.tertiary", Color.green.tertiary)
        check("gradient.secondary", LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing).secondary)
        check("tint", TintShapeStyle.tint)
        check("selection", SelectionShapeStyle.selection)
        check("thin material", Material.thin)
        check("foreground", ForegroundStyle())
        check("background", BackgroundStyle())
    }

    /// The SGR in force where `character` is drawn on `line`: the last one
    /// before it.
    private func sgr(before character: Character, in line: String) -> String? {
        guard let index = line.firstIndex(of: character) else { return nil }
        let before = line[..<index]
        return before.range(of: "\u{1B}[", options: .backwards).map { String(before[$0.lowerBound...]) }
    }

    @Test("A gradient on one fragment bands across the text, over that fragment alone")
    func fragmentGradient() throws {
        let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
        let own = try #require(drawn(Text("ab\(Text("cd").foregroundStyle(gradient))")).lines.first)
        let whole = try #require(drawn(Group { Text("ab\(Text("cd"))") }.foregroundStyle(gradient)).lines.first)
        #expect(sgr(before: "c", in: own) == sgr(before: "c", in: whole), "\(own.debugDescription)")
        #expect(sgr(before: "d", in: own) == sgr(before: "d", in: whole), "\(own.debugDescription)")
        #expect(sgr(before: "c", in: own) != sgr(before: "d", in: own), "a ramp, not one colour")
        #expect(sgr(before: "a", in: own) != sgr(before: "a", in: whole), "the plain fragment keeps its own ink")
    }

    @Test("The last style a text states wins, a colour after another style included")
    func lastStyleWins() {
        let red = drawn(Text("Ink").foregroundStyle(Color.red))
        #expect(drawn(Text("Ink").foregroundStyle(.tint).foregroundStyle(.red)) == red)
        #expect(drawn(VStack { Text("Ink").foregroundStyle(.secondary).foregroundStyle(.red) }
            .foregroundStyle(.blue)) == red)
    }

    @Test("A colour named only on Color still reads with a leading dot")
    func colourSpellings() {
        let accent = Text("Accent").foregroundStyle(.palette.accent) as Text
        #expect(drawn(accent) == drawn(Text("Accent").foregroundStyle(Color.palette.accent)))
    }
}
