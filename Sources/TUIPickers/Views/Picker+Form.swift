//  🖥️ TUI — A Terminal UI framework for Swift
//  Picker+Form.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Field Rows of a Form

/// A picker of any style is a field row of a ``Form``: its label in the label
/// column, the control in the value column — a menu's pop-up button, a
/// segmented control, a radio group — as SwiftUI's form lays out each of them
/// (measured, `Tools/SwiftUIProbes/Form rows`).
@MainActor extension Picker: FormFieldControl {
    package func formFieldParts(in environment: EnvironmentValues) -> (label: AnyView, control: AnyView)? {
        // The label resolves `.pickerTextStyle` in the column as beside the
        // control, and dims with a picker that is disabled or has no sources.
        let detached = _DetachedControlLabel(label: label, controlDisabled: isDisabled || hasNoSources)
        return (AnyView(detached.environment(\.controlKind, .picker)), AnyView(labelsHidden()))
    }
}

/// A date picker is a field row of a ``Form`` under a built-in style, as
/// SwiftUI's form lays it out (measured, `Tools/SwiftUIProbes/Form rows`). A
/// style of the app's own places the label itself, so the picker is then a row
/// drawn whole.
@MainActor extension DatePicker: FormFieldControl {
    package func formFieldParts(in environment: EnvironmentValues) -> (label: AnyView, control: AnyView)? {
        guard environment.datePickerStyle is any BuiltInDatePickerStyle else { return nil }
        return (AnyView(_DetachedControlLabel(label: label, controlDisabled: isDisabled)), AnyView(labelsHidden()))
    }
}
