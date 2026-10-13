//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _ButtonStyleBody.swift
//
//  The procedural rendering core of the built-in button styles.
//
//  Created by LAYERED.work
//  License: MIT

/// The procedural rendering core shared by the built-in button styles.
///
/// - Important: Framework infrastructure. The built-in ``ButtonStyle`` types
///   return this from `makeBody`; it is never used directly.
struct _ButtonStyleBody: View, Renderable {
    /// The button being styled.
    let configuration: ButtonStyleConfiguration

    /// The resolved visual parameters to draw with.
    let appearance: _ButtonAppearance

    var body: Never {
        fatalError("_ButtonStyleBody renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A `@ViewBuilder` label renders via view composition, preserving its own
        // styling; plain string labels keep the procedural path below unchanged.
        if let labelView = configuration.labelView {
            return renderViewLabel(labelView, context: context)
        }

        let palette = context.environment.palette
        // What the ink lands on, which is the page only until a container
        // paints something — a `TabView` body is on the strip's own surface.
        let surface = context.environment.enclosingSurface
        let isDisabled = !configuration.isEnabled
        let isFocused = configuration.isFocused
        // Focus and hover are two different questions — where the KEYBOARD
        // goes, and where the MOUSE would — so a button that is both shows
        // both. They do not compete here because they are answered in
        // different ink: focus moves the caps (pulsing them to accent) and the
        // weight, hover moves the FACE. Disabled buttons never show hover
        // (Button._ButtonCore clamps it to false before constructing the
        // configuration).
        let isHovered = configuration.isHovered

        // A destructive role always wins on colour, matching SwiftUI, where
        // the role overrides whatever tint the style would otherwise use.
        let baseForeground: Color? =
            configuration.role == .destructive
            ? Color.palette.error
            : appearance.foregroundColor

        // Scoped style cascade for this button (.control(.button) + this style's
        // variant). The label's colour/weight inherit it as soft overrides — but
        // a destructive role's error colour stays load-bearing (not broadly
        // overridable), so it's excluded from the cascade foreground.
        let cascaded = context.environment.styleCascade.resolve(
            for: [.all, .text, .control(.button), .controlVariant(.button, appearance.variant)])
        let cascadeForeground: Color? =
            configuration.role == .destructive ? nil : cascaded.foreground

        // Focused buttons render bold — this replaces the old explicit "focused
        // style" that was a bold variant of the normal style. A cascade `.bold`
        // (e.g. `.buttonTextStyle { $0.bold = true }`) adds to that.
        let isBold = appearance.isBold || isFocused || (cascaded.bold ?? false)

        let padding = String(repeating: " ", count: appearance.horizontalPadding)

        // Plain: focus indicator prefix + label, no brackets, no background.
        if appearance.isPlain {
            return renderPlainStringLabel(
                context: context,
                StringLabelState(
                    palette: palette, surface: surface, cascadeForeground: cascadeForeground,
                    baseForeground: baseForeground, isDisabled: isDisabled, isFocused: isFocused,
                    isHovered: isHovered, isBold: isBold, padding: padding))
        }

        // The standard variant wraps the label in `▐ … ▌` end caps plus
        // `horizontalPadding` cells of padding either side. If the cell
        // can't fit the full label the label is ellipsis-truncated so
        // the caps still align and the truncation is visible to the user.
        let chromeWidth = Self.chromeWidth(for: appearance)
        let labelText = Self.fitLabel(
            configuration.title, into: context.availableWidth, chrome: chromeWidth)
        let paddedLabel = Self.filling(
            padding + labelText + padding, context: context, caps: chromeWidth - 2 * padding.count)

        // Standard: half-block caps around an accent-tinted
        // background. Hover bumps the tint slightly so the
        // affordance reads as "I am clickable" without the
        // pulsing animation that focus uses.
        let buttonBg = isHovered ? palette.hoveredControlFace : palette.restingControlFace

        // Label foreground: a scoped cascade colour wins (in every state);
        // otherwise the style/role's own colour is used in every state too. A
        // semantic tint — a destructive button's error red, a success button's
        // green — is load-bearing: it must not drop to a neutral grey just
        // because the button is unfocused, or `.buttonStyle(.destructive)` would
        // be indistinguishable from `.default` until focused (and a bare
        // `role: .destructive` likewise). Focus changes the *weight* (`isBold`,
        // applied below) and the caps/background pulse, not whether the tint
        // shows. The default style's own colour already IS `foregroundSecondary`,
        // so an unfocused default button still reads as a dim, recessive control.
        // Framework-chosen colours are floored (hue-preserving) against the
        // face they sit on — a mid-tone palette's secondary text over its
        // accent-tinted face can land tone-on-tone (Red Sands' parchment on
        // gold-over-brick). An explicit cascade colour is the app author's
        // and is left alone.
        let labelFg: Color
        if isDisabled {
            // Floored against the FACE, like every other framework-chosen
            // colour here. The fade is computed over the page background — the
            // recessive look this state wants — but the label is painted on
            // the button's accent tint, and unfloored the two land 1.0–1.6:1
            // apart on every built-in palette. Five of them then quantise to
            // the same 256-colour entry and the label disappears completely.
            labelFg = palette.foregroundTertiary
                .opacity(ViewConstants.disabledForeground, over: palette.background)
                .ensuringRenderedContrast(
                    atLeast: ViewConstants.disabledLabelContrastFloor, against: buttonBg)
        } else if let cascadeForeground {
            // On a face that cannot be measured the hover has no fill to show, so the
            // label lifts instead, the app's colour too: it is then the only thing that
            // can answer the pointer, as on a plain button (Opacity as composition §82).
            let ink = cascadeForeground.resolve(with: palette)
            labelFg = isHovered ? palette.hoveredLabel(ink) : ink
        } else {
            let ink = (baseForeground?.resolve(with: palette) ?? palette.foregroundSecondary)
                .ensuringRenderedContrast(atLeast: ViewConstants.labelContrastFloor, against: buttonBg)
            labelFg = isHovered ? palette.hoveredLabel(ink) : ink
        }

        // Caps match the background normally, pulsing to accent when focused —
        // as a whole cycle, so the run loop can breathe those two cells without
        // re-rendering the screen. On a face the terminal decides they rest in
        // the tertiary tier and hold the accent instead. See ``ButtonCapCycle``.
        let caps = ButtonCapCycle(
            isFocused: isFocused && !isDisabled,
            background: buttonBg, palette: palette, context: context)

        // The caps are always opaque: both faces are composites over the page, or
        // an opaque accent kept at its own spelling (`hoveredControlFace`, §49),
        // and `ButtonCapCycle` spends a translucent tint's or tier's alpha against
        // that face, so every phase of the breath states a concrete colour (§29).
        // They therefore need no spelling and earn no claim.
        //
        // One introducer for the pair: both caps are the same colour, and a
        // `colorize` each derived the identical sequence twice per button per
        // render. Wrapped as `colorize` wraps (`ANSIRenderer.wrap` is what
        // `render` returns), so the bytes are the same.
        var capStyle = TextStyle()
        capStyle.foregroundColor = caps.colorNow
        let capSequence = ANSIRenderer.styleSequence(for: capStyle)
        let openCap = ANSIRenderer.wrap(String(TerminalSymbols.openCap), in: capSequence)
        let closeCap = ANSIRenderer.wrap(String(TerminalSymbols.closeCap), in: capSequence)
        // The label's ink is not: `labelFg` is the app author's cascade colour
        // where there is one, left unfloored on purpose, or a palette slot through
        // `ensuringRenderedContrast`, a re-spelling that carries its alpha (§28).
        // The face is opaque (above), so as the field it claims nothing.
        let styledLabel = ANSIRenderer.colorize(
            paddedLabel,
            foreground: labelFg.opaqueSpelling,
            background: buttonBg.opaqueSpelling,
            // A tier heavier under a bold legibility weight, as every label is.
            bold: context.environment.legibilityWeight.applied(bold: isBold && !isDisabled, faint: false).bold
        )

        var buffer = FrameBuffer(lines: [openCap + styledLabel + closeCap])
        // Between the caps: one cell in, and exactly the label's own width. The
        // caps are their own colour and, while the button holds the focus, their
        // own runs — so they are never part of this rectangle.
        if let claim = OpacityRegion.claim(
            offsetX: 1, width: paddedLabel.strippedLength, height: 1,
            ink: labelFg, field: buttonBg)
        {
            buffer.opacityRegions.append(claim)
        }
        if !context.isMeasuring {
            buffer.animatedCells = caps.runs(width: 2 + paddedLabel.strippedLength)
        }
        return buffer
    }
    /// What the string-label path resolved before it chose a variant: the state and
    /// the colours the plain arm draws from.
    ///
    /// A struct rather than nine parameters, because nine parameters is not a
    /// signature — and because these are one thing (what this button looks like
    /// right now) rather than nine unrelated ones.
    private struct StringLabelState {
        let palette: any Palette
        /// What the ink lands on, which is not the page wherever a container
        /// painted one.
        let surface: Color
        let cascadeForeground: Color?
        let baseForeground: Color?
        let isDisabled: Bool
        let isFocused: Bool
        let isHovered: Bool
        let isBold: Bool
        let padding: String
    }

    /// The PLAIN variant of the string-label path: a focus-indicator prefix and
    /// the label, with no caps and no fill.
    ///
    /// Its own function because the two variants together outgrew the body-length
    /// limit once each gained its opacity claim — and they were already two
    /// independent halves of one `if`, sharing only the palette and the cascade
    /// colour this passes in.
    @MainActor
    private func renderPlainStringLabel(
        context: RenderContext, _ resolved: StringLabelState
    ) -> FrameBuffer {
        let (palette, surface) = (resolved.palette, resolved.surface)
        let (cascadeForeground, baseForeground) = (resolved.cascadeForeground, resolved.baseForeground)
        let (isDisabled, isFocused, isHovered) = (
            resolved.isDisabled, resolved.isFocused, resolved.isHovered)
        let (isBold, padding) = (resolved.isBold, resolved.padding)
        // The plain variant has no caps; chrome is the focus-indicator
        // prefix (which always reserves 2 cells — `BorderRenderer` pads
        // with spaces when unfocused so things stay aligned) plus the
        // horizontal padding either side of the label.
        let chromeWidth = Self.chromeWidth(for: appearance)
        let labelText = Self.fitLabel(
            configuration.title, into: context.availableWidth, chrome: chromeWidth)
        let paddedLabel = padding + labelText + padding

        let restingColor: Color =
            isDisabled
            ? palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
            : (cascadeForeground?.resolve(with: palette)
                ?? baseForeground?.resolve(with: palette) ?? palette.accent)
        // A plain button has no face to light up — no caps, no fill, it
        // draws straight onto the page — so the pointer lifts the colour it
        // already has (``Palette/hoveredForeground(_:)``), which is also
        // what gives `Link` its hover: a link IS a plain button. The lift
        // keeps whatever hue is in force, so a cascade colour or a
        // destructive role still reads as itself.
        let foregroundColor =
            isHovered ? palette.hoveredForeground(restingColor) : restingColor

        var textStyle = TextStyle()
        textStyle.foregroundColor = foregroundColor
        textStyle.isBold = context.environment.legibilityWeight.applied(
            bold: isBold && !isDisabled, faint: false
        ).bold

        // The focus indicator is handed to the run loop as a finished cycle
        // rather than re-derived every tick: the two prefix cells are the
        // ONLY thing that changes while a focused button sits still, and
        // re-rendering the screen 20 times a second to move them is what
        // made an idle page cost a third of a core. See ``AnimatedCellRun``.
        let indicating = isFocused && !isDisabled
        let cycle = context.environment.selectionEmphasis.cycle(indicating)

        // The label breathes, and nothing sits in front of it. Same clock
        // and same frames as the bullet — only the cells it lands on
        // differ, which is the whole of the difference between the two
        // affordances.
        if appearance.indicatesFocusInLabel {
            return BreathingLabel.draw(
                paddedLabel, style: textStyle,
                ends: BorderRenderer.breathEnds(from: foregroundColor, on: surface),
                cycle: cycle, indicating: indicating, isMeasuring: context.isMeasuring)
        }

        // One ramp for the cycle, not one per frame: `focusIndicatorPrefix`
        // used to resolve its own colour from a `SelectionEmphasis`, so
        // drawing sixteen frames rebuilt the identical ramp sixteen times.
        let ends = BorderRenderer.focusIndicatorEnds(palette: palette, on: surface)
        let prefixes = cycle.colors(dim: ends.dim, bright: ends.bright).map {
            BorderRenderer.focusIndicatorPrefix(isFocused: indicating, color: $0)
        }
        // Opaque bytes plus a region, the pairing §26.1 states: an SGR
        // emitter has no backdrop, so a translucent cascade colour —
        // `.buttonTextStyle { $0.foreground = .red.opacity(0.5) }`, or a
        // faded `.tint` reaching `palette.accent` through `restingColor` —
        // goes into the claim below and never into the escape.
        let styledLabel = ANSIRenderer.render(paddedLabel, with: textStyle.opaqueColours)
        var buffer = FrameBuffer(
            lines: [prefixes[cycle.step % prefixes.count] + styledLabel])
        // The label's own cells begin past the two the focus prefix always
        // reserves — it pads with spaces when unfocused, which is what keeps
        // a row of buttons aligned. Nothing animates over the label here;
        // the prefix is the only thing that moves.
        if let claim = OpacityRegion.claim(
            offsetX: BorderRenderer.focusIndicatorWidth,
            width: paddedLabel.strippedLength, height: 1, ink: foregroundColor)
        {
            buffer.opacityRegions.append(claim)
        }
        // Between the two ends, not only the frames: where the accent or the surface has
        // no RGB they are one colour, and sixteen prefixes of it are a still picture.
        if cycle.isAnimating(dim: ends.dim, bright: ends.bright), !context.isMeasuring {
            buffer.animatedCells = [
                AnimatedCellRun(
                    offsetX: 0, offsetY: 0,
                    width: BorderRenderer.focusIndicatorWidth, frames: prefixes,
                    frameTicks: cycle.frameTicks, clock: cycle.clock)
            ]
        }
        // §18.4 lists the focus ● as an open question, and it is now ANSWERED
        // rather than claimed: `focusIndicatorEnds` goes through
        // `Color.breathEnds`, so both ends of the bullet's breath are opaque
        // (§29) — a still ● under `.selectionIndicatorStyle(.none)` included.
        // There is no alpha left at these two cells to put in a region, and a
        // claim over them would be worse than useless while the button is
        // unfocused: the prefix is then two bare spaces, and an ink claim on a
        // cell with no ink of its own lets what is behind it through.
        return buffer
    }

    /// What a `@ViewBuilder` label is drawn in: the palette and the surface
    /// under the button, and the two colours the style resolves for it.
    private struct ViewLabelInk {
        let palette: any Palette
        /// What the ink lands on, which is not the page wherever a container
        /// painted one.
        let surface: Color
        /// The label's colour.
        let label: Color
        /// The standard variant's face. The plain variant draws none.
        let face: Color
    }

    /// The colours a `@ViewBuilder` label is drawn in under `context`, by the
    /// string path's rules.
    private func viewLabelInk(context: RenderContext) -> ViewLabelInk {
        let palette = context.environment.palette
        // …as in the string path: what the ink lands on, not the page.
        let surface = context.environment.enclosingSurface
        let isDisabled = !configuration.isEnabled
        // Both, for the reason given in the string path above.
        let isHovered = configuration.isHovered

        let cascaded = context.environment.styleCascade.resolve(
            for: [.all, .text, .control(.button), .controlVariant(.button, appearance.variant)])
        let baseForeground: Color? =
            configuration.role == .destructive ? Color.palette.error : appearance.foregroundColor
        let cascadeForeground: Color? =
            configuration.role == .destructive ? nil : cascaded.foreground

        // Computed up front so the standard path can floor its default label
        // colour against the face it sits on; the plain path ignores it.
        let buttonBg = isHovered ? palette.hoveredControlFace : palette.restingControlFace

        // Same rules as the string path: cascade wins untouched; framework
        // colours are floored against the face (see makeStandardBody).
        let labelFg: Color
        if isDisabled {
            // See makeStandardBody. Floored only for the STANDARD variant: a
            // plain button has no face, so its label sits on the page
            // background and flooring it against `buttonBg` — a fill that is
            // never drawn — would brighten it against nothing.
            let faded = palette.foregroundTertiary
                .opacity(ViewConstants.disabledForeground, over: palette.background)
            labelFg = appearance.isPlain
                ? faded
                : faded.ensuringRenderedContrast(
                    atLeast: ViewConstants.disabledLabelContrastFloor, against: buttonBg)
        } else if appearance.isPlain {
            // Ahead of the cascade branch, not after it: a plain button's only
            // affordance IS the colour of its label — no caps, no fill, it
            // draws straight onto the page — so the pointer has to be able to
            // lift whatever colour is in force, the app's included. The lift
            // keeps the hue, so the label still reads as itself.
            let resting =
                cascadeForeground?.resolve(with: palette)
                ?? baseForeground?.resolve(with: palette) ?? palette.foregroundSecondary
            labelFg = isHovered ? palette.hoveredForeground(resting) : resting
        } else if let cascadeForeground {
            // On a face that cannot be measured the hover has no fill to show, so the
            // label lifts instead, the app's colour too: it is then the only thing that
            // can answer the pointer, as on a plain button (Opacity as composition §82).
            let ink = cascadeForeground.resolve(with: palette)
            labelFg = isHovered ? palette.hoveredLabel(ink) : ink
        } else {
            let ink = (baseForeground?.resolve(with: palette) ?? palette.foregroundSecondary)
                .ensuringRenderedContrast(atLeast: ViewConstants.labelContrastFloor, against: buttonBg)
            labelFg = isHovered ? palette.hoveredLabel(ink) : ink
        }
        return ViewLabelInk(palette: palette, surface: surface, label: labelFg, face: buttonBg)
    }

    /// Renders a `@ViewBuilder` button label (``ButtonStyleConfiguration/labelView``)
    /// by composing TUIkit views, so the label's own styling and structure are
    /// preserved. A plain `Text` label still picks up the style's tint because it
    /// is rendered under a `.foregroundStyle(_:)` the explicit colours override.
    /// The procedural string path above is left untouched for string labels.
    private func renderViewLabel(_ labelView: AnyView, context: RenderContext) -> FrameBuffer {
        let ink = viewLabelInk(context: context)
        let (palette, surface, labelFg) = (ink.palette, ink.surface, ink.label)
        let isDisabled = !configuration.isEnabled
        let isFocused = configuration.isFocused

        // Plain: focus-indicator prefix + the label, no caps or background.
        if appearance.isPlain {
            let indicating = isFocused && !isDisabled
            let cycle = context.environment.selectionEmphasis.cycle(indicating)

            // The label breathes, and reserves nothing in front of itself —
            // see ``_ButtonAppearance/indicatesFocusInLabel``. Rendered once
            // per frame of the cycle rather than recoloured after the fact,
            // because the label is a VIEW: its cells can carry an underline (a
            // link's does), a symbol, or bold, and a string-level recolour
            // would have to reproduce all of it. That is `frames.count`
            // renders of a short label, for the one control that holds the
            // focus, on the passes where it re-renders.
            if appearance.indicatesFocusInLabel {
                let ends = BorderRenderer.breathEnds(from: labelFg, on: surface)
                return BreathingLabel.draw(
                    ends: ends,
                    cycle: cycle, indicating: indicating, isMeasuring: context.isMeasuring
                ) { colour in
                    // A picture in the label keeps the bright end while the
                    // glyphs breathe. See ``PictureInkHold``.
                    TUIkitView.renderToBuffer(
                        labelView.breathingForegroundStyle(colour, holdingPicturesAt: ends.bright),
                        context: plainLabelContext(labelView, context: context))
                }
            }

            // One ramp for the cycle, not one per frame: `focusIndicatorPrefix`
            // used to resolve its own colour from a `SelectionEmphasis`, so
            // drawing sixteen frames rebuilt the identical ramp sixteen times.
            let ends = BorderRenderer.focusIndicatorEnds(palette: palette, on: surface)
            let prefixes = cycle.colors(dim: ends.dim, bright: ends.bright).map {
                BorderRenderer.focusIndicatorPrefix(isFocused: indicating, color: $0)
            }
            let body = TUIkitView.renderToBuffer(
                labelView.foregroundStyle(labelFg),
                context: plainLabelContext(labelView, context: context))
            var buffer = FrameBuffer(
                lines: body.lines.map { prefixes[cycle.step % prefixes.count] + $0 })
            guard !context.isMeasuring else { return buffer }
            // The label's own runs ride the prefix's width to the right; the
            // prefix repeats on every row of a multi-line label, so each row is
            // its own run.
            buffer.animatedCells = body.shiftedAnimatedCells(
                byX: BorderRenderer.focusIndicatorWidth, y: 0)
            buffer.opacityRegions = body.shiftedOpacityRegions(
                byX: BorderRenderer.focusIndicatorWidth, y: 0)
            // All FOUR payloads, not the two that were remembered: a label that
            // presents a sheet or holds a control has overlays and hit regions
            // of its own, and they ride the prefix's width exactly as the runs
            // and regions above do.
            buffer.overlays = body.shiftedOverlays(byX: BorderRenderer.focusIndicatorWidth, y: 0)
            buffer.hitTestRegions = body.shiftedHitTestRegions(
                byX: BorderRenderer.focusIndicatorWidth, y: 0)
            // The ends asked too, as for a string label: one colour is a still prefix.
            if cycle.isAnimating(dim: ends.dim, bright: ends.bright) {
                buffer.animatedCells += body.lines.indices.map { row in
                    AnimatedCellRun(
                        offsetX: 0, offsetY: row,
                        width: BorderRenderer.focusIndicatorWidth, frames: prefixes,
                        frameTicks: cycle.frameTicks, clock: cycle.clock)
                }
            }
            return buffer
        }

        // Standard: half-block caps around the background-tinted, padded label.
        let row = standardRow(labelView, ink: ink, context: context)
        return drawStandardRow(row.view, caps: row.caps, context: context)
    }

    /// The standard variant's row for a `@ViewBuilder` label in `ink`, and the
    /// cycle its caps breathe on: full accent at the bright end, and the
    /// tertiary tier at rest on a face the terminal decides — see
    /// ``ButtonCapCycle``.
    private func standardRow(
        _ labelView: AnyView, ink: ViewLabelInk, context: RenderContext
    ) -> (view: some View, caps: ButtonCapCycle) {
        let caps = ButtonCapCycle(
            isFocused: configuration.isFocused && configuration.isEnabled,
            background: ink.face, palette: ink.palette, context: context)
        let row = standardRow(
            labelView, caps: caps.colorNow, label: ink.label, face: ink.face,
            fills: context.environment.buttonSizing.fills)
        return (row, caps)
    }

    /// Draws the standard variant's row, and hands its caps' breath to the run
    /// loop when there is one.
    private func drawStandardRow<Row: View>(
        _ row: Row, caps: ButtonCapCycle, context: RenderContext
    ) -> FrameBuffer {
        var buffer = TUIkitView.renderToBuffer(row, context: context)
        guard !context.isMeasuring, caps.isAnimating else { return buffer }

        // A run has to name the row it sits on, and these caps are single-line
        // `Text`s that the HStack centres against whatever height the label
        // turns out to be — so only a one-row button can hand them over. A
        // taller label (rare, and never from the string path) keeps the old
        // cost: say the frame consulted the clock, and the loop goes on
        // rendering every tick exactly as it does today.
        if buffer.lines.count == 1 {
            buffer.animatedCells += caps.runs(width: buffer.lines[0].strippedLength)
        } else {
            context.environment.volatileReadTracker?.recordVolatileRead()
        }
        return buffer
    }

    /// Where a plain variant draws a `@ViewBuilder` label, and at what width.
    ///
    /// Under a child identity: the plain path renders the caller's label
    /// directly (the standard path's HStack pushes one implicitly), and at the
    /// core's identity a composite label's @State landed on the
    /// focusID/isHovered slots — 778699f5's collision class, missed here.
    ///
    /// Offered what the chrome leaves (``chromeWidth(for:)``), as the string
    /// path's `fitLabel` offers its text. Offered the whole width, a label as
    /// wide as that — one that fills it, or a long `Text` truncated to it —
    /// was drawn with the focus prefix in front and lost its last two cells to
    /// the parent's clip: `Text`, `Spacer`, `Text` lost the end of its second
    /// text, and a truncated one its ellipsis.
    private func plainLabelContext(_ labelView: AnyView, context: RenderContext) -> RenderContext {
        var labelContext = context.withChildIdentity(erasedType: type(of: labelView), index: 0)
        labelContext.availableWidth = max(0, context.availableWidth - Self.chromeWidth(for: appearance))
        return labelContext
    }

    /// The standard variant's row for a `@ViewBuilder` label: the label,
    /// padded on the button's face, between the two half-block caps.
    ///
    /// When buttons are flexible (``ButtonSizing/flexible``) the label is
    /// centred between spacers, which the face is painted under too, so the
    /// face widens to what the row is offered.
    private func standardRow(
        _ labelView: AnyView, caps: Color, label: Color, face: Color, fills: Bool
    ) -> some View {
        HStack(spacing: 0) {
            Text(String(TerminalSymbols.openCap)).foregroundStyle(caps)
            centred(labelView, fills: fills)
                .foregroundStyle(label)
                .padding(.horizontal, appearance.horizontalPadding)
                .background(face)
            Text(String(TerminalSymbols.closeCap)).foregroundStyle(caps)
        }
    }

    /// The label between spacers when the button fills its offer, and the
    /// label alone — no stack to lay out — when it fits it, which is nearly
    /// every button.
    @ViewBuilder
    private func centred(_ labelView: AnyView, fills: Bool) -> some View {
        if fills {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                labelView
                Spacer(minLength: 0)
            }
        } else {
            labelView
        }
    }

    /// Truncates a button label so it fits in `availableWidth` after
    /// reserving `chrome` cells for the button's chrome (caps + padding).
    ///
    /// Labels that already fit are returned unchanged. Labels longer than
    /// the available space are truncated to one less than their budget and
    /// suffixed with `…` so the user can see the truncation. If the cell
    /// is so narrow that even the chrome doesn't fit, the label is
    /// dropped entirely — the parent's clamping safety net will then clip
    /// the chrome itself.
    /// The cells this style's chrome occupies around the label.
    ///
    /// The ONE place the arithmetic lives. Both string branches of
    /// `renderToBuffer` read it, and so does ``sizeThatFits`` — the same bargain
    /// `FieldChrome` strikes for a text field's caps, and for the same reason:
    /// a measure and a render that each work the number out for themselves
    /// drift, and the drift shows as a button laid out one cell from where it
    /// draws.
    fileprivate static func chromeWidth(for appearance: _ButtonAppearance) -> Int {
        appearance.isPlain
            // No caps; the focus-indicator prefix always reserves its cells
            // (`BorderRenderer` pads with spaces when unfocused so things stay
            // aligned), unless the variant marks focus in the label instead.
            ? (appearance.indicatesFocusInLabel ? 0 : BorderRenderer.focusIndicatorWidth)
                + 2 * appearance.horizontalPadding
            // `▐ … ▌` end caps plus the padding either side.
            : 2 + 2 * appearance.horizontalPadding
    }

    /// `padded` centred in the width a flexible button fills — everything it is
    /// offered less its `caps` — or as it is when buttons fit their labels
    /// (``ButtonSizing``). Only a variant with a face calls this; a plain one
    /// has nothing to widen.
    fileprivate static func filling(_ padded: String, context: RenderContext, caps: Int) -> String {
        let spare = context.availableWidth - caps - padded.strippedLength
        guard context.environment.buttonSizing.fills, spare > 0 else { return padded }
        return String(repeating: " ", count: spare / 2) + padded
            + String(repeating: " ", count: spare - spare / 2)
    }

    fileprivate static func fitLabel(_ label: String, into availableWidth: Int, chrome: Int) -> String {
        let labelBudget = availableWidth - chrome
        guard labelBudget > 0 else { return "" }
        let labelWidth = label.strippedLength
        if labelWidth <= labelBudget { return label }
        // truncatedToWidth places the ellipsis itself; with a tiny budget it
        // returns just `…` which still keeps the chrome aligned.
        return label.truncatedToWidth(labelBudget)
    }
}

extension _ButtonStyleBody: Layoutable {
    /// The size ``renderToBuffer(context:)`` produces, without producing it.
    ///
    /// Both string branches draw exactly `chromeWidth + the fitted label`, on
    /// one line, and both numbers come from the same two helpers the render
    /// uses — so this is the render's own arithmetic, asked without the cells.
    /// `ButtonMeasureParityTests` renders the matrix and compares, because
    /// "same arithmetic" is a claim about code that has to be checked against
    /// what it actually draws.
    ///
    /// A `@ViewBuilder` label is deliberately left to render: measuring it would
    /// go through `AnyView`, where a flexible child measures to the whole
    /// available width rather than to what it draws. The SIZE is left to it,
    /// that is (``viewLabelSize(_:proposal:context:)``); the flexibility is the
    /// label's (``drawnViewFills(_:width:proposal:context:)``), as `_ToggleCore`
    /// and `_CollapsingLabel` take theirs. A label that fills
    /// — a `Spacer` between two texts, which is every navigation row — makes
    /// the button fill too, and reported rigid at the width it happened to be
    /// offered, it could not be told from a button that wide: a windowed stack
    /// of navigation links kept that width and answered a wider ask with it,
    /// and an `HStack` gave such a button its whole offer and its sibling
    /// none. Asked only of a button that drew its whole offer — one narrower
    /// than that is not filling it, keeps the answer it always had, and pays
    /// for no second measure.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        if let labelView = configuration.labelView {
            return viewLabelSize(labelView, proposal: proposal, context: context)
        }
        let chrome = Self.chromeWidth(for: appearance)
        let label = Self.fitLabel(
            configuration.title, into: context.availableWidth, chrome: chrome)
        let natural = chrome + label.strippedLength
        guard !appearance.isPlain, context.environment.buttonSizing.fills else {
            return ViewSize.fixed(natural, 1)
        }
        // A flexible button with a face fills what it is offered, and says so.
        return ViewSize(width: max(natural, context.availableWidth), height: 1, isWidthFlexible: true)
    }

    /// A `@ViewBuilder` label's button: drawn under the context
    /// `measureFixedByRendering` draws in (``fixedMeasureContext(proposal:context:)``)
    /// for its size, and, when it drew its whole offer, asked whether it fills
    /// of the view it drew the label in.
    ///
    /// The standard variant is drawn here rather than through
    /// `measureFixedByRendering` — the same row, resolved from the same ink,
    /// drawn by the same function its render uses — so that the row it drew
    /// is the row it asks. Every child of that row is then a view the drawing
    /// has just laid out, byte for byte, and the pass's memo serves the probe
    /// all of them: the probe measures the row and nothing in it. It used to
    /// ask a copy of the row in placeholder colours, whose caps and label
    /// wrappers the memo had never seen, and measured them all again.
    private func viewLabelSize(
        _ labelView: AnyView, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize {
        let measureContext = fixedMeasureContext(proposal: proposal, context: context)
        let width = measureContext.availableWidth
        if appearance.isPlain {
            let size = measureFixedByRendering(self, proposal: proposal, context: context)
            guard size.width >= width else { return size }
            let labelContext = plainLabelContext(labelView, context: measureContext)
            return ViewSize(
                width: size.width, height: size.height,
                isWidthFlexible: drawnViewFills(
                    labelView, width: labelContext.availableWidth, proposal: proposal,
                    context: labelContext))
        }
        let row = standardRow(labelView, ink: viewLabelInk(context: measureContext), context: measureContext)
        // Clamped as `renderToBuffer` clamps a `Renderable`'s buffer.
        let drawn = drawStandardRow(row.view, caps: row.caps, context: measureContext)
            .clamped(toWidth: width, height: measureContext.availableHeight)
        guard drawn.width >= width else { return ViewSize.fixed(drawn.width, drawn.height) }
        return ViewSize(
            width: drawn.width, height: drawn.height,
            isWidthFlexible: drawnViewFills(row.view, width: width, proposal: proposal, context: measureContext))
    }

    /// Whether `drawn` — the view the style drew a `@ViewBuilder` label in,
    /// under `context`, at `width` — grows with its offer.
    ///
    /// Asked of the view the label is drawn in, at the identity it is drawn
    /// at, so a label whose filling depends on its own `@State` is asked with
    /// the state it is drawn with: the standard variant draws its label inside
    /// an `HStack` (``standardRow(_:ink:context:)``), which gives it a child
    /// identity of its own, and a label probed at any other identity bound its
    /// `@State` afresh and was reported rigid while it was drawn filling. At
    /// the width it was drawn at, stated: a nil width under the ideal-width
    /// mark would ask a different question.
    ///
    /// A probe, and measured as one (`measureChildRememberingOnlyItself`): the
    /// pass's measure memo keeps its answer and nothing it finds on the way,
    /// and serves it what the drawing just measured.
    private func drawnViewFills(
        _ drawn: some View, width: Int, proposal: ProposedSize, context: RenderContext
    ) -> Bool {
        measureChildRememberingOnlyItself(
            drawn, proposal: ProposedSize(width: width, height: proposal.height), context: context
        ).isWidthFlexible
    }
}
