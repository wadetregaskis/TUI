//  🖥️ TUI — A Terminal UI framework for Swift
//  HostileNumbersColorTests.swift
//
//  Colours made from hostile components, faded by hostile opacities and
//  adjusted by hostile colour effects: each must draw without trapping. See
//  HostileNumbersSupport.swift.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("Hostile numbers: colour")
struct HostileNumbersColorTests {

    /// Every way a colour is made from numbers, each component `value`.
    private func colors(_ value: Double) -> [Color] {
        [
            Color(red: value, green: value, blue: value),
            Color(red: 0.5, green: value, blue: 0.5, opacity: value),
            Color(.sRGBLinear, red: value, green: 0.2, blue: 0.3, opacity: 0.5),
            Color(.displayP3, red: value, green: 0.2, blue: 0.3),
            Color(white: value),
            Color(white: 0.5, opacity: value),
            Color(hue: value, saturation: value, brightness: value),
            Color(hue: value, saturation: 1, brightness: 1, opacity: value),
            Color(hue: 0.3, saturation: value, brightness: 1),
            Color.hsl(value, value, value),
            Color.hsl(value, 1, 0.5),
            Color.hsb(value, value, value),
            Color.hsb(value, 1, 1),
            Color.cmyk(value, value, value, value),
            Color.cmyk(value, 0, 0, 0),
            Color(Color.Resolved(red: Float(value), green: Float(value), blue: Float(value), opacity: Float(value))),
            Color.red.opacity(value),
            Color.red.opacity(value, over: .blue),
            Color.red.lighter(by: value),
            Color.red.darker(by: value),
            Color.red.headroom(value),
            Color.lerp(.red, .blue, phase: value),
            Color.red.compositing(value, over: .white),
            Color.gray.ensuringContrast(atLeast: value, against: .black),
            Color.red.breathEnds(dimmedTo: value, over: .black).dim,
        ]
    }

    @Test("A colour made from any component draws", arguments: Hostile.doubles)
    func components(value: Double) {
        for color in colors(value) {
            drawHostile(Text("colour").foregroundStyle(color).background(color))
            drawHostile(color)
        }
    }

    @Test("A colour made from any component resolves at every depth", arguments: Hostile.doubles)
    func depths(value: Double) {
        for color in colors(value) {
            _ = color.downsampledToPalette256()
            _ = color.downsampledToANSI16()
            _ = color.contrastRatio(against: .white)
            _ = color.lightnessDifference(from: .black)
        }
    }

    @Test("Any opacity draws", arguments: Hostile.doubles)
    func opacity(value: Double) {
        drawHostile(Text("fade").opacity(value))
        drawHostile(Text("fade").background(.red).opacity(value))
        drawHostile(Text("fade").foregroundStyle(Color.red.opacity(value)))
        drawHostile(Text("fade").foregroundStyle(.tint.opacity(value)))
        drawHostile(VStack { Text("under"); Text("over").opacity(value) }.background(.blue))
    }

    @Test("Any colour effect draws", arguments: Hostile.doubles)
    func colorEffects(value: Double) {
        let content = Text("effect").foregroundStyle(.red).background(.blue)
        drawHostile(content.brightness(value))
        drawHostile(content.contrast(value))
        drawHostile(content.saturation(value))
        drawHostile(content.grayscale(value))
        drawHostile(content.hueRotation(.degrees(value)))
        drawHostile(content.hueRotation(.radians(value)))
        drawHostile(content.colorMultiply(Color(red: value, green: value, blue: value)))
    }

    @Test("Any visual effect draws", arguments: Hostile.doubles)
    func visualEffects(value: Double) {
        let content = Text("effect").foregroundStyle(.red).background(.blue)
        drawHostile(content.visualEffect { effect, _ in effect.opacity(value) })
        drawHostile(content.visualEffect { effect, _ in effect.brightness(value) })
        drawHostile(content.visualEffect { effect, _ in effect.contrast(value) })
        drawHostile(content.visualEffect { effect, _ in effect.saturation(value) })
        drawHostile(content.visualEffect { effect, _ in effect.grayscale(value) })
        drawHostile(content.visualEffect { effect, _ in effect.hueRotation(.degrees(value)) })
    }

    // MARK: Hunt 11-20

    #if !os(WASI)  // Exit tests need a child process, which WASI cannot start.
        /// `Int64(_:)` trapped on an opacity past about 3.6e16, which ends the
        /// whole run: so in a child process.
        @Test("A resolved colour of any opacity describes itself (STYLE-10)")
        func resolvedDescription() async {
            await #expect(processExitsWith: .success) {
                for opacity: Float in [1e20, -1e20, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, .infinity, .nan] {
                    _ = Color.Resolved(red: 0, green: 0, blue: 0, opacity: opacity).description
                }
                // The measured 32-bit wraps of SwiftUI's spelling stand.
                precondition(Color.Resolved(red: 1.5, green: -0.2, blue: 0.5).description == "#17FFFFFFFCE80FF")
            }
        }
    #endif

    @Test("An opacity that is not a number is no opacity, over the bare page and over a sibling alike (BLEND-14)")
    func notANumberOpacity() {
        func shows(_ view: some View) -> Bool {
            let harness = InputChainHarness(width: 10, height: 2)
            let palette = harness.context.environment.palette
            let buffer = harness.frame(view).resolvingOpacity(surface: palette.background, palette: palette)
            return buffer.lines.contains { $0.stripped.contains("x") }
        }
        #expect(!shows(Text("x").opacity(.nan)), "over the bare page")
        #expect(!shows(ZStack { Color.red; Text("x").opacity(.nan) }), "over a sibling")
        #expect(shows(Text("x").opacity(1)), "the yardstick shows")
    }
}
