//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FieldChrome.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Field chrome

/// The caps a styled field draws around its content, and what they cost.
///
/// One type because `TextField` and `SecureField` draw the same chrome from
/// two `_*Core` views: the arithmetic has to appear in four places (each
/// view's `sizeThatFits` and `renderToBuffer`), and four copies of "the caps
/// are two cells" is exactly how a measure and a render come to disagree.
@MainActor
struct FieldChrome {
    /// The cells the caps occupy in total — 2 with a surface, 0 without.
    let width: Int

    /// The leading cap, or `""` for a plain field.
    let open: String

    /// The trailing cap, or `""`.
    let close: String

    /// The field's surface colour, or `nil` when the style draws none.
    let surface: Color?

    /// The colour the caps are painted in, or `nil` for a style that draws none.
    ///
    /// Kept beside the bytes because the bytes state its OPAQUE spelling and the alpha
    /// has to reach the compositor separately — see ``claims(lineWidth:)``. It is the
    /// field surface, or the surface lerped toward the accent while hovered, so a
    /// palette that fades its page fades these too now that a derived surface carries
    /// the page's alpha (§39).
    let capColor: Color?

    /// Cells before the content starts — the leading cap, or none.
    ///
    /// Everything positioned against the content reads this rather than
    /// assuming 1: the caret's animated cells, the combo-box disclosure's click
    /// range, and the click-to-caret column mapping. A plain field's content
    /// starts at column 0, and each of those was an off-by-one waiting to
    /// happen.
    var leadingCells: Int { width / 2 }

    /// Cells after the content ends — the trailing cap, or none.
    ///
    /// The combo box's click target reaches through it: the cap is a single
    /// cell hard against the `▾`, and a click one cell wide of a two-cell
    /// target is a miss the pointer has no way to see coming.
    var trailingCells: Int { width - leadingCells }

    /// Builds the chrome for a style, tinting the caps toward the accent while
    /// hovered so the affordance reads as "clickable" without mimicking the
    /// focused look.
    /// - Parameter background: what the field is drawn ON — the page, or the
    ///   surface of a container that painted one (a `TabView`'s body). The
    ///   field's own surface is derived from it, so a field inside a tab does
    ///   not come out the same colour as the tab.
    init(
        style: any TextFieldStyle, palette: any Palette, isHovered: Bool,
        on background: Color? = nil
    ) {
        guard style.drawsFieldSurface else {
            self.width = 0
            self.open = ""
            self.close = ""
            self.surface = nil
            self.capColor = nil
            return
        }
        let surface =
            (background.map { palette.fieldBackground(on: $0) } ?? palette.fieldBackground)
            .resolve(with: palette)
        let capColor =
            isHovered
            ? Color.lerp(surface, palette.accent.resolve(with: palette), phase: 0.35)
            : surface
        self.width = 2
        let caps = Self.caps(in: capColor.opaqueSpelling)
        self.open = caps.open
        self.close = caps.close
        self.surface = surface
        self.capColor = capColor
    }

    /// The pair of caps last spelled, with everything their bytes are a function of.
    private struct SpelledCaps {
        let color: Color
        let depth: ColorDepth
        /// By value, as `ScrollbarMemo.Key` keeps it: at sixteen colours an RGB
        /// colour is spelled as the slot nearest what the terminal REPORTED that
        /// slot paints, and a task-local pin changes the report without moving
        /// `TerminalColors.generation`.
        let terminal: TerminalColors
        let open: String
        let close: String
    }

    /// The caps last spelled. Main-actor state, like the chrome itself.
    private static var lastCaps: SpelledCaps?

    /// The two caps in `color`, spelled once per colour, depth and terminal report
    /// rather than twice per field per render.
    ///
    /// The glyphs are constants, so the bytes are a function of the colour, the
    /// depth the emitter quantises to and the terminal's report — and nothing else.
    /// Every unhovered field on a page has the same cap colour, so the last pair
    /// answers almost every field: the spelling (a `TextStyle`, its introducer
    /// derived, twice) was 5.3% of a page of 200 fields. A miss — a hovered field's
    /// lerped colour, a palette or depth change — spells them as `colorize` does.
    private static func caps(in color: Color) -> (open: String, close: String) {
        let depth = ColorDepth.current
        let terminal = TerminalColors.current
        if let last = lastCaps, last.color == color, last.depth == depth, last.terminal == terminal {
            return (last.open, last.close)
        }
        // One introducer for the pair, wrapped as `colorize` wraps (`ANSIRenderer.wrap`
        // is what `render` returns), as a button's caps are.
        var style = TextStyle()
        style.foregroundColor = color
        let sequence = ANSIRenderer.styleSequence(for: style)
        let open = ANSIRenderer.wrap(String(TerminalSymbols.openCap), in: sequence)
        let close = ANSIRenderer.wrap(String(TerminalSymbols.closeCap), in: sequence)
        lastCaps = SpelledCaps(color: color, depth: depth, terminal: terminal, open: open, close: close)
        return (open, close)
    }

    /// What the caps owe on a field line `lineWidth` cells wide.
    ///
    /// Here rather than at the two call sites, because the trailing cap's column is
    /// `lineWidth - trailingCells` and this is the type that knows what
    /// ``trailingCells`` is — `TextField` and `SecureField` would each have re-derived
    /// it, which is how the two drift.
    ///
    /// The caps are half-block glyphs with no background of their own, so this is an
    /// INK claim. The field's surface is claimed by the content renderer, which is what
    /// paints it (§30).
    func claims(lineWidth: Int) -> [OpacityRegion] {
        guard let capColor, width > 0 else { return [] }
        return [
            OpacityRegion.claim(width: leadingCells, height: 1, ink: capColor),
            OpacityRegion.claim(
                offsetX: lineWidth - trailingCells, width: trailingCells, height: 1,
                ink: capColor),
        ].compactMap { $0 }
    }

    /// The chrome width for a style, without building the glyphs — what
    /// `sizeThatFits` needs, where there is no palette and nothing to draw.
    static func width(for style: any TextFieldStyle) -> Int {
        style.drawsFieldSurface ? 2 : 0
    }
}
