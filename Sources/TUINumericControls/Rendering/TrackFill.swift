//  🖥️ TUI — A Terminal UI framework for Swift
//  TrackFill.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// What a gauge's or a progress bar's lit part is painted with: the tint,
/// where one is stated (``View/tint(_:)-(S?)``), and otherwise the palette's
/// quiet `foregroundSecondary` — TUI's own untinted look, which leaves the
/// accent to what the user acts on (SwiftUI fills an untinted bar with the
/// accent).
///
/// A gradient tint is painted along the control as a ramp: across a bar, the
/// whole track's length, so the fill uncovers it as it grows (``TrackGradientScaling/track``);
/// around a ring, its turn. Where only one colour can be drawn — a dot's head,
/// an indeterminate sweep — it stands as its representative.
struct TrackFill: Equatable {
    /// The one colour to draw with.
    let colour: Color
    /// The tint's ramp, where it was a gradient.
    let ramp: Gradient?

    /// How far toward the background a gradient-tinted ring's unlit cells
    /// are mixed: faint, and still the ramp's hue.
    static let unlitRampFade = 0.6

    init(environment: EnvironmentValues, palette: any Palette) {
        guard let paint = environment.tintPaint else {
            colour = palette.foregroundSecondary
            ramp = nil
            return
        }
        colour = paint.representative
        if case .gradient(let gradient) = paint, gradient.gradient.stops.count >= 2 {
            ramp = gradient.gradient
        } else {
            ramp = nil
        }
    }
}
