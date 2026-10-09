//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorResolvedTests.swift
//
//  `Color.Resolved` and the component initialisers, against the numbers
//  SwiftUI gives for the same calls (measured on macOS 15).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitStyling

@Suite("Color.Resolved and the component initialisers")
struct ColorResolvedTests {

    private func close(_ lhs: Float, _ rhs: Float) -> Bool { abs(lhs - rhs) < 1e-5 }

    @Test("Components are stored linear and read back encoded")
    func linearStorage() {
        let resolved = Color.Resolved(red: 1, green: 0.5, blue: 0, opacity: 0.25)
        #expect(close(resolved.linearGreen, 0.214_041_14))
        #expect(close(resolved.green, 0.5))
        let fromLinear = Color.Resolved(colorSpace: .sRGBLinear, red: 0.5, green: 0.5, blue: 0.5)
        #expect(close(fromLinear.red, 0.735_356_9))
        // Exactly 1 round trip, as SwiftUI's does.
        #expect(Color.Resolved(red: 1, green: 1, blue: 1).red == 1)
    }

    @Test("Display P3 converts to extended sRGB")
    func displayP3() {
        let red = Color.Resolved(colorSpace: .displayP3, red: 1, green: 0, blue: 0)
        #expect(close(red.red, 1.093_050_7))
        #expect(close(red.green, -0.226_582_91))
        #expect(close(red.blue, -0.150_406_12))
        let green = Color.Resolved(colorSpace: .displayP3, red: 0, green: 1, blue: 0)
        #expect(close(green.linearRed, -0.2247) && close(green.linearGreen, 1.0419) && close(green.linearBlue, -0.0786))
    }

    @Test("The description is SwiftUI's #RRGGBBAA, wrap included")
    func description() {
        #expect(Color.Resolved(red: 1, green: 0.5, blue: 0, opacity: 0.25).description == "#FF800040")
        #expect(Color.Resolved(colorSpace: .sRGBLinear, red: 0.5, green: 0.5, blue: 0.5).description == "#BCBCBCFF")
        #expect(Color.Resolved(red: 1.5, green: -0.2, blue: 0.5).description == "#17FFFFFFFCE80FF")
        #expect(Color.Resolved(colorSpace: .displayP3, red: 1, green: 0, blue: 0).description == "#117FFFFFFC7FFFFFFDBFF")
    }

    @Test("It encodes as [red, green, blue, opacity], encoded sRGB, and decodes back")
    func codable() throws {
        let resolved = Color.Resolved(red: 1, green: 0.5, blue: 0, opacity: 0.25)
        let json = try #require(String(data: JSONEncoder().encode(resolved), encoding: .utf8))
        #expect(json == "[1,0.5,0,0.25]")
        let decoded = try JSONDecoder().decode(Color.Resolved.self, from: Data(json.utf8))
        #expect(close(decoded.linearGreen, resolved.linearGreen) && decoded.opacity == 0.25)
    }

    @Test("The component initialisers make the 8-bit colour SwiftUI's resolves to")
    func componentInitialisers() {
        #expect(Color(red: 0.2, green: 0.4, blue: 0.6) == Color.rgb(0x33, 0x66, 0x99))
        #expect(Color(red: 0.2, green: 0.4, blue: 0.6).description == "#336699FF")
        #expect(Color(hue: 0.5, saturation: 1, brightness: 1) == Color.rgb(0, 255, 255))
        #expect(Color(white: 0.5, opacity: 0.5) == Color.rgb(128, 128, 128).opacity(0.5))
        #expect(Color(.sRGBLinear, white: 0.5) == Color.rgb(188, 188, 188))
        // Out of range clamps: a terminal shows 8-bit sRGB.
        #expect(Color(red: 1.5, green: -0.2, blue: 0.5) == Color.rgb(255, 0, 128))
    }

    @Test("A colour made from a resolved one keeps its numbers to the byte")
    func roundTrip() {
        let resolved = Color.Resolved(red: 0.2, green: 0.4, blue: 0.6, opacity: 0.5)
        #expect(Color(resolved) == Color.rgb(0x33, 0x66, 0x99).opacity(0.5))
    }

    /// SwiftUI's own example: a yellow brightened two stops, with its headroom.
    /// A terminal is SDR, so the cap is met and the colour is what it was —
    /// clamped to SDR when it was made, which no headroom changes.
    @Test("headroom(_:) returns the colour as it is: a terminal is SDR")
    func headroomIsAlwaysMet() {
        let bright = Color(.sRGB, red: 1.83, green: 1.47, blue: 0)
        #expect(bright.headroom(4) == bright)
        #expect(bright.headroom(nil) == bright)
        #expect(Color.palette.accent.headroom(2) == Color.palette.accent)
        #expect(bright == Color(.sRGB, red: 1, green: 1, blue: 0), "the extended components were not clamped")
    }

    @Test("A colour describes itself as SwiftUI's would, or by role")
    func colourDescription() {
        #expect(Color.rgb(1, 2, 3).description == "#010203FF")
        #expect(Color.palette.accent.description == "accent")
        #expect(Color.palette.accent.opacity(0.5).description == "accent at 128/255")
    }
}
