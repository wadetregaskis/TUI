//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FontResolvedTests.swift
//
//  `Font.resolve(in:)`: a semantic font resolved through the style cascade, as
//  a `Text` in that font draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Resolved fonts")
struct FontResolvedTests {

    private func resolve(_ font: Font, cascade: StyleCascade = StyleCascade()) -> Font.Resolved {
        var environment = EnvironmentValues()
        environment.styleCascade = cascade
        return font.resolve(in: environment.fontResolutionContext)
    }

    @Test("The tiers resolve to bold, regular and light")
    func tiers() {
        #expect(resolve(.headline).isBold && resolve(.headline).weight == .bold)
        #expect(!resolve(.body).isBold && resolve(.body).weight == .regular)
        #expect(resolve(.caption).weight == .light)
        #expect(resolve(.body.italic()).isItalic)
        #expect(resolve(.body).isMonospaced && !resolve(.body).isSmallCaps)
    }

    @Test("A named weight is kept while it is drawn as named")
    func namedWeight() {
        #expect(resolve(.body.weight(.semibold)).weight == .semibold)
        #expect(resolve(.body.weight(.semibold)).isBold)
    }

    @Test("A theme's cascade entry for the style wins, as it does for a Text")
    func cascadeWins() {
        var plain = StyleAttributes()
        plain.bold = false
        let theme = StyleCascade().appending(.font(.headline), plain)
        let resolved = resolve(.headline, cascade: theme)
        #expect(!resolved.isBold && resolved.weight == .regular)
        #expect(resolve(.headline).isBold, "and without the theme, a headline is bold")
    }

    private func resolve(_ font: Font, under environmentFont: Font?) -> Font.Resolved {
        var environment = EnvironmentValues()
        environment.font = environmentFont
        return font.resolve(in: environment.fontResolutionContext)
    }

    @Test("Font.default is the font in effect, with its own statements over it")
    func defaultIsTheEnvironmentsFont() {
        #expect(resolve(.default, under: .headline).isBold)
        #expect(!resolve(.default, under: nil).isBold && resolve(.default, under: nil).weight == .regular)
        let boldCaption = resolve(.default.bold(), under: .caption)
        #expect(boldCaption.isBold && boldCaption.weight == .bold)
        #expect(resolve(.default, under: .default).weight == .regular, "a default in effect inherits nothing")
    }

    @Test("A Text in Font.default draws in the font set above it")
    func textInDefaultDrawsTheInheritedFont() {
        func line(_ view: some View) -> String {
            InputChainHarness(width: 10, height: 1).frame(view).lines.first ?? ""
        }
        let inherited = line(Text("Hi").font(.default).font(.headline))
        #expect(inherited == line(Text("Hi").font(.headline)), "\(inherited.debugDescription)")
        #expect(line(Text("Hi").font(.default)) == line(Text("Hi")))
    }
}
