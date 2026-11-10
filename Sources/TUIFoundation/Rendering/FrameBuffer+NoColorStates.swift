//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+NoColorStates.swift
//
//  What a control says with an attribute where it can't say it with a colour.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

/// A control's states are mostly told apart by colour: an accent that breathes for the
/// focus, a recessive grey for disabled. At ``ColorDepth/noColor`` neither is drawn, so
/// a focused toggle and a disabled button looked like any other. This is what they
/// say instead, in the attributes such a terminal still draws, and in one place, so
/// that every control says it alike: the focus in reverse video, as a list's cursor
/// row, a menu's bar and a segmented picker already do, and disabled in the faint
/// `SelectionDisabledModifier` already uses for a row that can't be selected —
/// italic too where the host doesn't show faint (``TerminalClient/drawsFaint``).
///
/// At any other depth the colours keep the job, unless the person asked for cues that
/// don't rest on colour (``EnvironmentValues/accessibilityDifferentiateWithoutColor``):
/// then these are drawn over the colours too (``RenderContext/statesWithoutColor``).
/// And where a state's colour draws as the colour the control rests in at the
/// terminal's depth, as a 16-colour terminal rounds many a palette's accent and grey
/// onto its page or its text (``RenderContext/drawsAsResting(_:_:)``): there the
/// colour says nothing, so the control says it as it would without colour.
extension FrameBuffer {
    /// This buffer drawn faint, if `isDisabled`, where a control says its state without
    /// colour (``RenderContext/statesWithoutColor``), where its grey can't be mixed
    /// (``RenderContext/disabledWithoutColor``), or where `greyDrawsAsEnabled`: its grey
    /// draws as its enabled colour at the terminal's depth
    /// (``RenderContext/drawsAsResting(_:_:)``). Italic too where faint doesn't show
    /// (``ANSIRenderer/applyPersistentDisabled(_:)``).
    @MainActor
    package func fadedWithoutColor(
        if isDisabled: Bool, greyDrawsAsEnabled: Bool = false, context: RenderContext
    ) -> FrameBuffer {
        guard isDisabled, greyDrawsAsEnabled || context.disabledWithoutColor else { return self }
        return drawnDisabled()
    }

    /// This buffer drawn disabled, if `isDisabled`, at every depth: for a control with
    /// no ink of its own to grey, as a `List` or a `Table` is, whose rows are the app's
    /// views. Its faint was kept for where states are said without colour, so at any
    /// colour depth a disabled one drew exactly as an enabled one without the focus.
    @MainActor
    package func drawnDisabled(if isDisabled: Bool) -> FrameBuffer {
        isDisabled ? drawnDisabled() : self
    }

    /// This buffer in the attributes that say "disabled", at any depth: faint, and
    /// italic where the host doesn't show faint. What a disabled control draws at
    /// no colour, and a row that can't be selected at every depth.
    @MainActor
    package func drawnDisabled() -> FrameBuffer {
        var faded = self
        faded.lines = lines.map(ANSIRenderer.applyPersistentDisabled)
        // Under the runs too, so that a replayed tick draws what the render did.
        faded.paintRunGrounds { _, ground in ANSIRenderer.applyPersistentDisabled(ground) }
        return faded
    }

    /// This whole buffer saying `state` without colour (``RenderContext/statesWithoutColor``),
    /// for a control with no part of it that means anything by being lit; and where the
    /// focus's colour or the grey draws as the resting colour at the terminal's depth
    /// (`focusDrawsAsResting`, `greyDrawsAsEnabled`).
    @MainActor
    package func statingWithoutColor(
        focused: Bool, disabled: Bool, focusDrawsAsResting: Bool = false, greyDrawsAsEnabled: Bool = false,
        context: RenderContext
    ) -> FrameBuffer {
        reversedWithoutColor(if: focused && !disabled, focusDrawsAsResting: focusDrawsAsResting, context: context)
            .fadedWithoutColor(if: disabled, greyDrawsAsEnabled: greyDrawsAsEnabled, context: context)
    }

    /// This buffer with `columns` of `rows` in reverse video, if `isFocused`, where a
    /// control says its state without colour (``RenderContext/statesWithoutColor``), or
    /// where `focusDrawsAsResting`: every colour the focus is drawn in draws as the
    /// colour the same cells rest in, at the terminal's depth
    /// (``RenderContext/breathDrawsAsResting(dim:bright:resting:)``).
    ///
    /// At no colour the 7 alone; over colours, the palette's own pair restated with it
    /// after every reset, so the reversal exchanges the palette's colours rather than
    /// the terminal's (``ANSIRenderer/applyPersistentReverse(_:ink:field:bold:padding:)``).
    ///
    /// A column range rather than the whole buffer because a control's indicator can
    /// mean something by which part of it is lit, as a checkbox's mark and a slider's
    /// track do, and reversing it would say the opposite.
    ///
    /// - Parameters:
    ///   - isFocused: Whether the control shows the focus.
    ///   - rows: The rows to reverse, or all of them.
    ///   - columns: The columns to reverse, or all of them.
    ///   - focusDrawsAsResting: Whether the focus's colours draw as the resting ones here.
    ///   - context: Where the control is drawn.
    package func reversedWithoutColor(
        if isFocused: Bool, rows: Range<Int>? = nil, columns: Range<Int>? = nil, focusDrawsAsResting: Bool = false,
        context: RenderContext
    ) -> FrameBuffer {
        guard isFocused, focusDrawsAsResting || context.statesWithoutColor else { return self }
        return reversed(rows: rows, columns: columns, context: context)
    }

    /// This buffer with `columns` of `rows` in reverse video, if `isFocused`, where the
    /// focus can be told neither by colour nor by its breath: wherever
    /// ``reversedWithoutColor(if:rows:columns:focusDrawsAsResting:context:)`` reverses, and wherever the
    /// focus holds still (``RenderContext/focusHoldsStill``).
    ///
    /// For a control whose focus is its breath alone, and whose resting look is the
    /// breath's bright end: a checked checkbox's mark, a switch that is on, a link's
    /// label, a radio group's chosen option. A still focus sits at that end, so the
    /// focused control and the resting one were the same cells, and nothing said where
    /// the keys would go. A control whose still focus is a colour of its own, as a
    /// button's caps and a slider's arrows are, says it with that colour and keeps
    /// ``reversedWithoutColor(if:rows:columns:focusDrawsAsResting:context:)``.
    ///
    /// And where `focusDrawsAsResting`: the breath, at the terminal's depth, draws
    /// only the colour the control rests in (``RenderContext/breathDrawsAsResting(dim:bright:resting:)``).
    package func reversedWithoutBreath(
        if isFocused: Bool, rows: Range<Int>? = nil, columns: Range<Int>? = nil, focusDrawsAsResting: Bool = false,
        context: RenderContext
    ) -> FrameBuffer {
        guard isFocused, focusDrawsAsResting || context.statesWithoutColor || context.focusHoldsStill else {
            return self
        }
        return reversed(rows: rows, columns: columns, context: context)
    }

    /// `columns` of `rows` in reverse video over the palette's pair: the reversal both
    /// of those draw.
    private func reversed(rows: Range<Int>?, columns: Range<Int>?, context: RenderContext) -> FrameBuffer {
        // At no colour the two colours spell nothing, and only the 7 is left.
        let palette = context.environment.palette
        let colored = ColorDepth.current != .noColor
        let ink: Color = colored ? palette.foreground : .default
        let field: Color = colored ? palette.background : .default
        func reversed(_ text: String) -> String {
            ANSIRenderer.applyPersistentReverse(text, ink: ink, field: field)
        }
        let rows = rows ?? 0..<lines.count
        var result = self
        for row in rows where lines.indices.contains(row) {
            let line = lines[row]
            let width = line.strippedLength
            let span = (columns ?? 0..<width).clamped(to: 0..<width)
            guard !span.isEmpty else { continue }
            // The reversed span ends in a reset, so the row's styling in force
            // past it is restated: a bold label after a reversed mark stays bold.
            result.lines[row] =
                line.ansiAwarePrefix(visibleCount: span.lowerBound)
                + reversed(line.ansiAwareSlice(visibleStart: span.lowerBound, visibleCount: span.count))
                + line.ansiStateBefore(visibleColumn: span.upperBound)
                + line.ansiAwareSuffix(droppingVisible: span.upperBound)
        }
        // A run wholly inside what was reversed replays reversed, as a faded buffer's
        // replays faded.
        result.paintRunGrounds { run, ground in
            let inside =
                rows.contains(run.offsetY)
                && (columns.map { $0.lowerBound <= run.offsetX && run.offsetX + run.width <= $0.upperBound } ?? true)
            return inside ? reversed(ground) : ground
        }
        return result
    }
}

extension _ButtonStyleBody {
    /// `buffer` saying in attributes what the colours would have said.
    ///
    /// A plain button already draws a ● for the focus, which needs no colour. A link's
    /// label only breathes, and a face only breathes its caps, so those reverse: all
    /// of the face but half-block caps, whose reversal would light the half facing
    /// away from the label and leave a gap beside it.
    ///
    /// A link's label rests at its breath's bright end, so it reverses too where the
    /// focus holds still (``RenderContext/focusHoldsStill``), at any depth.
    ///
    /// And at any depth where the colours say nothing: the focus's breath draws only
    /// the colour the button rests in (``focusDrawsAsResting(context:)``), or a disabled
    /// label's grey draws as the enabled label's colour (``greyDrawsAsEnabled(context:)``).
    func statingStateWithoutColor(_ buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        let focused = configuration.isFocused && configuration.isEnabled
        let focusUnseen = focused && focusDrawsAsResting(context: context)
        let greyUnseen = !configuration.isEnabled && greyDrawsAsEnabled(context: context)
        guard
            context.statesWithoutColor || (configuration.isFocused && context.focusHoldsStill)
                || (!configuration.isEnabled && context.disabledWithoutColor) || focusUnseen || greyUnseen
        else { return buffer }
        let edges = appearance.edges
        let hasCaps = !appearance.isPlain && edges.caps != nil && !edges.capsAreFace && !edges.isOutline
        return
            buffer
            .fadedWithoutColor(if: !configuration.isEnabled, greyDrawsAsEnabled: greyUnseen, context: context)
            .reversedWithoutColor(
                if: configuration.isFocused && !appearance.isPlain,
                columns: hasCaps ? 1..<max(1, buffer.width - 1) : nil, focusDrawsAsResting: focusUnseen,
                context: context)
            // A label that only breathes, as a link's does, rests at its breath's
            // bright end, so a still focus there is reversed too.
            .reversedWithoutBreath(
                if: configuration.isFocused && appearance.isPlain && appearance.indicatesFocusInLabel,
                focusDrawsAsResting: focusUnseen, context: context)
    }
}

extension _ButtonStyleBody {
    /// Whether this focused button's focus is drawn only in the colours it rests in, at
    /// the terminal's colour depth (``RenderContext/breathDrawsAsResting(dim:bright:resting:)``):
    /// a face's caps or whole face breathe from the face to the accent, an outline's
    /// lines from their resting ink to the accent, and a plain label that breathes from
    /// its own colour dimmed. A plain button's ● says the focus without colour.
    ///
    /// Silver Aerogel's accent is its page at 16 colours, as its face is, so a focused
    /// view-label button, a prominent one and a `.button` toggle drew as at rest
    /// (THEME-16, 2026-11-10).
    func focusDrawsAsResting(context: RenderContext) -> Bool {
        let ink = viewLabelInk(context: context)
        let accent = ink.palette.accent.spendingAlpha(over: ink.face)
        if appearance.isPlain {
            guard appearance.indicatesFocusInLabel else { return false }
            let label = drawnLabel(ink, context: context)
            let ends = BorderRenderer.breathEnds(from: label, on: ink.surface)
            return context.breathDrawsAsResting(dim: ends.dim, bright: ends.bright, resting: label)
        }
        if appearance.edges.isOutline {
            let lines = Self.outlineInk(
                palette: ink.palette, surface: ink.surface, hovered: configuration.isHovered, disabled: false)
            return context.breathDrawsAsResting(dim: lines, bright: accent, resting: lines)
                && (ink.authored || context.breathDrawsAsResting(dim: ink.label, bright: accent, resting: ink.label))
        }
        if appearance.edges.caps == nil {
            let ends = BorderRenderer.breathEnds(from: ink.label, on: ink.face)
            return context.breathDrawsAsResting(dim: ends.dim, bright: ends.bright, resting: ink.label)
        }
        return context.breathDrawsAsResting(dim: ink.face, bright: accent, resting: ink.face)
    }

    /// Whether this disabled button's label is drawn in the colour the same button's
    /// label rests in enabled, at the terminal's colour depth
    /// (``RenderContext/drawsAsResting(_:_:)``): its grey says nothing there. Six
    /// palettes' grey is a resting button's label at 16 colours (THEME-16, 2026-11-10).
    func greyDrawsAsEnabled(context: RenderContext) -> Bool {
        let enabled = Self(
            configuration: ButtonStyleConfiguration(
                title: configuration.title, labelView: configuration.labelView, role: configuration.role,
                isPressed: false, isFocused: false, isHovered: false, isEnabled: true,
                keyboardShortcut: configuration.keyboardShortcut),
            appearance: appearance, isSized: isSized)
        return context.drawsAsResting(
            drawnLabel(viewLabelInk(context: context), context: context),
            enabled.drawnLabel(enabled.viewLabelInk(context: context), context: context))
    }

    /// The colour the label is drawn in: `ink`'s, but for a plain button's string
    /// label, which `renderPlainStringLabel(context:_:)` rests in the accent where a
    /// view label rests in the secondary tier, and greys unfloored.
    private func drawnLabel(_ ink: ViewLabelInk, context: RenderContext) -> Color {
        guard appearance.isPlain, configuration.labelView == nil else { return ink.label }
        let palette = ink.palette
        guard configuration.isEnabled else {
            return palette.foregroundTertiary.opacity(ViewConstants.disabledForeground, over: palette.background)
        }
        if ink.authored { return ink.label }
        let base: Color? = configuration.role == .destructive ? Color.palette.error : appearance.foregroundColor
        return base?.resolve(with: palette) ?? palette.accent
    }
}

extension RenderContext {
    /// Whether a control says its state in attributes and glyphs, not by colour alone:
    /// at ``ColorDepth/noColor``, where they are all it has, and wherever the person
    /// asked for cues that don't rest on colour
    /// (``EnvironmentValues/accessibilityDifferentiateWithoutColor``: macOS's
    /// Differentiate Without Colour where they're at this machine, or
    /// `TUI_DIFFERENTIATE_WITHOUT_COLOR`), over the colours. The one test every
    /// control's no-colour cues ask, so that they all turn on together.
    package var statesWithoutColor: Bool {
        ColorDepth.current == .noColor || environment.accessibilityDifferentiateWithoutColor
    }

    /// Whether `state`, the colour a control says a state in, draws as `resting`, the
    /// colour the same cells have without it, at the terminal's colour depth
    /// (``ColorDepth/current``): the state's colour says nothing there.
    ///
    /// The owner's ruling of 2026-11-10 (THEME-16): rounded to a 16-colour terminal's
    /// sixteen, some palettes' states land on their resting colour — Silver Aerogel's
    /// accent is its page, so a focused slider's arrows drew as resting ones, and six
    /// palettes' disabled grey is a resting button's label. Where it does, the control
    /// falls back to the cue it draws without colour, automatically, for every palette:
    /// reverse video for the focus, faint for disabled. Measured with
    /// `StateColourCollisionTests`, which sweeps every control through every shipped
    /// palette at every depth.
    package func drawsAsResting(_ state: Color, _ resting: Color) -> Bool {
        let depth = ColorDepth.current
        return state.downsampled(to: depth) == resting.downsampled(to: depth)
    }

    /// Whether a focus that breathes from `dim` to `bright` draws only `resting` at the
    /// terminal's colour depth: every shade the depth draws the breath in
    /// (`Color.pulseRamp(from:to:depth:)`) is the colour the same cells rest in; or,
    /// where the focus holds still (``focusHoldsStill``), its bright end is, which is
    /// all a still focus shows. Man Page's slider arrows breathe from its grey to its
    /// page at 16 colours, and held still sat on the grey they rest in. See
    /// ``drawsAsResting(_:_:)``.
    package func breathDrawsAsResting(dim: Color, bright: Color, resting: Color) -> Bool {
        let depth = ColorDepth.current
        let rest = resting.downsampled(to: depth)
        guard bright.downsampled(to: depth) == rest else { return false }
        if focusHoldsStill { return true }
        // The truecolor answer is the two ends themselves, which `pulseRamp` hands
        // back; at the other depths it is every shade the breath is drawn in.
        return Color.pulseRamp(from: dim, to: bright, depth: depth).allSatisfy { $0.downsampled(to: depth) == rest }
    }

    /// Whether the focus breath most controls draw — the accent, dimmed toward the page
    /// at one end (``Palette/accentPulse(over:)``) — draws only `resting` at the
    /// terminal's colour depth. A slider's and a stepper's arrows breathe it from their
    /// dimmed grey. See ``breathDrawsAsResting(dim:bright:resting:)``.
    package func accentBreathDrawsAsResting(on resting: Color) -> Bool {
        let ends = environment.palette.accentPulse()
        return breathDrawsAsResting(dim: ends.dim, bright: ends.bright, resting: resting)
    }

    /// ``accentBreathDrawsAsResting(on:)`` for a slider's or a stepper's arrows, which
    /// rest in the tertiary tier at ``ViewConstants/disabledForeground`` over the page.
    package var arrowFocusDrawsAsResting: Bool {
        let palette = environment.palette
        return accentBreathDrawsAsResting(
            on: palette.foregroundTertiary.opacity(ViewConstants.disabledForeground, over: palette.background))
    }

    /// Whether a disabled control says so in faint rather than by its grey: wherever
    /// states are said without colour (``statesWithoutColor``), and where the grey can't
    /// be mixed because the palette's foreground or page has no RGB, as the `Terminal`
    /// palette's have until the terminal reports them, and on a host that never does
    /// (GNU screen). There the grey comes out as the plain foreground
    /// (`Color.opacity(_:over:)` keeps the heavier side), so a disabled control looked
    /// enabled.
    package var disabledWithoutColor: Bool {
        if statesWithoutColor { return true }
        let palette = environment.palette
        return palette.foreground.rgbComponents == nil || palette.background.rgbComponents == nil
    }

    /// Whether a focused control's breath holds still here, at its bright end: the
    /// person turned it off (`TUI_BREATHING=0`, the View menu's Breathing Focus), the
    /// app did (`Scene.focusBreathing(false)`), or a view did for its subtree
    /// (`.selectionIndicatorStyle(.none)`). And where the breath can't move: its accent
    /// or the page it breathes over has no RGB to mix, as under the `Terminal` palette
    /// until the terminal reports its colours, so it holds at its bright end whatever
    /// the setting (`SelectionEmphasisCycle.isAnimating(dim:bright:)`).
    ///
    /// Not in a window that does not appear active: a focus there is held half-way
    /// between its breath's ends, which a resting control does not draw
    /// (``SelectionEmphasisClock/cycle(_:)``).
    package var focusHoldsStill: Bool {
        guard environment.appearsActive else { return false }
        if environment.selectionIndicatorStyle == .none { return true }
        let palette = environment.palette
        return palette.accent.rgbComponents == nil || palette.background.rgbComponents == nil
    }
}
