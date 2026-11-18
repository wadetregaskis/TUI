//  🖥️ TUI — A Terminal UI framework for Swift
//  TextField+Form.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Field Rows of a Form

/// A text field is a field row of a ``Form``: its title in the label column,
/// the field in the value column, as SwiftUI's form lays it out in both styles
/// (measured on macOS 15.8, `Tools/SwiftUIProbes/Form rows/rows.out` and
/// `textfield-title.out`). The title is then no placeholder: only a prompt is,
/// as in SwiftUI's form, where `TextField("Name", text: $name)` has none and
/// `TextField("Name", text: $name, prompt: Text("Required"))` shows "Required".
/// An empty title is a row in the value column all the same. It was a plain
/// row, the title only the empty field's placeholder, so the field lost it as
/// soon as anything was typed.
@MainActor extension TextField: FormFieldControl {
    package func formFieldParts(in environment: EnvironmentValues) -> (label: AnyView, control: AnyView)? {
        var field = self
        field.titleIsPlaceholder = false
        return (AnyView(_DetachedControlLabel(label: label, controlDisabled: isDisabled)), AnyView(field))
    }
}

/// A secure field is a field row of a ``Form`` as a ``TextField`` is
/// (measured, `Tools/SwiftUIProbes/Form rows/textfield-title.out`).
@MainActor extension SecureField: FormFieldControl {
    package func formFieldParts(in environment: EnvironmentValues) -> (label: AnyView, control: AnyView)? {
        var field = self
        field.titleIsPlaceholder = false
        return (AnyView(_DetachedControlLabel(label: label, controlDisabled: isDisabled)), AnyView(field))
    }
}
