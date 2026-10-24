//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NamedColourSchemeTests.swift
//
//  SwiftUI's named colours drawn by the colour scheme in force where they are
//  drawn: a palette's, or a `.colorScheme` pin's, in either direction.
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
private struct SchemePagePalette: Palette, Hashable {
    let id = "scheme-page"
    let name = "Scheme page"
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
@Suite("Named colours follow the colour scheme where they are drawn")
struct NamedColourSchemeTests {

    private static let darkPage = SchemePagePalette(background: .rgb(10, 10, 10))
    private static let lightPage = SchemePagePalette(background: .rgb(250, 250, 250))

    /// Apple's red, light and dark, as a truecolor foreground and background.
    private static let lightRedInk = "38;2;255;59;48"
    private static let darkRedInk = "38;2;255;69;58"
    private static let lightBlueFill = "48;2;0;122;255"
    private static let darkBlueFill = "48;2;10;132;255"

    private func rendered(_ view: some View) -> String {
        ColorDepth.withCurrent(.truecolor) {
            renderToBuffer(view, context: makeBareRenderContext()).lines.joined()
        }
    }

    @Test("A light page draws the light value, a dark page the dark one")
    func byPalette() {
        let light = rendered(Text("Hi").foregroundStyle(.red).palette(Self.lightPage))
        let dark = rendered(Text("Hi").foregroundStyle(.red).palette(Self.darkPage))
        #expect(light.contains(Self.lightRedInk), "\(light.debugDescription)")
        #expect(dark.contains(Self.darkRedInk), "\(dark.debugDescription)")
        #expect(!dark.contains(Self.lightRedInk))
    }

    @Test("A dark subtree inside a light app draws the dark value")
    func darkSubtreeInLightApp() {
        let view = VStack {
            Text("Outer").foregroundStyle(.red)
            Text("Inner").foregroundStyle(.red).environment(\.colorScheme, .dark)
        }
        .palette(Self.lightPage)
        let lines = ColorDepth.withCurrent(.truecolor) {
            renderToBuffer(view, context: makeBareRenderContext()).lines
        }
        #expect(lines.count >= 2)
        #expect(lines[0].contains(Self.lightRedInk), "\(lines[0].debugDescription)")
        #expect(lines[1].contains(Self.darkRedInk), "\(lines[1].debugDescription)")
    }

    @Test("A light subtree inside a dark app draws the light value")
    func lightSubtreeInDarkApp() {
        let view = VStack {
            Text("Outer").foregroundStyle(.red)
            Text("Inner").foregroundStyle(.red).environment(\.colorScheme, .light)
        }
        .palette(Self.darkPage)
        let lines = ColorDepth.withCurrent(.truecolor) {
            renderToBuffer(view, context: makeBareRenderContext()).lines
        }
        #expect(lines.count >= 2)
        #expect(lines[0].contains(Self.darkRedInk), "\(lines[0].debugDescription)")
        #expect(lines[1].contains(Self.lightRedInk), "\(lines[1].debugDescription)")
    }

    /// The environment's style and a fill resolve where they are painted, so a named
    /// colour given either way takes the scheme of the subtree it is painted in.
    @Test("A named foreground style and fill follow a pin")
    func stylesFollowAPin() {
        let ink = rendered(
            HStack { Text("Hi") }.foregroundStyle(Color.red).environment(\.colorScheme, .dark).palette(Self.lightPage))
        #expect(ink.contains(Self.darkRedInk), "\(ink.debugDescription)")
        let fill = rendered(Text("Hi").background(Color.blue).environment(\.colorScheme, .dark).palette(Self.lightPage))
        #expect(fill.contains(Self.darkBlueFill), "\(fill.debugDescription)")
        let lightFill = rendered(Text("Hi").background(Color.blue).palette(Self.lightPage))
        #expect(lightFill.contains(Self.lightBlueFill), "\(lightFill.debugDescription)")
    }

    @Test("At 256 colours a dark subtree draws the entry nearest the dark value")
    func palette256InAPinnedSubtree() {
        // Orange is #FF9500 (208) light and #FF9F0A (214) dark.
        let view = Text("Hi").foregroundStyle(.orange).environment(\.colorScheme, .dark).palette(Self.lightPage)
        let drawn = ColorDepth.withCurrent(.palette256) {
            renderToBuffer(view, context: makeBareRenderContext()).lines.joined()
        }
        #expect(drawn.contains("38;5;214"), "\(drawn.debugDescription)")
        #expect(!drawn.contains("38;5;208"))
    }

    /// `resolve(in:)` answers per environment: the scheme of the palette in force,
    /// pinned or not.
    @Test("resolve(in:) answers each environment's value")
    func resolveInEnvironment() {
        var environment = EnvironmentValues()
        environment.palette = Self.lightPage
        #expect(Color(Color.red.resolve(in: environment)) == .rgb(0xFF, 0x3B, 0x30))
        environment.colorScheme = .dark
        #expect(Color(Color.red.resolve(in: environment)) == .rgb(0xFF, 0x45, 0x3A))
        environment.palette = Self.darkPage
        environment.colorScheme = .light
        #expect(Color(Color.red.resolve(in: environment)) == .rgb(0xFF, 0x3B, 0x30))
    }
}
