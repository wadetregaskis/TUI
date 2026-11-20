//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+BreathingHighlight.swift
//
//  A highlight painted BEHIND a finished buffer — a menu's focused row, a
//  focused `.focusable()` view — still or breathing on the shared focus clock,
//  with the whole breath handed to the run loop as finished lines rather than
//  read from the clock (see ``AnimatedCellRun``).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

extension FrameBuffer {
    /// This buffer — a label already drawn — on `highlight`: every cell's field where
    /// the label leaves it, the label's fades spent against it, and where it breathes,
    /// one run per line carrying the line at every point of the breath.
    ///
    /// Painted over the FINISHED lines, so the cycle is sixteen recolourings of a
    /// label rendered once rather than sixteen renders of it. Where the highlight
    /// breathes, its runs repaint each WHOLE line every tick, so a run the label left
    /// — a spinner beside its text — would be a second animation claiming cells the
    /// highlight's already claim, the wider one winning. The label's runs are dropped
    /// for as long as it breathes, what they said about alpha stays behind, and the
    /// render they would have caused at their next step is asked for on their behalf
    /// under `wakeToken`, as a `List`'s breathing cursor row does.
    ///
    /// A cell that states a field of its own keeps it: the highlight is behind the
    /// label, not over it.
    ///
    /// - Parameters:
    ///   - highlight: What to paint: a still fill, a breath, a reversal or a breath
    ///     with reverse video in it (`Palette.highlightedRowFill(appearsActive:reversing:)`,
    ///     `Palette.focusWashEmphasis(appearsActive:)`).
    ///   - width: How wide to square the lines off to before painting, so the
    ///     highlight is a rectangle rather than as ragged as the label's lines; `nil`
    ///     for the widest line.
    ///   - wakeToken: The token the label's dropped runs are woken under — one per
    ///     site, since a wake is kept per token.
    ///   - context: Where the label is drawn.
    /// - Returns: The label on the highlight.
    @MainActor
    package func onHighlight(
        _ highlight: HighlightFill, width: Int? = nil, wakeToken: String, context: RenderContext
    ) -> FrameBuffer {
        var buffer = self
        let palette = context.environment.palette

        // Squared off first: the bar spans the row, and a short line would
        // otherwise be painted only as far as it happens to reach, leaving the
        // highlight ragged on a multi-line label.
        let width = width ?? buffer.lines.map(\.strippedLength).max() ?? 0
        let plain = buffer.lines.map { $0.padToVisibleWidth(width) }

        // Each step is self-contained — its own background in front and a reset
        // behind — because a frame the loop splices in cannot lean on an escape
        // that happens to sit earlier in the line.
        func painted(_ line: String, _ color: Color) -> String {
            ANSIRenderer.applyPersistentBackground(line, color: color) + ANSIRenderer.reset
        }

        if let ends = RowBackground.reversingEnds(of: highlight) {
            let cycle = context.environment.selectionEmphasis.cycle(true)
            if cycle.isAnimating {
                return Self.reversingBar(
                    under: buffer, lines: plain, ends: ends, cycle: cycle, wakeToken: wakeToken, context: context)
            }
        }
        switch highlight.stillFill {
        case .reversed(let ink, let field):
            // Steady: a reversal has no phase to advance, so the row is drawn once and
            // leaves no run — and with no run there is no clock for the loop to wake
            // for. No cycle is built either, which is work avoided rather than a rule:
            // building one is sixteen frames and a pulse ramp for a picture that cannot
            // change, and it is NOT itself a clock read (`IndicatorCycleTiming.step(on:)`
            // does not mark the frame, unlike `CursorTimer.pulsePhase(for:)`).
            // The pair is restated after every reset inside the line, because a row is a
            // reset per styled run followed by plain padding, and a bare 7 exchanges the
            // colours IN FORCE, which after a reset are the terminal's own.
            func reversed(_ line: String) -> String {
                ANSIRenderer.applyPersistentReverse(
                    line, ink: ink.opaqueSpelling, field: field.opaqueSpelling)
            }
            buffer.lines = plain.map(reversed)
            // The label's own runs sit on the bar wherever their frames leave a
            // cell bare, so their grounds take the same paint as the lines do
            // (`AnimatedCellRun.ground`) — here, and in the two cases below.
            buffer.paintRunGrounds { _, ground in reversed(ground) }
            // And the bar is behind every fade inside the label: spent against it,
            // over the lines just reversed, and nothing restates the reversal after.
            // Carried up, a label faded below one half met the reversal's field as
            // its own and lost it to the page — a hole in the bar
            // (`Opacity as composition.md` §86.1).
            buffer = buffer.resolvingOpacity(onReversal: ink.opaqueSpelling, palette: palette)
        case .fill(let color):
            buffer = Self.bar(under: buffer, lines: plain, in: color, palette: palette, buildingRuns: true)
        case .reversingPulse:
            // Never: `stillFill` holds a reversing breath as a fill or a reversal.
            break
        case .pulse(let dim, let bright):
            let cycle = context.environment.selectionEmphasis.cycle(true)
            let now = cycle.colorNow(dim: dim, bright: bright)
            // For a bar that holds still, whose label keeps its runs. A breathing one
            // drops them below and leaves only its own, which ARE the bar.
            let label = buffer
            buffer = Self.bar(under: label, lines: plain, in: now, palette: palette, buildingRuns: true)
            // A still cycle (`.selectionIndicatorStyle(.none)`, or a blink at rest)
            // was already drawn above; replaying it would emit bytes per tick to
            // change nothing. Nor do two equal ends breathe (an accent the page's
            // own colour, a fully transparent one), however many frames the cycle
            // has — the question the List's cursor row asks, and asked here the
            // same way: asked only of `isAnimating`, such a bar dropped the label's
            // runs and then drew none of its own, so the spinner moved by a full
            // render at every step. Measuring passes leave no runs at all.
            guard cycle.isAnimating(dim: dim, bright: bright), !context.isMeasuring else { break }
            // The bar's runs repaint the WHOLE row every tick, over the label as it
            // was drawn, so a run the label left — a spinner beside its text — is a
            // second animation claiming cells the bar's already claims, and the
            // wider one wins: the spinner held the glyph it was rendered with. So
            // the label's runs are dropped for as long as the bar breathes, and the
            // row takes over what they did, as a `List`'s breathing cursor row does:
            // what they said about alpha stays behind, after the label's own regions
            // (§69.4), and the render they would have caused at their next step is
            // asked for on their behalf.
            Self.dropLabelRuns(of: &buffer, wakeToken: wakeToken, context: context)
            // Each colour of the breath is a bar the label's fades are spent
            // against, once per colour, where the label has any — the colour drawn
            // above already, and every other its lines alone: these runs keep only
            // lines, and a bar spent whole faded every frame of the label's runs to
            // throw them away.
            let spends = label.hasFadeOnWhatIsBehind
            var spent: [(colour: Color, lines: [String])] = spends ? [(now, buffer.lines)] : []
            buffer.animatedCells = plain.indices.compactMap { index in
                cycle.run(dim: dim, bright: bright, offsetX: 0, offsetY: index) { colour in
                    guard spends else { return painted(plain[index], colour) }
                    if let known = spent.first(where: { $0.colour == colour }) { return known.lines[index] }
                    let lines = Self.bar(
                        under: label, lines: plain, in: colour, palette: palette, buildingRuns: false
                    ).lines
                    spent.append((colour, lines))
                    return lines[index]
                }
            }
        }
        return buffer
    }

    /// The label's runs, dropped for as long as the bar breathes over them — what they
    /// said about alpha left behind, and the render they would have caused at their
    /// next step asked for on their behalf (see the breath in
    /// ``onHighlight(_:width:wakeToken:context:)``).
    @MainActor
    private static func dropLabelRuns(of buffer: inout FrameBuffer, wakeToken: String, context: RenderContext) {
        let dropped = buffer.animatedCells.filter(\.isAnimating)
        buffer.opacityRegions += dropped.flatMap(\.alphaLeftBehind)
        context.requestWake(token: wakeToken, forNextStepOf: dropped.map { ($0.clock, $0.frameTicks) })
    }

    /// `label` on a bar that breathes between a fill and reverse video, or between
    /// reverse video and reverse video in bold: the frames a list's cursor row draws
    /// (`RowBackground.reversingEnds(of:)`). A reversed frame is the whole row in the
    /// text's colour with the label in the page's; a fill is the bar, as a colour
    /// breath draws it.
    @MainActor
    private static func reversingBar(
        under label: FrameBuffer, lines: [String], ends: (dim: RowBackground.Paint, bright: RowBackground.Paint),
        cycle: SelectionEmphasisCycle, wakeToken: String, context: RenderContext
    ) -> FrameBuffer {
        let palette = context.environment.palette
        let brightFrames = cycle.brightFrames()
        let now = brightFrames[cycle.step % max(1, brightFrames.count)] ? ends.bright : ends.dim
        func drawn(_ paint: RowBackground.Paint, buildingRuns: Bool) -> FrameBuffer {
            switch paint {
            case .fill(let colour):
                return bar(under: label, lines: lines, in: colour, palette: palette, buildingRuns: buildingRuns)
            case .reversed(let ink, _, _):
                var reversed = label
                reversed.lines = lines.map(paint.painting)
                if buildingRuns { reversed.paintRunGrounds { _, ground in paint.painting(ground) } }
                // The label's fades spent against the reversal, as the still reversal
                // spends them: its field is the reversal's ink.
                return reversed.resolvingOpacity(onReversal: ink.opaqueSpelling, palette: palette)
            }
        }
        var buffer = drawn(now, buildingRuns: true)
        guard !context.isMeasuring else { return buffer }
        dropLabelRuns(of: &buffer, wakeToken: wakeToken, context: context)
        let dim = drawn(ends.dim, buildingRuns: false).lines
        let bright = drawn(ends.bright, buildingRuns: false).lines
        buffer.animatedCells = lines.indices.compactMap { index in
            cycle.run(drawn: brightFrames.map { ($0 ? bright : dim)[index] }, offsetX: 0, offsetY: index)
        }
        return buffer
    }

    /// `label` — its `lines` squared off to the bar — on a bar of `colour`, its runs'
    /// grounds painted with it, and its fades spent against it where it is opaque;
    /// its lines alone where `buildingRuns` is false.
    ///
    /// The bar is behind every fade inside the label, as a `.background` is
    /// (`Opacity as composition.md` §96.3): carried up past it, a fade met the bar
    /// as the faded label's own field and faded it too, toward the page.
    @MainActor
    private static func bar(
        under label: FrameBuffer, lines: [String], in colour: Color, palette: any Palette, buildingRuns: Bool
    ) -> FrameBuffer {
        /// Self-contained, as every step of the bar is — see `onHighlight`.
        func painted(_ line: String) -> String {
            ANSIRenderer.applyPersistentBackground(line, color: colour) + ANSIRenderer.reset
        }
        var bar = label
        bar.lines = lines.map(painted)
        if buildingRuns { bar.paintRunGrounds { _, ground in painted(ground) } }
        guard colour.isOpaque else { return bar }
        return bar.resolvingOpacity(onOpaqueFill: { nil }, surface: colour, palette: palette, buildingRuns: buildingRuns)
    }
}
