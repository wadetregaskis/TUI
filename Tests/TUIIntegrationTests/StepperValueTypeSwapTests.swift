//  🖥️ TUI — A Terminal UI framework for Swift
//  StepperValueTypeSwapTests.swift
//
//  A `Stepper` drawn at one place over a value of another type steps that
//  value (CTRLS-9, H-09).
//
//  Its handler is kept at its place erased over the value's type, and each
//  frame points it at the binding drawn; a handler of the old type failed the
//  cast and was left as it was, so the arrows stepped the old binding within
//  the old bounds while the read-out showed the new value.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

/// Swaps the stepper from outside, between frames.
@MainActor
private final class Swap {
    var usesDouble: Binding<Bool>?
}

/// One stepper, over an `Int` or a `Double` by a flag: both a `Stepper<Text>`,
/// erased alike, so they share a place.
private struct Steppers: View {
    @State private var usesDouble = false
    @State private var whole = 3
    @State private var fraction = 0.5
    let swap: Swap

    var body: some View {
        swap.usesDouble = $usesDouble
        return VStack(alignment: .leading) {
            Text(verbatim: "whole \(whole) fraction \(fraction)")
            stepper
        }
    }

    private var stepper: AnyView {
        usesDouble
            ? AnyView(Stepper("Step", value: $fraction, in: 0...10, step: 0.25))
            : AnyView(Stepper("Step", value: $whole, in: 0...10))
    }
}

@MainActor
@Suite("A Stepper over a value of another type")
struct StepperValueTypeSwapTests {
    @Test("Its arrows step the value it is drawn over")
    func stepsTheValueDrawn() {
        let swap = Swap()
        let app = TestApp(width: 40, height: 6) { Steppers(swap: swap) }
        _ = app.press(.tab)
        _ = app.press(.right)
        #expect(app.screen.contains("whole 4 fraction 0.5"), "precondition: \(app.screen)")
        swap.usesDouble?.wrappedValue = true
        _ = app.screen
        _ = app.press(.right)
        #expect(app.screen.contains("whole 4 fraction 0.75"), "\(app.screen)")
    }
}
