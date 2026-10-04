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
}
