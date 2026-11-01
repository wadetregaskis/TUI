//  🖥️ TUI — A Terminal UI framework for Swift
//  Stepper+ValueSync.swift
//
//  What a Stepper, erased over its value's type, keeps to re-point its handler
//  each frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUIView

/// What ``Stepper`` keeps to re-point its persisted handler each frame. Its
/// requirement alone is on the main actor, where it is drawn: a value of it can
/// be made anywhere, as a stepper can.
protocol StepperValueSync {
    @MainActor func sync(_ handler: any StepperDriving, _ context: RenderContext)
}

/// The handler persists across renders; EVERYTHING this render declared must be
/// refreshed on it, not just the value binding — a stale bounds kept clamping
/// increments to a range the view no longer declared (e.g. a ceiling that grew
/// when a mode picker changed).
struct DeclaredStepperValue<V: Strideable>: StepperValueSync {
    let value: Binding<V>
    let bounds: ClosedRange<V>?
    let step: V.Stride

    @MainActor func sync(_ handler: any StepperDriving, _ context: RenderContext) {
        guard let handler = handler as? StepperHandler<V> else { return }
        // A person's steps are steps in the app's undo manager, a run of them
        // one step; the stepper's own clamp is not a person's.
        handler.value = context.undoable(value, coalescing: true, propertyIndex: StepperUndoIndex.undo)
        handler.plainValue = value
        handler.bounds = bounds
        handler.step = step
    }
}
