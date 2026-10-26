//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimatableMacroTests.swift
//
//  `@Animatable` and `@AnimatableIgnored` (decisions A52), used as an app uses
//  them: the types below are expanded by the compiler plugin, and the tests
//  read and write the `animatableData` it wrote.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUI
import TUIMacros

/// SwiftUI's own example, with TUI's numbers.
@Animatable
struct Meter {
    var width: Double
    var angle: Double
    @AnimatableIgnored var isOpaque: Bool
    let label: String
    var computed: Double { width * 2 }
    static let count = 0
}

/// One property: the data is a one-element `AnimatableValues`.
@Animatable
struct Level {
    var value: Double
}

/// Already `Animatable`: the macro adds the data but not the conformance a
/// second time (which would not compile).
@Animatable
struct Pair: Animatable {
    var first: Double
    var second: Double
    var observed: Double = 0 {
        didSet {}
    }
}

/// A public type: the data must be public for the conformance to be.
@Animatable
public struct PublicRamp {
    /// Where the ramp starts.
    public var start: Double
    /// Where the ramp ends.
    public var end: Double
}

@MainActor
@Suite("@Animatable")
struct AnimatableMacroTests {
    @Test("The data is the animatable properties in order, and writing it writes them back")
    func readsAndWrites() {
        var meter = Meter(width: 10, angle: 0.5, isOpaque: true, label: "m")
        let data: AnimatableValues<Double, Double> = meter.animatableData
        #expect(data.value.0 == 10)
        #expect(data.value.1 == 0.5)
        meter.animatableData = AnimatableValues(4, 2)
        #expect(meter.width == 4)
        #expect(meter.angle == 2)
        #expect(meter.isOpaque, "an ignored property was written")
        #expect(meter.label == "m")
    }

    @Test("A single property, observed properties, and a type that already conformed")
    func shapes() {
        var level = Level(value: 3)
        #expect(level.animatableData == AnimatableValues(3))
        level.animatableData = AnimatableValues(7)
        #expect(level.value == 7)

        var pair = Pair(first: 1, second: 2)
        #expect(pair.animatableData == AnimatableValues(1, 2, 0))
        pair.animatableData = AnimatableValues(5, 6, 9)
        #expect(pair.first == 5 && pair.second == 6 && pair.observed == 9)
    }

    @Test("The type conforms, so TUI can interpolate it")
    func conforms() {
        func data<T: Animatable>(of value: T) -> T.AnimatableData { value.animatableData }
        var ramp = PublicRamp(start: 0, end: 10)
        let halfway = data(of: ramp).scaled(by: 0.5)
        ramp.animatableData = halfway
        #expect(ramp.start == 0 && ramp.end == 5)
    }
}
