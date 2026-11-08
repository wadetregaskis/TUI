//  🖥️ TUI — A Terminal UI framework for Swift
//  OKLabColorTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIStyling

/// The public OKLab and OKLCh conversions and `deltaE`, against Björn
/// Ottosson's published values for the sRGB primaries (and CSS Color 4's
/// `oklch()` for red), to four places.
@MainActor
@Suite("OKLab and OKLCh")
struct OKLabColorTests {
    private func close(_ value: Double, _ expected: Double, within tolerance: Double = 0.0005) -> Bool {
        abs(value - expected) <= tolerance
    }

    @Test(
        "sRGB primaries and white convert to their published OKLab coordinates",
        arguments: [
            (UInt8(255), UInt8(255), UInt8(255), 1.0, 0.0, 0.0),
            (255, 0, 0, 0.62796, 0.22486, 0.12585),
            (0, 255, 0, 0.86644, -0.23389, 0.17950),
            (0, 0, 255, 0.45201, -0.03246, -0.31153),
        ])
    func primaries(red: UInt8, green: UInt8, blue: UInt8, lightness: Double, a: Double, b: Double) {
        let lab = Color.rgbToOKLab(red: red, green: green, blue: blue)
        #expect(close(lab.lightness, lightness))
        #expect(close(lab.a, a))
        #expect(close(lab.b, b))
    }

    @Test("Red's OKLCh is CSS Color 4's oklch(0.628 0.2577 29.23)")
    func redInPolarForm() {
        let lch = Color.rgbToOKLCh(red: 255, green: 0, blue: 0)
        #expect(close(lch.lightness, 0.62796))
        #expect(close(lch.chroma, 0.25768))
        #expect(close(lch.hue, 29.234, within: 0.01))
    }

    @Test("A grey has no hue: OKLCh reports chroma about 0 and hue 0")
    func greyHasNoHue() {
        let lch = Color.rgbToOKLCh(red: 128, green: 128, blue: 128)
        #expect(lch.chroma < 0.0001)
        #expect(lch.hue == 0)
    }

    @Test("Hue is reported on 0..<360: blue's angle is positive")
    func hueIsPositive() {
        let lch = Color.rgbToOKLCh(red: 0, green: 0, blue: 255)
        #expect(close(lch.hue, 264.05, within: 0.05))
    }

    @Test("The constructors invert the conversions for every channel corner")
    func roundTrips() {
        for red in [UInt8(0), 64, 200, 255] {
            for green in [UInt8(0), 128, 255] {
                for blue in [UInt8(0), 30, 255] {
                    let lab = Color.rgbToOKLab(red: red, green: green, blue: blue)
                    #expect(Color.oklab(lab.lightness, lab.a, lab.b) == .rgb(red, green, blue))
                    let lch = Color.rgbToOKLCh(red: red, green: green, blue: blue)
                    #expect(Color.oklch(lch.lightness, lch.chroma, lch.hue) == .rgb(red, green, blue))
                }
            }
        }
    }

    @Test("A point sRGB cannot show is clamped into range, and a hue off the circle wraps")
    func outOfGamutClamps() {
        // Lightness above 1 is past white on every channel.
        #expect(Color.oklab(1.5, 0, 0) == .rgb(255, 255, 255))
        #expect(Color.oklab(-1, 0, 0) == .rgb(0, 0, 0))
        // A non-finite coordinate draws black rather than trapping.
        #expect(Color.oklab(.nan, 0, 0) == .rgb(0, 0, 0))
        #expect(Color.oklch(0.7, 0.1, 30 + 360) == Color.oklch(0.7, 0.1, 30))
    }

    @Test("ΔEOK: 0 for one colour, 1 from black to white, symmetric")
    func deltaEOK() throws {
        #expect(Color.rgb(10, 20, 30).deltaE(.rgb(10, 20, 30)) == 0)
        let blackToWhite = try #require(Color.black.deltaE(.white))
        #expect(close(blackToWhite, 1))
        let redGreen = try #require(Color.rgb(255, 0, 0).deltaE(.rgb(0, 255, 0), method: .ok))
        let greenRed = try #require(Color.rgb(0, 255, 0).deltaE(.rgb(255, 0, 0)))
        #expect(redGreen == greenRed)
        // Red to green: √(0.23848² + 0.45875² + 0.05365²).
        #expect(close(redGreen, 0.51981))
    }

    @Test("ΔE is nil where a colour has no RGB to measure")
    func deltaEWithoutRGB() {
        #expect(Color.default.deltaE(.white) == nil)
        #expect(Color.white.deltaE(.default) == nil)
    }
}
