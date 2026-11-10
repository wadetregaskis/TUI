//  🖥️ TUI — A Terminal UI framework for Swift
//  IntClampingDoubleTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIStyling

/// Values and what they truncate to, the largest one past 32 bits where `Int`
/// is 64 (and inside them where it is not: wasm32).
#if _pointerBitWidth(_64)
    private let ordinaryPairs: [(Double, Int)] = [
        (3.7, 3), (-3.7, -3), (0.0, 0), (255.4999, 255), (-0.9, 0), (1e15, 1_000_000_000_000_000),
    ]
#else
    private let ordinaryPairs: [(Double, Int)] = [
        (3.7, 3), (-3.7, -3), (0.0, 0), (255.4999, 255), (-0.9, 0), (1e9, 1_000_000_000),
    ]
#endif

@Suite("Int(clamping: Double)")
struct IntClampingDoubleTests {

    @Test("Ordinary values truncate toward zero, exactly as Int(_:) does", arguments: ordinaryPairs)
    func ordinary(pair: (Double, Int)) {
        #expect(Int(clamping: pair.0) == pair.1)
        #expect(Int(clamping: pair.0) == Int(pair.0), "agrees with the trapping conversion where that one is defined")
    }

    @Test("The values Int(_:) traps on land on a bound, and NaN on zero")
    func extremes() {
        #expect(Int(clamping: .infinity) == .max)
        #expect(Int(clamping: -.infinity) == .min)
        #expect(Int(clamping: 1e300) == .max)
        #expect(Int(clamping: -1e300) == .min)
        #expect(Int(clamping: .nan) == 0)
        #expect(Int(clamping: -.nan) == 0)
    }

    @Test("The boundary is exact: 2^63 (2^31) is past the largest Int, the Double below it is not")
    func boundary() {
        // `Double(Int.max)` rounds up to 2^63, which `Int(_:)` refuses.
        #expect(Int(clamping: Double(Int.max)) == .max)
        #expect(Int(clamping: Double(Int.min)) == .min)
        #if _pointerBitWidth(_64)
            // 2^63 - 1024 is the largest Double below 2^63 and converts exactly.
            #expect(Int(clamping: 9_223_372_036_854_774_784) == 9_223_372_036_854_774_784)
            #expect(Int(clamping: -9_223_372_036_854_774_784) == -9_223_372_036_854_774_784)
        #else
            // A 32-bit Int's ends are exact Doubles, so one past each is the
            // first value refused.
            #expect(Int(clamping: Double(Int.max) + 1) == .max)
            #expect(Int(clamping: Double(Int.min) - 1) == .min)
        #endif
    }
}
