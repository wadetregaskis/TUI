//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimatableGeometry.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - Why these are Double when the types are Int
//
// Terminal geometry is whole cells, and every type here stores `Int`. Their
// animatable data is `Double` anyway, and that is the point: the interpolation
// is computed once per frame from the ORIGINAL endpoints — `from + (to − from)
// × t` — so the curve is evaluated at full precision and only the final
// position is rounded onto the grid. An eased move keeps its easing; it simply
// dwells longer on the cells it passes through slowly.
//
// (What would break is an interpolation that ACCUMULATED — `value += step` each
// frame — where rounding compounds. Nothing here does that.)

extension EdgeInsets: Animatable {
    /// Top and leading, then bottom and trailing — SwiftUI's own nesting.
    public typealias AnimatableData = AnimatablePair<
        AnimatablePair<Double, Double>, AnimatablePair<Double, Double>
    >

    /// The four insets, animated together.
    ///
    /// Nested pairs rather than a four-component type, which is how SwiftUI
    /// spells it too: it keeps ``VectorArithmetic`` a two-method protocol
    /// rather than a vector library.
    public var animatableData: AnimatableData {
        get {
            AnimatablePair(
                AnimatablePair(Double(top), Double(leading)),
                AnimatablePair(Double(bottom), Double(trailing)))
        }
        set {
            top = Int(clamping: newValue.first.first.rounded())
            leading = Int(clamping: newValue.first.second.rounded())
            bottom = Int(clamping: newValue.second.first.rounded())
            trailing = Int(clamping: newValue.second.second.rounded())
        }
    }
}

extension UnitPoint: Animatable {
    /// `x`, then `y`.
    public typealias AnimatableData = AnimatablePair<Double, Double>

    /// A unit point is already two continuous numbers, so this is a rename.
    public var animatableData: AnimatableData {
        get { AnimatablePair(x, y) }
        set {
            x = newValue.first
            y = newValue.second
        }
    }
}

extension CellSize: Animatable {
    /// Width and height, animated together.
    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(Double(width), Double(height)) }
        set {
            width = Int(clamping: newValue.first.rounded())
            height = Int(clamping: newValue.second.rounded())
        }
    }
}

extension CellRect: Animatable {
    /// Origin and size, animated together — a rectangle moving and resizing at
    /// once is one animation, not two.
    public var animatableData: AnimatablePair<
        AnimatablePair<Double, Double>, AnimatablePair<Double, Double>
    > {
        get {
            AnimatablePair(
                AnimatablePair(Double(x), Double(y)),
                AnimatablePair(Double(width), Double(height)))
        }
        set {
            x = Int(clamping: newValue.first.first.rounded())
            y = Int(clamping: newValue.first.second.rounded())
            width = Int(clamping: newValue.second.first.rounded())
            height = Int(clamping: newValue.second.second.rounded())
        }
    }
}
