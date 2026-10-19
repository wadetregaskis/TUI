//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FieldChrome.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Field chrome

/// The caps a styled field draws around its content, and what they cost.
///
/// One type because `TextField` and `SecureField` draw the same chrome from
/// two `_*Core` views: the arithmetic has to appear in four places (each
/// view's `sizeThatFits` and `renderToBuffer`), and four copies of "the caps
/// are two cells" is exactly how a measure and a render come to disagree.
@MainActor
struct FieldChrome {
    /// The cells the caps occupy in total — 2 with a surface, 0 without, or at
    /// `.mini`, where a field draws no caps.
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

    /// The field's surface under the caps, or `nil` where they are half-blocks
    /// in the surface's colour, which have no background of their own.
    let capField: Color?

    /// Builds the chrome for a style, tinting the caps toward the accent while
    /// hovered so the affordance reads as "clickable" without mimicking the
    /// focused look.
    ///
    /// The caps follow the appearance's family, as a button's do. Under an
    /// appearance of lines — `.rounded`, the default — they are its vertical
    /// line, in the border's colour, on the field's surface — `│text│`, the
    /// fill saying the field is editable and the lines matching every other
    /// control's, the line in the middle of its cell leaving half a cell
    /// between it and the text. Otherwise they are half-blocks in the
    /// surface's colour, `▐text▌`, which round the surface off. Either way
    /// they are a cell each, so a field is as wide under every appearance.
    /// - Parameters:
    ///   - background: what the field is drawn ON — the page, or the surface
    ///     of a container that painted one (a `TabView`'s body). The field's
    ///     own surface is derived from it, so a field inside a tab does not
    ///     come out the same colour as the tab.
    ///   - appearance: The appearance in force, whose family the caps follow.
    ///   - drawsCaps: Whether the control size in force draws a control's end
    ///     caps (``ControlSize/drawsEndCaps``): not at `.mini`, where a field is
    ///     its surface alone, as a mini button is its label alone.
    init(
        style: any TextFieldStyle, palette: any Palette, isHovered: Bool,
        on background: Color? = nil, appearance: Appearance, drawsCaps: Bool
    ) {
        guard style.drawsFieldSurface else {
            self.width = 0
            self.open = ""
            self.close = ""
            self.surface = nil
            self.capColor = nil
            self.capField = nil
            return
        }
        let surface =
            (background.map { palette.fieldBackground(on: $0) } ?? palette.fieldBackground)
            .resolve(with: palette)
        self.surface = surface
        guard drawsCaps else {
            // The surface alone: the content renderer paints it, and claims it.
            self.width = 0
            self.open = ""
            self.close = ""
            self.capColor = nil
            self.capField = nil
            return
        }
        self.width = 2
        if let lines = appearance.controlLines {
            let border = palette.border.resolve(with: palette)
            let ink = isHovered ? Color.lerp(border, palette.accent.resolve(with: palette), phase: 0.35) : border
            let caps = Self.caps(
                (String(lines.vertical), String(lines.vertical)), in: ink.opaqueSpelling, on: surface.opaqueSpelling)
            self.open = caps.open
            self.close = caps.close
            self.capColor = ink
            self.capField = surface
        } else {
            let capColor =
                isHovered
                ? Color.lerp(surface, palette.accent.resolve(with: palette), phase: 0.35)
                : surface
            let caps = Self.caps(
                (String(TerminalSymbols.openCap), String(TerminalSymbols.closeCap)), in: capColor.opaqueSpelling,
                on: nil)
            self.open = caps.open
            self.close = caps.close
            self.capColor = capColor
            self.capField = nil
        }
    }

    /// The chrome a field draws in `environment`: its style, palette, the
    /// surface it is drawn on, the appearance and the control size in force —
    /// what every field's measure and render read, in one place.
    init(isHovered: Bool, in environment: EnvironmentValues) {
        self.init(
            style: environment.textFieldStyle, palette: environment.palette, isHovered: isHovered,
            on: environment.surfaceBackground, appearance: environment.appearance,
            drawsCaps: environment.controlSize.drawsEndCaps)
    }

    /// The pair of caps last spelled, with everything their bytes are a function of.
    private struct SpelledCaps {
        let glyphs: (open: String, close: String)
        let color: Color
        let field: Color?
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

    /// The two caps, `glyphs` in `color` on `field`, spelled once per glyphs,
    /// colours, depth and terminal report rather than twice per field per render.
    ///
    /// The bytes are a function of the glyphs, the colours, the depth the emitter
    /// quantises to and the terminal's report — and nothing else.
    /// Every unhovered field on a page has the same cap colour, so the last pair
    /// answers almost every field: the spelling (a `TextStyle`, its introducer
    /// derived, twice) was 5.3% of a page of 200 fields. A miss — a hovered field's
    /// lerped colour, a palette or depth change — spells them as `colorize` does.
    private static func caps(
        _ glyphs: (open: String, close: String), in color: Color, on field: Color?
    ) -> (open: String, close: String) {
        let depth = ColorDepth.current
        let terminal = TerminalColors.current
        if let last = lastCaps, last.glyphs == glyphs, last.color == color, last.field == field, last.depth == depth,
            last.terminal == terminal
        {
            return (last.open, last.close)
        }
        // One introducer for the pair, wrapped as `colorize` wraps (`ANSIRenderer.wrap`
        // is what `render` returns), as a button's caps are.
        var style = TextStyle()
        style.foregroundColor = color
        style.backgroundColor = field
        let sequence = ANSIRenderer.styleSequence(for: style)
        let open = ANSIRenderer.wrap(glyphs.open, in: sequence)
        let close = ANSIRenderer.wrap(glyphs.close, in: sequence)
        lastCaps = SpelledCaps(
            glyphs: glyphs, color: color, field: field, depth: depth, terminal: terminal, open: open, close: close)
        return (open, close)
    }

    /// What the caps owe on a field line `lineWidth` cells wide.
    ///
    /// Here rather than at the two call sites, because the trailing cap's column is
    /// `lineWidth - trailingCells` and this is the type that knows what
    /// ``trailingCells`` is — `TextField` and `SecureField` would each have re-derived
    /// it, which is how the two drift.
    ///
    /// Half-block caps have no background of their own, so they make an INK claim;
    /// line caps are drawn on the field's surface, and claim it too. The rest of the
    /// surface is claimed by the content renderer, which is what paints it (§30).
    func claims(lineWidth: Int) -> [OpacityRegion] {
        guard let capColor, width > 0 else { return [] }
        return [
            OpacityRegion.claim(width: leadingCells, height: 1, ink: capColor, field: capField),
            OpacityRegion.claim(
                offsetX: lineWidth - trailingCells, width: trailingCells, height: 1,
                ink: capColor, field: capField),
        ].compactMap { $0 }
    }

    /// The chrome width for a style, without building the glyphs — what
    /// `sizeThatFits` needs, where there is no palette and nothing to draw.
    static func width(for style: any TextFieldStyle, drawsCaps: Bool) -> Int {
        style.drawsFieldSurface && drawsCaps ? 2 : 0
    }
}
