//  🖥️ TUI — A Terminal UI framework for Swift
//  NumericControls+Form.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Field Rows of a Form

/// A slider is a field row of a ``Form``: its label in the label column, the
/// track in the value column, as SwiftUI's form lays it out (measured,
/// `Tools/SwiftUIProbes/Form rows`). One with no label is a row in the value
/// column all the same.
@MainActor extension Slider: FormFieldControl {
    package func formFieldParts(in environment: EnvironmentValues) -> (label: AnyView, control: AnyView)? {
        // The label resolves `.sliderTextStyle` in the column as beside the
        // track, and dims with a disabled slider.
        let detached = _DetachedControlLabel(label: label, controlDisabled: isDisabled)
        return (AnyView(detached.environment(\.controlKind, .slider)), AnyView(labelsHidden()))
    }
}

/// A stepper is a field row of a ``Form``: its label in the label column, the
/// arrows and the value in the value column, as SwiftUI's form lays it out
/// (measured, `Tools/SwiftUIProbes/Form rows`).
@MainActor extension Stepper: FormFieldControl {
    package func formFieldParts(in environment: EnvironmentValues) -> (label: AnyView, control: AnyView)? {
        let detached = _DetachedControlLabel(label: label, controlDisabled: isDisabled)
        return (AnyView(detached.environment(\.controlKind, .stepper)), AnyView(labelsHidden()))
    }
}
