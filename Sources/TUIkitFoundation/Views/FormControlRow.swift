//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormControlRow.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Row-kind markers

/// A self-labelled control that a ``Form`` places in the control column with its
/// own clickable label (a checkbox/radio), rather than pulling a label to the
/// pillar. Conformed by ``Toggle`` and ``RadioButtonGroup``.
@MainActor
package protocol FormControlRow {
    /// The control's label and the control without it, for a grouped form,
    /// which lays a self-labelled control's row out as it lays a
    /// `LabeledContent`'s — the label at the leading edge, the control at the
    /// trailing one, as SwiftUI's grouped form does (measured, a `Toggle`'s
    /// checkbox at the trailing edge); `nil` for a control with no label of its
    /// own to move.
    var groupedFormRowParts: (label: AnyView, control: AnyView)? { get }
}

extension FormControlRow {
    package var groupedFormRowParts: (label: AnyView, control: AnyView)? { nil }
}

extension Toggle: FormControlRow {
    /// The label, and the checkbox with its label hidden.
    package var groupedFormRowParts: (label: AnyView, control: AnyView)? {
        (AnyView(label), AnyView(labelsHidden()))
    }
}

/// A labelled control a ``Form`` lays out as a field row: its label in the
/// label column, right-aligned to the others, and the control, its own label
/// hidden, in the value column after it — or, in a grouped form, the label at
/// the row's leading edge and the control at its trailing one. SwiftUI's form
/// lays out a `Picker` of every style, a `Slider`, a `Stepper`, a `DatePicker`
/// and a `ColorPicker` so (measured on macOS 15.8,
/// `Tools/SwiftUIProbes/Form rows`), and those five conform.
@MainActor
package protocol FormFieldControl {
    /// The control's label, as the label column draws it, and the control
    /// without it — or `nil` where the control is no field row in
    /// `environment`, the environment the form reads the row in: a date
    /// picker drawn by a style of the app's own, which places its label
    /// itself.
    func formFieldParts(in environment: EnvironmentValues) -> (label: AnyView, control: AnyView)?
}
