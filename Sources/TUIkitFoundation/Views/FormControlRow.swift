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
