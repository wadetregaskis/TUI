//  🖥️ TUI — A Terminal UI framework for Swift
//  TabViewCustomLabels.swift
//
//  A tab's label of the app's own (`Tab(content:label:)`), drawn inside its
//  chip: measured once the tab view has a context, rendered in the chip's ink
//  on the chip's fill, and as tall as it draws — a row of chips as tall as its
//  tallest label. A strip of text labels never comes here.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension _TabViewCore {

    /// This core with each label of the app's own measured, or `nil` when no
    /// tab has one still to measure — nearly always.
    ///
    /// A label is rendered as a measure, which registers nothing, under an
    /// identity of its tab's, so one with `@State` keeps it; its size is what
    /// every width and height of the strip is then derived from.
    func measuringCustomLabels(_ context: RenderContext) -> Self? {
        guard tabs.contains(where: { $0.customLabel != nil && $0.labelCells == nil }) else { return nil }
        var labelContext = context
        labelContext.isMeasuring = true
        let measured = tabs.map { tab -> _RawTab in
            guard let label = tab.customLabel, tab.labelCells == nil else { return tab }
            var tab = tab
            let drawn = TUIView.renderToBuffer(label, context: labelContext.withBranchIdentity(Self.labelBranch(tab)))
            tab.labelCells = CellSize(width: drawn.width, height: max(1, drawn.height))
            return tab
        }
        return Self(selection: selection, tabs: measured)
    }

    /// The branch a tab's own label renders under, measured and drawn alike.
    private static func labelBranch(_ tab: _RawTab) -> String { "tab-label-\(tab.value)" }

    /// How many lines a row of the strip's labels takes: one for text labels,
    /// and as many as the tallest label of the app's own on it.
    func labelRowHeight(_ row: [Int]) -> Int {
        row.reduce(1) { max($0, tabs[$1].labelCells?.height ?? 1) }
    }

    /// The lines the strip takes above the content: each row's labels, and in
    /// the bordered style each row's tops plus the box's content border and
    /// bottom.
    func stripChrome(_ rows: [[Int]], bordered: Bool) -> Int {
        let labels = rows.reduce(0) { $0 + labelRowHeight($1) }
        return bordered ? labels + rows.count + 2 : labels
    }

    /// Line `place.line` of a tab's label between its chip's caps or its
    /// folder walls, in a row `place.height` lines tall: for a text label,
    /// ``tabLabelBody(_:background:foreground:active:palette:legibility:)``'s
    /// one line on the row's middle line and the chip's fill above and below
    /// it; for a label of the app's own, that line of it.
    ///
    /// `label` is the label as this chip draws it (``DrawnTabLabel``), or `nil`
    /// for a text label. One function for both strips and for every frame of
    /// the active chip's breath, as `tabLabelBody` is.
    func tabLabelLine(
        _ index: Int, line place: (line: Int, height: Int), label: DrawnTabLabel?, background: Color,
        foreground: Color, active: Bool, palette: any Palette, legibility: LegibilityWeight?
    ) -> ClaimingRow {
        let (line, height) = place
        guard let label else {
            guard line == height / 2 else { return Self.fill(tabWidth(index, style: .bordered), background: background) }
            return tabLabelBody(
                index, background: background, foreground: foreground, active: active, palette: palette,
                legibility: legibility)
        }
        let badge = tabs[index].badgeSuffix
        var row = ClaimingRow()
        row.append(" ", cells: 1, ink: foreground, field: background)
        row.append(contentsOf: label.row(line, ink: foreground))
        // The badge beside the label's middle line, as a text label's is beside
        // its title, in the palette's tertiary ink.
        if !badge.isEmpty {
            if line == height / 2 {
                row.append(
                    badge, cells: badge.strippedLength, ink: palette.foregroundTertiary, field: background,
                    bold: legibility.drawsPlainBold)
            } else {
                row.append(.spaces(badge.strippedLength), cells: badge.strippedLength, ink: nil, field: background)
            }
        }
        row.append(" ", cells: 1, ink: foreground, field: background)
        return row
    }

    /// Whether line `line` of tab `index`'s label, in a row `height` lines
    /// tall, draws anything in the label's ink — what the active chip's breath
    /// recolours. A text label's lines above and below its title are fill.
    func labelLineIsInked(_ index: Int, line: Int, height: Int) -> Bool {
        tabs[index].customLabel != nil || line == height / 2
    }

    /// `cells` of a chip's fill and nothing drawn: a line of a chip whose label
    /// is shorter than its row.
    private static func fill(_ cells: Int, background: Color) -> ClaimingRow {
        var row = ClaimingRow()
        row.append(.spaces(cells), cells: cells, ink: nil, field: background)
        return row
    }

    /// Tab `index`'s label of the app's own as its chip draws it, `height`
    /// lines tall, in `ink` on `background` — or `nil` for a text label.
    ///
    /// Rendered once per chip per pass: the active chip's breath recolours
    /// these lines (``DrawnTabLabel/row(_:ink:)``) rather than rendering the
    /// label again for each step of its cycle.
    @MainActor
    func drawnLabel(
        _ index: Int, height: Int, ink: Color, background: Color, active: Bool, context: RenderContext
    ) -> DrawnTabLabel? {
        guard let label = tabs[index].customLabel, let cells = tabs[index].labelCells else { return nil }
        var labelContext = context
        // Drawn, not interacted with: the chip is the control, and takes the
        // clicks and the keys.
        labelContext.isMeasuring = true
        let bold = context.environment.legibilityWeight.applied(bold: active, faint: false).bold
        let drawn = TUIView.renderToBuffer(
            label.foregroundStyle(ink).bold(bold)
                .frame(width: cells.width, height: height)
                .background(background),
            context: labelContext.withBranchIdentity(Self.labelBranch(tabs[index])))
        return DrawnTabLabel(
            buffer: drawn.clamped(toWidth: cells.width, height: height), width: cells.width, ink: ink,
            background: background)
    }
}

/// A tab's label of the app's own, rendered for its chip: its lines, and the
/// claims each owes, in the ink it was drawn in.
///
/// The label's own colours are its own. What it states no colour for is drawn
/// in the chip's ink, so that is what breathes on the active chip: a frame of
/// the breath is these lines with that ink rewritten (``SGRColorRewrite``),
/// which leaves everything else — the label's own colours, its fill, its
/// attributes — as drawn. A colour of the label's own that is exactly the
/// chip's resting ink breathes with it.
struct DrawnTabLabel {
    /// The rendered label, `width` across and its row's height down.
    let buffer: FrameBuffer
    /// The label's width in cells.
    let width: Int
    /// The ink the label was drawn in.
    let ink: Color
    /// The chip's fill it was drawn on: what the terminal's own field (SGR 49)
    /// means in it.
    let background: Color

    /// Line `line` of the label, its ink rewritten to `now`, with the claims
    /// that line owes in its own coordinates.
    func row(_ line: Int, ink now: Color) -> ClaimingRow {
        var row = ClaimingRow()
        let drawn = line < buffer.lines.count ? buffer.lines[line] : ""
        let text =
            now == ink
            ? drawn
            : SGRColorRewrite.rewriting(drawn, defaultForeground: ink, defaultBackground: background) {
                $0 == ink ? now : $0
            }
        row.appendFinished(text, cells: width)
        row.claims = buffer.opacityRegions.compactMap {
            $0.clipped(toColumns: 0..<width, rows: line..<(line + 1))?.shifted(byX: 0, y: -line)
        }
        return row
    }
}
