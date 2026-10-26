//  🖥️ TUI — A Terminal UI framework for Swift
//  Stepper+ValueWidth.swift
//
//  How many cells a stepper's read-out reserves, so ▶ does not move as the
//  value gains a digit (owner ruling STEPPER-WIDTH, option 1, 2026-10-23).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

private struct StepperValueWidthKey: EnvironmentKey {
    /// Fit the bounds: see ``TUI/View/stepperValueWidth(_:)``.
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// How many cells a ``Stepper``'s read-out reserves, or `nil` to fit its
    /// bounds. See ``TUI/View/stepperValueWidth(_:)``.
    public var stepperValueWidth: Int? {
        get { self[StepperValueWidthKey.self] }
        set { self[StepperValueWidthKey.self] = newValue }
    }
}

extension View {
    /// Sets how many cells the read-out of every ``Stepper`` in this view
    /// reserves between its arrows.
    ///
    /// TUI's stepper draws its value, `◀ 9 ▶`, so a value that gains a digit
    /// would push ▶ a cell to the right — under a pointer that may be holding
    /// it down to repeat. By default (`nil`) a stepper with bounds reserves the
    /// width of the wider of its two ends, formatted as the value is, and one
    /// with no bounds reserves nothing. A narrower value stands at the trailing
    /// edge, so its digits keep their places: `◀  9 ▶`, `◀ 10 ▶`. A value wider
    /// than the reservation still shows whole, and widens the stepper.
    ///
    /// ```swift
    /// Stepper("Retries", value: $retries)   // no bounds: nothing reserved
    ///     .stepperValueWidth(3)             // ▶ holds still up to 999
    /// ```
    ///
    /// TUI-specific: SwiftUI's stepper draws no value, its ± at the trailing
    /// edge after a label that may widen.
    ///
    /// - Parameter width: The cells to reserve, `0` for none, or `nil` to fit
    ///   the bounds.
    /// - Returns: A view whose steppers reserve `width` cells for their value.
    public func stepperValueWidth(_ width: Int?) -> some View {
        environment(\.stepperValueWidth, width.map { max(0, $0) })
    }
}
