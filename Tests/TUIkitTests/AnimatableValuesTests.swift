//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatableValuesTests.swift
//
//  `AnimatableValues`: several animatable values as one vector.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitTestSupport

@Suite("AnimatableValues")
struct AnimatableValuesTests {

    @Test("Arithmetic acts on every value, and the magnitude sums theirs")
    func arithmetic() {
        let first = AnimatableValues(1.0, 2.0, 3.0)
        let second = AnimatableValues(0.5, 0.5, 0.5)
        #expect((first + second).value == (1.5, 2.5, 3.5))
        #expect((first - second).value == (0.5, 1.5, 2.5))
        #expect(first.scaled(by: 2).value == (2.0, 4.0, 6.0))
        #expect(first.magnitudeSquared == 14)
        #expect(AnimatableValues<Double, Double>.zero.value == (0, 0))
    }

    @Test("Equality compares every value")
    func equality() {
        let values = AnimatableValues(1.0, 2.0)
        #expect(values == AnimatableValues(1.0, 2.0 + 0))
        #expect(AnimatableValues(1.0, 2.0) != AnimatableValues(1.0, 2.5))
    }

    @Test("A pair nests inside, as SwiftUI's examples nest them")
    func nesting() {
        let mixed = AnimatableValues(AnimatablePair(1.0, 2.0), 3.0)
        #expect((mixed + mixed).value.0 == AnimatablePair(2.0, 4.0))
        #expect((mixed + mixed).value.1 == 6.0)
    }
}
