//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalImageSignature.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - What decides whether a picture has changed

/// Everything about a request that, if it changed, means the terminal is
/// holding the wrong picture.
///
/// A typed value rather than a formatted string: the fields are already
/// `Equatable`, and comparing them directly cannot go stale the way a
/// hand-written description does when somebody adds a knob and forgets to put
/// it in the format. Getting this wrong is invisible in the good direction and
/// unmissable in the bad one — a missing field means turning a knob changes
/// nothing on screen, because the store believes it already sent this picture.
struct TerminalImageSignature: Equatable {
    /// Which picture, and at what decoded size — a source change resets the
    /// loading phase, so within one view these cannot disagree.
    var source: ImageSource
    var rawWidth: Int
    var rawHeight: Int

    /// The resolution the picture is transmitted AT — which is what decides
    /// the bytes, and is not the same question as where it goes.
    ///
    /// This used to be the cell box (`columns`, `rows`, `cellWidth`,
    /// `cellHeight`), and that made a resize a new picture: every step of a
    /// drag ran delete + transmit + place over bytes the terminal already
    /// held. The four are not dropped so much as *resolved* — `pixelWidth` and
    /// `pixelHeight` are computed from all four (`_ImageCore`: box times cell,
    /// clamped so the transmission never exceeds the source), so keying on
    /// them is strictly more precise rather than less. Two boxes that resample
    /// to the same resolution ARE the same picture, and the clamped regime
    /// makes that the common case: past the point where the placement wants
    /// more pixels than the source has, the transmitted size stops tracking
    /// the box on the binding axis and pins to the source.
    ///
    /// Where the picture GOES is the placement, and a placement is twenty
    /// bytes — see ``TerminalImageStore/placeholderRows(token:signature:columns:rows:pixels:)``.
    var pixelWidth: Int
    var pixelHeight: Int

    /// The settings `ASCIIConverter.recoloured(_:width:height:)` consults —
    /// and only those. A charset or a supersampling factor changes which
    /// GLYPH would be chosen, and there are no glyphs here, so re-transmitting
    /// megabytes for one would be work with no effect.
    var colorMode: ASCIIColorMode
    var toneCurve: ASCIIToneCurve?
    var edgeContrast: Double
    var dithering: DitheringMode

    /// The two colours ``ASCIIColorMode/mono`` is painted in (the view's
    /// `.foregroundStyle` and `.backgroundStyle`, the palette's where unstated),
    /// which for pixels are baked into the picture rather than stated around it.
    /// So a style or theme change makes a mono image a genuinely different
    /// picture, and has to re-transmit.
    ///
    /// Ignored by every other mode, so there they are PINNED to
    /// `recoloured`'s defaults (white ink, black paper) rather than omitted:
    /// `_ImageCore` makes the same test on the same requested mode that
    /// `recoloured` makes before painting them. A field that is sometimes
    /// MISSING costs a picture that will not update. A field that carries a
    /// value nothing reads costs a re-transmission for nothing: read from the
    /// palette whatever the mode, these re-sent every true-colour picture on a
    /// theme change.
    ///
    /// ## A changing ink is followed, frame by frame
    ///
    /// A mono picture re-sends whenever its ink or paper changes in 8-bit RGB,
    /// and that includes every frame of a `.foregroundStyle` fading under
    /// `withAnimation`. Each alternative is wrong somewhere worse:
    ///
    /// - Snapping to the end colour needs the animation's target, and that
    ///   belongs to the style view's store entry. The image sees only the
    ///   interpolated paint.
    /// - Holding the old picture while the ink moves cannot tell the last frame
    ///   of a fade from any other, and there is no frame after the last to send
    ///   the settled colour on.
    /// - Quantising the ink draws the settled picture in a colour nobody stated.
    ///
    /// The cost is bounded. Only `.mono` pays it (above). Only an RGB change
    /// counts: alpha is dropped, so a fade that moves only alpha is the same
    /// picture. A fade costs one re-send per frame for its length; a hover, a
    /// menu highlight or a disabled dim costs one. And the store frees a token's
    /// previous image before transmitting its next, so nothing accumulates in
    /// the terminal.
    ///
    /// **A focus breath is not followed.** A `.link` button's breath renders its
    /// label once per frame in ONE pass, each time under that frame's
    /// `.foregroundStyle` and at one identity
    /// (`BreathingLabel.draw(ends:cycle:indicating:isMeasuring:render:)`), and
    /// the runs that replay those frames repeat one image id. Followed, a mono
    /// picture there was sent once per frame on every pass that re-rendered the
    /// label, and left in the last frame's ink. So the breath publishes a
    /// ``PictureInkHold``, and the picture keeps the breath's bright end, the
    /// label's resting colour, for the whole breath. Its glyphs still breathe.
    var monoInk: RGBA
    var monoPaper: RGBA

    /// The colours the terminal had reported when the picture was recoloured.
    ///
    /// A mode that names the terminal's slots — `.ansi16`, or a `.palette` of
    /// `.ansi(_:)` entries — paints each pixel in the colour the terminal
    /// reported for its slot, or in xterm's value while it has reported none.
    /// A palette mode compares equal by its colours whatever they measure as,
    /// so without this a report arriving after the picture was sent changed the
    /// pixels and not the signature, and the terminal kept the old picture.
    ///
    /// Every mode carries it, so a report re-sends a picture that does not name
    /// a slot too. That costs one transmission per picture per report, which
    /// is rare, where leaving it out of the modes that do name one would be a
    /// picture that never updates.
    var terminalColors: TerminalColors
}

extension TerminalImageSignature: ImageStoreSignature {
    /// Which file or address: a list of different icons at one size is as
    /// many buckets as icons.
    var storeBucket: String {
        switch source {
        case .file(let path): path
        case .url(let address): address
        }
    }
}
