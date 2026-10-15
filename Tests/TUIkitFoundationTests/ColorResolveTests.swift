//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorResolveTests.swift
//
//  `Color.resolve(in:)`: a palette role, a constant and a terminal default
//  resolved to numbers against an environment.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

@MainActor
@Suite("Color.resolve(in:)")
struct ColorResolveTests {

    private func environment() -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        return environment
    }

    @Test("A constant resolves to its own components")
    func constant() {
        let resolved = Color.rgb(51, 102, 153).opacity(0.5).resolve(in: environment())
        #expect(resolved.description == "#33669980")
    }

    @Test("A palette role resolves through the palette in force")
    func role() {
        let environment = environment()
        #expect(Color(Color.palette.accent.resolve(in: environment)) == environment.palette.accent)
    }

    @Test("A resolved colour paints itself")
    func resolvedIsAStyle() {
        let resolved = Color.Resolved(red: 0.2, green: 0.4, blue: 0.6)
        #expect(resolved.paint(in: environment()) == .color(.rgb(0x33, 0x66, 0x99)))
    }

    @Test("Its animatable data is the linear components and the opacity")
    func animatableData() {
        var resolved = Color.Resolved(red: 1, green: 0.5, blue: 0, opacity: 0.25)
        let data = resolved.animatableData
        #expect(data.first == resolved.linearRed && data.second.second.second == 0.25)
        resolved.animatableData = AnimatablePair(0, AnimatablePair(1, AnimatablePair(0, 1)))
        #expect(resolved.green == 1 && resolved.opacity == 1)
    }

    @Test("The terminal's default colour, which has no RGB, reads light on a dark scheme")
    func terminalDefault() {
        var environment = environment()
        environment.colorScheme = .dark
        #expect(Color.default.resolve(in: environment).red == 1)
        environment.colorScheme = .light
        #expect(Color.default.resolve(in: environment).red == 0)
    }
}
