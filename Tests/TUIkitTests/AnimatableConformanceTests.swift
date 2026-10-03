//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatableConformanceTests.swift
//
//  The scalar and layout conformances SwiftUI has and SwiftUI source leans on:
//  an app's `Animatable` type written against SwiftUI animates a `CGFloat`, and
//  names the associated types SwiftUI's own types spell out.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// The shape a ported SwiftUI `Animatable` takes: its data is `CGFloat`, which
/// compiles only if `CGFloat` is TUIkit `VectorArithmetic`.
private struct Pulse: Animatable {
    var animatableData: CGFloat
}

/// The same, with a pair — `AnimatablePair` needs both halves to conform.
private struct Drift: Animatable {
    var animatableData: AnimatablePair<CGFloat, CGFloat>
}

@MainActor
@Suite("Animatable conformances SwiftUI source relies on")
struct AnimatableConformanceTests {

    /// Generic, because that is how the animation system reaches a value — and
    /// because a direct `cgFloat.interpolated(…)` is ambiguous on Apple
    /// platforms, where SwiftUICore's own extension of `CGFloat` is visible
    /// (see `VectorArithmetic.swift`).
    private func halfway<T: VectorArithmetic>(_ from: T, _ to: T) -> T {
        from.interpolated(towards: to, amount: 0.5)
    }

    @Test("CGFloat interpolates as a vector")
    func cgFloatInterpolates() {
        #expect(halfway(CGFloat(2), CGFloat(10)) == 6)
        var scaled = CGFloat(3)
        scaled.scale(by: 2)
        #expect(scaled == 6)
        #expect(CGFloat(3).magnitudeSquared == 9)
    }

    @Test("An Animatable whose data is CGFloat, or a pair of them, interpolates")
    func cgFloatAnimatableData() {
        let pulse = halfway(Pulse(animatableData: 0).animatableData, 4)
        #expect(pulse == 2)
        let from = Drift(animatableData: AnimatablePair(0, 10)).animatableData
        let drift = halfway(from, AnimatablePair(4, 20))
        #expect(drift.first == 2 && drift.second == 15)
    }

    /// Through the protocol, for the reason `halfway` gives: SwiftUICore's
    /// `animatableData` on `Double` and `CGFloat` is visible on Apple
    /// platforms too, so the bare property is ambiguous there.
    private func settingData<T: Animatable>(of value: T, to data: T.AnimatableData) -> T {
        var copy = value
        copy.animatableData = data
        return copy
    }

    @Test("A scalar's animatable data is itself")
    func scalarsAreTheirOwnData() {
        #expect(settingData(of: 1.5, to: 2.5) == 2.5)
        #expect(settingData(of: CGFloat(1), to: 3) == 3)
    }

    @Test("The associated types SwiftUI spells out are spelled out")
    func associatedTypes() {
        #expect(HStackLayout.AnimatableData.self == EmptyAnimatableData.self)
        #expect(VStackLayout.AnimatableData.self == EmptyAnimatableData.self)
        #expect(ZStackLayout.AnimatableData.self == EmptyAnimatableData.self)
        #expect(AnyLayout.AnimatableData.self == EmptyAnimatableData.self)
        #expect(HStackLayout.Cache.self == Void.self)
        #expect(Angle.AnimatableData.self == Double.self)
        #expect(UnitPoint.AnimatableData.self == AnimatablePair<Double, Double>.self)
        #expect(Double.AnimatableData.self == Double.self)
        #expect(CGFloat.AnimatableData.self == CGFloat.self)
    }
}
