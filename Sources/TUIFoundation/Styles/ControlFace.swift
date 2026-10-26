//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlFace.swift
//
//  A bordered button's face round a string, for a control that is a button in
//  everything but its type.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// A bordered button's face drawn round a string, exactly as the default
/// button style draws one — for a control that is a button in all but type: a
/// pop-up `Picker`'s closed control, which on a Mac is a pop-up BUTTON.
///
/// So the control follows everything a button's face does: the
/// ``Appearance``'s family (lines, solid, Braille, blank), the
/// ``ControlSize`` and the ``ButtonBorderShape`` in force, the breath while it
/// holds the focus, the lift under the pointer. A control that drew its own
/// half-block caps read as solid beside buttons drawn in lines.
package enum ControlFace {
    /// The appearance a face takes in `environment`: the default button's, at
    /// the size, shape and family in force.
    private static func appearance(in environment: EnvironmentValues) -> _ButtonAppearance {
        _ButtonAppearance.default.sized(
            environment.controlSize, shape: environment.buttonBorderShape,
            family: ButtonFaceFamily(environment),
            raster: SolidRaster(environment),
            segment: environment.isControlSegment)
    }

    /// The cells a face adds across its title, and the rows it is tall, in
    /// `environment` — what a control sizes itself with before it draws.
    @MainActor
    package static func chrome(in environment: EnvironmentValues) -> (width: Int, rows: Int) {
        let appearance = appearance(in: environment)
        return (_ButtonStyleBody.chromeWidth(for: appearance), appearance.edges.rows)
    }

    /// The face round `title`, which the caller has already fitted: drawn at
    /// the width the title and the chrome take, whatever ``ButtonSizing`` is in
    /// force — the control decides its own width.
    @MainActor
    package static func draw(
        _ title: String, focused: Bool, hovered: Bool, enabled: Bool, context: RenderContext
    ) -> FrameBuffer {
        var context = context
        context.environment.buttonSizing = .fitted
        context.availableWidth = max(context.availableWidth, title.strippedLength + chrome(in: context.environment).width)
        let body = _ButtonStyleBody(
            configuration: ButtonStyleConfiguration(
                title: title, labelView: nil, role: nil, isPressed: false,
                isFocused: focused, isHovered: hovered && enabled, isEnabled: enabled, keyboardShortcut: nil),
            appearance: .default)
        return body.renderToBuffer(context: context)
    }
}
