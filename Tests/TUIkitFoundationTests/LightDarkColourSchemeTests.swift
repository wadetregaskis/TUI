//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LightDarkColourSchemeTests.swift
//
//  A colour with light and dark values of its own (an asset catalogue's colour
//  set, a dynamic `NSColor`) drawn by the colour scheme in force where it is
//  drawn: a palette's, or a `.colorScheme` pin's, in either direction, as a
//  named colour is (NamedColourSchemeTests).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport
@testable import TUIkitView

/// A palette that states nothing but a page (and the roles with no default).
private struct LightDarkPagePalette: Palette, Hashable {
    let id = "light-dark-page"
    let name = "Light-dark page"
    var background: Color
    let foreground = Color.rgb(128, 128, 128)
    let accent = Color.rgb(0, 200, 0)
    let success = Color.rgb(0, 200, 0)
    let warning = Color.rgb(200, 200, 0)
    let error = Color.rgb(200, 0, 0)
    let info = Color.rgb(0, 200, 200)
    let border = Color.rgb(100, 100, 100)
}

@MainActor
@Suite("Light-and-dark colours follow the colour scheme where they are drawn")
struct LightDarkColourSchemeTests {

    private static let darkPage = LightDarkPagePalette(background: .rgb(10, 10, 10))
    private static let lightPage = LightDarkPagePalette(background: .rgb(250, 250, 250))

    /// An asset colour, as a colour set with a dark variant makes one.
    private static let brand = Color.lightDark(light: .rgb(204, 102, 51), dark: .rgb(16, 128, 255))!
    private static let lightInk = "38;2;204;102;51"
    private static let darkInk = "38;2;16;128;255"
    private static let lightFill = "48;2;204;102;51"
    private static let darkFill = "48;2;16;128;255"

    private func lines(_ view: some View) -> [String] {
        ColorDepth.withCurrent(.truecolor) {
            renderToBuffer(view, context: makeBareRenderContext()).lines
        }
    }

    @Test("A light page draws the light variant, a dark page the dark one")
    func byPalette() {
        let light = lines(Text("Hi").foregroundStyle(Self.brand).palette(Self.lightPage)).joined()
        let dark = lines(Text("Hi").foregroundStyle(Self.brand).palette(Self.darkPage)).joined()
        #expect(light.contains(Self.lightInk), "\(light.debugDescription)")
        #expect(dark.contains(Self.darkInk), "\(dark.debugDescription)")
    }

    @Test("A dark subtree inside a light app draws the dark variant")
    func darkSubtreeInLightApp() {
        let drawn = lines(
            VStack {
                Text("Outer").foregroundStyle(Self.brand)
                Text("Inner").foregroundStyle(Self.brand).environment(\.colorScheme, .dark)
            }
            .palette(Self.lightPage))
        #expect(drawn.count >= 2)
        #expect(drawn[0].contains(Self.lightInk), "\(drawn[0].debugDescription)")
        #expect(drawn[1].contains(Self.darkInk), "\(drawn[1].debugDescription)")
    }

    @Test("A light subtree inside a dark app draws the light variant")
    func lightSubtreeInDarkApp() {
        let drawn = lines(
            VStack {
                Text("Outer").foregroundStyle(Self.brand)
                Text("Inner").foregroundStyle(Self.brand).environment(\.colorScheme, .light)
            }
            .palette(Self.darkPage))
        #expect(drawn.count >= 2)
        #expect(drawn[0].contains(Self.darkInk), "\(drawn[0].debugDescription)")
        #expect(drawn[1].contains(Self.lightInk), "\(drawn[1].debugDescription)")
    }

    /// Made ABOVE the pin and drawn below it, which choosing by the scheme where
    /// the body runs (B-D6M-1's option 4) would have got wrong.
    @Test("A colour made above a pin and drawn below it takes the pinned scheme")
    func madeAbovePinDrawnBelow() {
        let colour = Self.brand
        let fill = lines(Text("Hi").background(colour).environment(\.colorScheme, .dark).palette(Self.lightPage))
            .joined()
        #expect(fill.contains(Self.darkFill), "\(fill.debugDescription)")
        let lightFill = lines(Text("Hi").background(colour).palette(Self.lightPage)).joined()
        #expect(lightFill.contains(Self.lightFill), "\(lightFill.debugDescription)")
    }

    @Test("resolve(in:) answers each environment's variant")
    func resolveInEnvironment() {
        var environment = EnvironmentValues()
        environment.palette = Self.lightPage
        #expect(Color(Self.brand.resolve(in: environment)) == .rgb(204, 102, 51))
        environment.colorScheme = .dark
        #expect(Color(Self.brand.resolve(in: environment)) == .rgb(16, 128, 255))
        environment.palette = Self.darkPage
        environment.colorScheme = .light
        #expect(Color(Self.brand.resolve(in: environment)) == .rgb(204, 102, 51))
    }
}
