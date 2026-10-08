//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PictureInkHold.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - A breathing label's pictures

/// The one ink a picture keeps while the label it sits in breathes.
///
/// A breathing label (`BreathingLabel.draw(ends:cycle:indicating:isMeasuring:render:)`)
/// is rendered once per frame of its breath, each time under that frame's
/// `.foregroundStyle`, and the run loop replays the rows. Glyphs breathe that
/// way. A picture cannot: its pixels carry the ink, so each frame's render is a
/// different picture, while the rows a run replays name ONE image id. Followed,
/// the store sent every frame's picture on every pass that re-rendered the label,
/// and the terminal kept whichever came last.
///
/// So on the pixel path a picture holds ``held`` for the whole breath. The breath
/// hands it the bright end, which is the colour the label rests in without the
/// focus and the colour a focus draws under `.selectionIndicatorStyle(.none)`, so
/// the breath starting or stopping sends nothing either. Nor does the window
/// losing the terminal's focus: the label's glyphs then hold still half-way
/// between the ends (`SelectionEmphasis.held(_:)`), and the picture stays at the
/// bright end rather than being re-sent in that shade.
///
/// The hold applies only while the ink in force is the breath's own ``breath``
/// colour, compared in the 8-bit RGB the picture would bake. A picture that
/// states its own ink inside the label, or sits under a control that states one,
/// keeps that ink. The comparison cannot tell a stated ink that equals the
/// current frame's colour exactly from the breath's: that picture takes ``held``
/// in that one frame's render and its own ink in the others, and re-sends
/// between them.
struct PictureInkHold: Equatable, Sendable {
    /// The ink this render of the label breathes in.
    let breath: Color
    /// The ink a picture keeps instead.
    let held: Color
}

private struct PictureInkHoldKey: EnvironmentKey {
    static let defaultValue: PictureInkHold? = nil
}

extension EnvironmentValues {
    /// The hold a breathing label publishes to the pictures in it, or `nil`
    /// outside a breath. See ``PictureInkHold``.
    var pictureInkHold: PictureInkHold? {
        get { self[PictureInkHoldKey.self] }
        set { self[PictureInkHoldKey.self] = newValue }
    }
}

extension View {
    /// This view in one frame of a breath: `.foregroundStyle(breath)`, with any
    /// picture inside keeping `held` instead. Both halves in one call, so a
    /// breath cannot publish one without the other. See ``PictureInkHold``.
    func breathingForegroundStyle(_ breath: Color, holdingPicturesAt held: Color) -> some View {
        foregroundStyle(breath)
            .environment(\.pictureInkHold, PictureInkHold(breath: breath, held: held))
    }
}
