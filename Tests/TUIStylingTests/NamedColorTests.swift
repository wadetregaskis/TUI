//  🖥️ TUI — A Terminal UI framework for Swift
//  NamedColorTests.swift
//
//  SwiftUI's fifteen named colours, and `magenta`, which SwiftUI does not have.
//
//  The values are Apple's system palette in the light and dark appearances,
//  measured rather than guessed (`Tools/SwiftUIProbes/Named colours by
//  scheme/`), so the tests pin the exact bytes: a "close enough" red would make
//  ported SwiftUI code look subtly wrong and nothing would catch it. Thirteen
//  follow the scheme where they are resolved, and read their light value where
//  they are measured unresolved, as in a view body. They are colours, not the
//  terminal's slots, which are spelled `Color.ansi(_:)` (ColorANSIFactoryTests).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIStyling

/// A palette that states its page and the roles with no default.
struct NamedColourPagePalette: Palette {
    let id = "named-colour-page"
    let name = "Named colour page"
    var background: Color
    var foreground = Color.rgb(128, 128, 128)
    var accent = Color.rgb(0, 200, 0)
    let success = Color.rgb(0, 200, 0)
    let warning = Color.rgb(200, 200, 0)
    let error = Color.rgb(200, 0, 0)
    let info = Color.rgb(0, 200, 200)
    let border = Color.rgb(100, 100, 100)
}

@Suite("SwiftUI named colours")
struct NamedColorTests {

    /// One name, and the RGB it must be in each scheme.
    struct Named: Sendable, CustomTestStringConvertible {
        let name: String
        let color: Color
        let rgb: [UInt8]
        let dark: [UInt8]
        var testDescription: String { name }

        /// Whether the name follows the scheme.
        var adapts: Bool { rgb != dark }
    }

    /// SwiftUI's fifteen, resolved with `Color.resolve(in:)` under a light and a
    /// dark `EnvironmentValues` on macOS 15.8.1 (`white`, `black`: the same in
    /// both). `namedcolours.out` in the probe's folder is the record.
    static let swiftUI: [Named] = [
        Named(name: "black", color: .black, rgb: [0x00, 0x00, 0x00], dark: [0x00, 0x00, 0x00]),
        Named(name: "white", color: .white, rgb: [0xFF, 0xFF, 0xFF], dark: [0xFF, 0xFF, 0xFF]),
        Named(name: "red", color: .red, rgb: [0xFF, 0x3B, 0x30], dark: [0xFF, 0x45, 0x3A]),
        Named(name: "orange", color: .orange, rgb: [0xFF, 0x95, 0x00], dark: [0xFF, 0x9F, 0x0A]),
        Named(name: "yellow", color: .yellow, rgb: [0xFF, 0xCC, 0x00], dark: [0xFF, 0xD6, 0x0A]),
        Named(name: "green", color: .green, rgb: [0x28, 0xCD, 0x41], dark: [0x32, 0xD7, 0x4B]),
        Named(name: "mint", color: .mint, rgb: [0x00, 0xC7, 0xBE], dark: [0x63, 0xE6, 0xE2]),
        Named(name: "teal", color: .teal, rgb: [0x59, 0xAD, 0xC4], dark: [0x6A, 0xC4, 0xDC]),
        Named(name: "cyan", color: .cyan, rgb: [0x55, 0xBE, 0xF0], dark: [0x5A, 0xC8, 0xF5]),
        Named(name: "blue", color: .blue, rgb: [0x00, 0x7A, 0xFF], dark: [0x0A, 0x84, 0xFF]),
        Named(name: "indigo", color: .indigo, rgb: [0x58, 0x56, 0xD6], dark: [0x5E, 0x5C, 0xE6]),
        Named(name: "purple", color: .purple, rgb: [0xAF, 0x52, 0xDE], dark: [0xBF, 0x5A, 0xF2]),
        Named(name: "pink", color: .pink, rgb: [0xFF, 0x2D, 0x55], dark: [0xFF, 0x37, 0x5F]),
        Named(name: "brown", color: .brown, rgb: [0xA2, 0x84, 0x5E], dark: [0xAC, 0x8E, 0x68]),
        Named(name: "gray", color: .gray, rgb: [0x8E, 0x8E, 0x93], dark: [0x98, 0x98, 0x9D]),
    ]

    /// TUI's own: SwiftUI has no magenta, and a TUI app ported from ANSI
    /// habits reaches for one. Full-strength #FF00FF in both schemes.
    static let magenta = Named(
        name: "magenta", color: .magenta, rgb: [0xFF, 0x00, 0xFF], dark: [0xFF, 0x00, 0xFF])

    static let all = swiftUI + [magenta]

    static let lightPage = NamedColourPagePalette(background: .rgb(250, 250, 250))
    static let darkPage = NamedColourPagePalette(background: .rgb(10, 10, 10))

    private static func rgb(_ bytes: [UInt8]) -> Color { .rgb(bytes[0], bytes[1], bytes[2]) }

    /// Unresolved — as a view body holds it — a name measures and spells as its
    /// LIGHT value, which is what SwiftUI's `resolve(in: EnvironmentValues())`
    /// answers.
    @Test("Unresolved, each name is its light RGB, and emits it at truecolor", arguments: all)
    func bytes(_ named: Named) {
        if named.adapts {
            #expect(named.color.value != Self.rgb(named.rgb).value, "a name, not its value")
        } else {
            #expect(named.color.value == .rgb(red: named.rgb[0], green: named.rgb[1], blue: named.rgb[2]))
        }
        #expect(named.color.isOpaque)
        #expect(named.color.rgbComponents.map { [$0.red, $0.green, $0.blue] } == named.rgb)
        let channels = named.rgb.map { "\($0)" }
        #expect(named.color.foregroundCodes(depth: .truecolor) == ["38", "2"] + channels)
        #expect(named.color.backgroundCodes(depth: .truecolor) == ["48", "2"] + channels)
    }

    @Test("Resolved, each name takes its scheme's value", arguments: all)
    func resolvedByScheme(_ named: Named) {
        #expect(named.color.resolve(with: Self.lightPage) == Self.rgb(named.rgb))
        #expect(named.color.resolve(with: Self.darkPage) == Self.rgb(named.dark))
        let channels = named.dark.map { "\($0)" }
        #expect(named.color.resolve(with: Self.darkPage).foregroundCodes(depth: .truecolor) == ["38", "2"] + channels)
    }

    /// A translucent name keeps its alpha as it is resolved: the result is the
    /// same colour spelled for one scheme.
    @Test("Resolving a faded name carries its alpha")
    func resolvingCarriesAlpha() {
        let faded = Color.red.opacity(0.5)
        #expect(faded.resolve(with: Self.darkPage) == Color.rgb(0xFF, 0x45, 0x3A).opacity(0.5))
        #expect(faded.resolve(with: Self.lightPage) == Color.rgb(0xFF, 0x3B, 0x30).opacity(0.5))
    }

    /// A palette role spelled as a name resolves through the role to the scheme's
    /// value, as `.palette.accent` reaches whatever the palette holds.
    @Test("A role that holds a name resolves to the scheme's value")
    func roleHoldingAName() {
        var dark = Self.darkPage
        dark.accent = .blue
        #expect(Color.palette.accent.resolve(with: dark) == .rgb(0x0A, 0x84, 0xFF))
        var light = Self.lightPage
        light.accent = .blue
        #expect(Color.palette.accent.resolve(with: light) == .rgb(0x00, 0x7A, 0xFF))
    }

    /// A page in a name is measured at its light value to decide the scheme, and
    /// deciding it does not recurse: resolving the page by the scheme would ask
    /// the scheme, which is what is being decided.
    @Test("A page in a named colour decides the scheme by its light value")
    func pageInANamedColour() {
        // #FFCC00 reads better under black ink: a light page.
        let yellow = NamedColourPagePalette(background: .yellow)
        #expect(yellow.colorScheme == .light)
        #expect(Color.palette.background.resolve(with: yellow) == .rgb(0xFF, 0xCC, 0x00))
        // #5856D6 reads better under white: a dark page, so it is drawn dark.
        let indigo = NamedColourPagePalette(background: .indigo)
        #expect(indigo.colorScheme == .dark)
        #expect(Color.palette.background.resolve(with: indigo) == .rgb(0x5E, 0x5C, 0xE6))
    }

    /// What a body does with a name — composite it over a surface, blend it,
    /// measure it — answers with the light value, as SwiftUI's
    /// `resolve(in: EnvironmentValues())` does: such a result is RGB, and no
    /// longer follows the scheme.
    @Test("Arithmetic on a name in a body uses the light value")
    func bodyArithmeticIsLight() {
        let red = Color.rgb(0xFF, 0x3B, 0x30)
        let blue = Color.rgb(0x00, 0x7A, 0xFF)
        #expect(Color.red.opacity(0.5, over: .black) == red.opacity(0.5, over: .black))
        #expect(Color.lerp(.red, .blue, phase: 0.5) == Color.lerp(red, blue, phase: 0.5))
        #expect(Color.red.mix(with: .blue, by: 0.3) == red.mix(with: blue, by: 0.3))
        #expect(Color.red.lighter(by: 0.2) == red.lighter(by: 0.2))
        #expect(Color.red.relativeLuminance == red.relativeLuminance)
        // The result is a value, so it no longer follows the scheme.
        let mixed = Color.lerp(.red, .blue, phase: 0.5)
        #expect(mixed.resolve(with: Self.darkPage) == mixed)
    }

    /// A blend's ends keep their spelling, so a name at either end of a lerp is
    /// still the name, and still resolves by scheme.
    @Test("A blend at an end keeps the name")
    func blendEndsKeepTheName() {
        #expect(Color.lerp(.red, .blue, phase: 0) == .red)
        #expect(Color.lerp(.red, .blue, phase: 1) == .blue)
        #expect(Color.lerp(.red, .red, phase: 0.4) == .red)
        #expect(Color.lerp(.red, .blue, phase: 0).resolve(with: Self.darkPage) == .rgb(0xFF, 0x45, 0x3A))
    }

    /// At 256 colours a name resolved for a scheme lands on the entry nearest
    /// THAT scheme's value, and unresolved on the one nearest its light value.
    @Test("At 256 colours a name quantises its scheme's value", arguments: swiftUI.filter(\.adapts))
    func palette256(_ named: Named) {
        let dark = Self.rgb(named.dark).downsampledToPalette256()
        let light = Self.rgb(named.rgb).downsampledToPalette256()
        #expect(named.color.resolve(with: Self.darkPage).downsampledToPalette256() == dark)
        #expect(named.color.resolve(with: Self.lightPage).downsampledToPalette256() == light)
        #expect(
            named.color.resolve(with: Self.darkPage).foregroundCodes(depth: .palette256)
                == dark.foregroundCodes(depth: .palette256))
        #expect(named.color.foregroundCodes(depth: .palette256) == light.foregroundCodes(depth: .palette256))
        #expect(named.color.downsampledToPalette256() == light)
    }

    /// The scheme shows at 256 colours too, not only at truecolor, for the names
    /// whose two values are far enough apart to land on different cube entries;
    /// the others share one. Measured with the quantiser as it stands, so a
    /// change to it shows up here as well as in its own tests.
    @Test("Where a name's two values are two 256-colour entries")
    func entriesAt256() {
        let expected: [(Color, light: UInt8, dark: UInt8)] = [
            (.red, 196, 196), (.orange, 208, 214), (.yellow, 220, 220), (.green, 41, 41),
            (.mint, 44, 80), (.teal, 38, 81), (.cyan, 74, 81), (.blue, 33, 33),
            (.indigo, 62, 63), (.purple, 134, 171), (.pink, 197, 197), (.brown, 137, 137),
            (.gray, 245, 246),
        ]
        for (colour, light, dark) in expected {
            #expect(colour.resolve(with: Self.lightPage).downsampledToPalette256() == .palette256(light), "\(colour)")
            #expect(colour.resolve(with: Self.darkPage).downsampledToPalette256() == .palette256(dark), "\(colour)")
        }
    }

    @Test("A name describes itself by name, as SwiftUI's does")
    func describesByName() {
        #expect(Color.red.description == "red")
        #expect(Color.red.opacity(0.5).description == "red at 128/255")
        #expect(Color.white.description == "#FFFFFFFF")
    }

    /// The name is a colour, not a slot: nothing a terminal profile keeps
    /// repaints it, and bold does not brighten it above sixteen colours.
    @Test("A named colour is not terminal-defined", arguments: all)
    func notTerminalDefined(_ named: Named) {
        #expect(!named.color.isTerminalDefined)
        #expect(!ANSIColor.allCases.map(Color.ansi).contains(named.color))
    }

    @Test("Red is Apple's red, not the terminal's")
    func redIsApples() {
        #expect(Color.red.foregroundCodes(depth: .truecolor) == ["38", "2", "255", "59", "48"])
        #expect(Color.red != Color.ansi(.red))
    }

    /// At sixteen colours a named colour becomes the nearest slot by xterm's
    /// table, which for red, blue, white and magenta is the bright one.
    @Test("At sixteen colours each name lands on its nearest slot")
    func sixteenColours() {
        let expected: [(String, Color, String)] = [
            ("black", .black, "30"), ("red", .red, "91"), ("green", .green, "32"),
            ("yellow", .yellow, "33"), ("blue", .blue, "94"), ("cyan", .cyan, "36"),
            ("white", .white, "97"), ("magenta", .magenta, "95"),
        ]
        for (name, color, code) in expected {
            #expect(color.foregroundCodes(depth: .basic16) == [code], "\(name)")
        }
    }

    @Test("clear is black at zero opacity, as in SwiftUI")
    func clearIsTransparentBlack() {
        #expect(Color.clear == Color.black.opacity(0))
    }

    /// The deliberate divergence, pinned so nobody "fixes" it later: SwiftUI's
    /// orange is Apple's, the picker's Named-colours tab lists CSS's, and the
    /// two are different colours that share a word.
    @Test("SwiftUI's orange is not the CSS orange")
    func notCSS() {
        #expect(Color.orange.rgbComponents?.green == 0x95, "Apple's #FF9500")
        #expect(Color.orange.rgbComponents?.green != 0xA5, "not CSS's #FFA500")
    }

    /// Every named colour has to survive the trip down to a 16-colour terminal,
    /// because that is where a wrong one is least recoverable. Downsampling
    /// LANDS on the ANSI set — so doing it twice changes nothing, which is the
    /// property that says it really landed rather than merely moved.
    @Test("each downsamples onto the ANSI set and stays there", arguments: all)
    func downsamples(_ named: Named) {
        let once = named.color.downsampledToANSI16()
        #expect(once.isTerminalDefined)
        #expect(once.downsampledToANSI16() == once, "downsampling is idempotent once it has landed")
    }

    @Test("distinct names are distinct colours")
    func allDistinct() {
        #expect(Set(Self.all.map(\.color)).count == Self.all.count)
    }
}
