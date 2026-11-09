//  🖥️ TUI — A Terminal UI framework for Swift
//  GradientStopsCodecTests.swift
//
//  The Example's stored-gradient format: what a malformed stored value reads
//  back as.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUI

@Suite("The Example's stored-gradient format")
struct GradientStopsCodecTests {
    private let fallback = Gradient(colors: [.rgb(1, 2, 3), .rgb(4, 5, 6)])

    /// `Double("nan")` and `Double("inf")` parse. A NaN location is a stop the
    /// ramp never reaches (every comparison with it is false) and a gradient
    /// that never equals itself, so a non-finite position reads as even, like
    /// an unparseable one.
    @Test("A non-finite stop position reads as evenly spaced")
    func nonFinitePositionsReadAsEven() {
        let decoded = GradientStopsCodec.decode("FF0000@nan,00FF00@inf,0000FF@1.000", fallback: fallback)
        #expect(decoded.stops.map(\.location) == [0, 0.5, 1])
        #expect(decoded.stops.allSatisfy { $0.location.isFinite })
    }

    @Test("A stop that is only a separator is skipped")
    func separatorOnlyStopIsSkipped() {
        let decoded = GradientStopsCodec.decode("FF0000@0.000,@,0000FF@1.000", fallback: fallback)
        #expect(decoded.stops.map(\.color) == [.rgb(255, 0, 0), .rgb(0, 0, 255)])
    }
}
