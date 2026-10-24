//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewStrip.swift
//
//  How a TabView draws its strip of tabs: the compact chips, the folder-tab
//  chrome, the colours both take, and a chip's spring loading. Split from
//  TabView.swift, which keeps the view itself — its focus, geometry, and
//  content panel.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension _TabViewCore {

    /// Lays out the wrapped, aligned compact chip rows. Returns the lines (each
    /// padded to `width`), the per-tab click regions in strip coordinates, and
    /// the active chip's animation run if it is breathing.
    ///
    /// The chips' caps are a button's in the family in force (``ControlEnds``),
    /// read at `.regular`: a chip is two cells wider than its label under every
    /// family and size, as ``tabWidth(_:style:)`` says.
    func compactStripLines(
        rows: [[Int]], selectedIndex: Int, hoveredIndex: Int?,
        chip: ActiveChipCycle, palette: any Palette,
        width: Int, alignment: HorizontalAlignment, context: RenderContext
    ) -> (
        lines: [String], regions: [(x: Int, y: Int, width: Int, height: Int, index: Int)],
        animatedCells: [AnimatedCellRun], claims: [OpacityRegion]
    ) {
        let (inactiveFg, inactiveBg) = stripLabelColors(palette: palette)
        let legibility = context.environment.legibilityWeight
        let ends = ControlEnds(in: context.environment, size: .regular)
        var lines: [String] = []
        var regions: [(x: Int, y: Int, width: Int, height: Int, index: Int)] = []
        var animatedCells: [AnimatedCellRun] = []
        var claims: [OpacityRegion] = []

        // The active chip's lines, where its caps are lines: on its own fill,
        // whose label is the one thing that breathes.
        let lineInk = ControlEnds.lineInk(palette: palette, surface: chip.surface, hovered: false, disabled: false)

        // A coloured chip: the half-block caps (▐ … ▌) extend the chip's fill
        // half a cell each side with a clean edge. One function draws it, so
        // the animation's frames are the same cells the render draws — a second
        // spelling of this is how a replayed run drifts from what is on screen.
        //
        // Through `ClaimingRow`, which is also what gets the claim's COLUMNS right
        // without a second piece of arithmetic: the caps are ink-only (a half block
        // painted in the chip's own colour) and the body is ink on field, so a chip
        // owes three claims and not one, and the row knows where each begins because
        // it is the thing that put them there.
        //
        // In another family the caps are a button's of it (``ControlEnds``): the
        // face's own cells where a filled face is square, and lines on the active
        // chip's fill where controls are drawn in lines — `( title )`, as a text
        // field keeps its field between line caps. An inactive chip has no caps to
        // show there, as on the page its half blocks vanish into it: its two cells
        // are its fill. Under `.blank`, and at sizes with no caps, the chip keeps
        // its two cells, of its fill, so a strip is as wide in every family.
        //
        // The active chip's line caps breathe the focus with its label, as a
        // lines button's do (`capsInk`, the colour they are drawn in now).
        func drawChip(
            _ index: Int, background: Color, foreground: Color, active: Bool, capsInk: Color
        ) -> ClaimingRow {
            var row = ClaimingRow()
            cap(ends.open, active: active, background: background, ink: capsInk, into: &row)
            row.append(contentsOf: tabLabelBody(
                index, background: background, foreground: foreground, active: active, palette: palette,
                legibility: legibility))
            cap(ends.close, active: active, background: background, ink: capsInk, into: &row)
            return row
        }
        func cap(_ glyph: Character, active: Bool, background: Color, ink: Color, into row: inout ClaimingRow) {
            switch ends.kind {
            case .filled, .face:
                ends.appendCap(glyph, to: &row, face: background, lines: ink)
            case .lines where active:
                ends.appendCap(glyph, to: &row, face: background, lines: ink, field: background)
            case .lines, .none:
                row.append(" ", cells: 1, ink: nil, field: background)
            }
        }

        for (y, row) in rows.enumerated() {
            let offset = max(0, alignment.childOffset(childWidth: compactRowWidth(row), in: width))
            var line = String.spaces(offset)
            var x = offset
            for i in row {
                // The active chip takes the surface (breathing when focused);
                // inactive chips recede onto the base background.
                let active = i == selectedIndex
                // The pointer lifts the label it is over — including the active
                // tab's, unless that one is already breathing for the focus — but
                // not a disabled tab's, which a click does nothing to.
                let hovered = i == hoveredIndex && !(active && chip.isBreathing) && !tabs[i].isDisabled
                let resting = active ? chip.labelNow : restingInk(i, inactive: inactiveFg, palette: palette)
                let drawn = drawChip(
                    i, background: active ? chip.surface : inactiveBg,
                    foreground: hovered ? palette.hoveredForeground(resting) : resting,
                    active: active, capsInk: active ? chip.capsNow(resting: lineInk) : lineInk)
                line += drawn.text
                claims += drawn.claims.map { $0.shifted(byX: x, y: y) }
                let chipWidth = tabWidth(i, style: .compact)  // body + the two caps
                regions.append((x: x, y: y, width: chipWidth, height: 1, index: i))
                // Only lines caps breathe: a filled chip's caps are its fill,
                // which holds still while the label breathes.
                let run =
                    !active ? nil
                    : ends.kind == .lines
                        ? chip.run(offsetX: x, offsetY: y, capsResting: lineInk) { label, caps in
                            drawChip(i, background: chip.surface, foreground: label, active: true, capsInk: caps).text
                        }
                        : chip.run(offsetX: x, offsetY: y, draw: {
                            drawChip(i, background: chip.surface, foreground: $0, active: true, capsInk: lineInk).text
                        })
                if let run {
                    animatedCells.append(run)
                }
                x += chipWidth
            }
            if x < width { line += String.spaces(width - x) }
            lines.append(line)
        }
        return (lines, regions, animatedCells, claims)
    }

    /// The chrome a folder-tab strip is drawn from: the label colours, the
    /// border and surface tones, and the box geometry its rows align within.
    struct FolderStripStyle {
        let inactiveFg: Color
        /// The tab under the pointer, if any.
        let hoveredIndex: Int?
        /// For the hover lift (``Palette/hoveredForeground(_:)``).
        let palette: any Palette
        let inactiveBg: Color
        let border: Color
        /// The glyphs the tabs and the box are drawn in: the appearance's border.
        let glyphs: TabBoxGlyphs
        let surface: Color
        let interior: Int
        let boxWidth: Int
        let alignment: HorizontalAlignment
        /// `\.legibilityWeight`, which draws the tabs' labels a tier heavier.
        let legibility: LegibilityWeight?
    }

    /// Draws the folder-tab strip: per row, a line of tab tops and a line of
    /// labels, and under the last row the content box's top border curving
    /// around the active tab.
    ///
    /// Returns the lines, the per-tab click regions, and the active chip's
    /// animation run. The regions and the run are in box coordinates, which are
    /// also the buffer's, because the strip opens it; each line's claims are in its
    /// own, and the caller places them on the row the line lands on.
    ///
    /// Every line is a ``ClaimingRow``, for the reason the compact chips are: a wall
    /// is border ink on nothing, a label is ink on field, the mouth under the active
    /// tab is field and no ink — and the row that emits each run is the thing that
    /// knows its column (§56).
    func folderStripRows(
        rows: [[Int]], selectedIndex: Int, chip: ActiveChipCycle, style: FolderStripStyle
    ) -> (
        lines: [ClaimingRow], regions: [(x: Int, y: Int, width: Int, height: Int, index: Int)],
        animatedCells: [AnimatedCellRun]
    ) {
        // The absolute box column of a row's left wall, per the strip alignment.
        func rowOffset(_ rowWidth: Int) -> Int {
            1 + max(0, style.alignment.childOffset(childWidth: rowWidth, in: style.interior))
        }
        // One function draws a tab's label so the animation's frames are the
        // same cells the render draws. The walls either side are border chrome
        // and do not breathe, so a folder tab's run is its body only.
        func drawLabel(_ index: Int, background: Color, foreground: Color, active: Bool) -> ClaimingRow {
            tabLabelBody(
                index, background: background, foreground: foreground, active: active,
                palette: style.palette, legibility: style.legibility)
        }

        var lines: [ClaimingRow] = []
        var regions: [(x: Int, y: Int, width: Int, height: Int, index: Int)] = []
        var animatedCells: [AnimatedCellRun] = []

        for (rowIndex, row) in rows.enumerated() {
            let isBottom = rowIndex == rows.count - 1
            let off = rowOffset(folderRowWidth(row))

            // Walls (count + 1) and bodies for this row, in absolute columns.
            var wallCols: [Int] = []
            var bodySpans: [(start: Int, len: Int, index: Int)] = []
            var col = off
            for i in row {
                wallCols.append(col)
                let bw = tabWidth(i, style: .bordered)
                bodySpans.append((start: col + 1, len: bw, index: i))
                col += 1 + bw
            }
            wallCols.append(col)

            // Tab tops: the whole strip span is border-coloured, so emit it as one
            // run — `╭`/`╮` for active corners & strip ends, `┬` for shared walls,
            // in the appearance's own border (``TabBoxGlyphs``).
            let glyphs = style.glyphs
            var top = ""
            for k in wallCols.indices {
                // A wall touching the active tab takes a rounded corner so the
                // active tab reads as a raised `╭ … ╮` cell — `╮` on its right
                // wall, `╭` on its left. These deliberately cut into the shared
                // walls with its neighbours (a "backwards" corner on the
                // neighbour), which is what makes the active tab stand out.
                let activeRight = k > 0 && row[k - 1] == selectedIndex
                let activeLeft = k < bodySpans.count && row[k] == selectedIndex
                top.append(Self.topWallGlyph(
                    isStripStart: k == 0, isStripEnd: k == wallCols.count - 1,
                    activeRight: activeRight, activeLeft: activeLeft, glyphs: glyphs))
                if k < bodySpans.count { top += String(repeating: glyphs.horizontal, count: bodySpans[k].len) }
            }
            var tops = ClaimingRow()
            tops.skip(cells: off)
            tops.append(top, cells: top.count, ink: style.border, field: glyphs.field(style.border))
            tops.skip(cells: style.boxWidth - off - top.count)
            lines.append(tops)

            // Tab labels: `│ title │ title │ …`, the active chip on the surface.
            let labelsY = lines.count
            var labels = ClaimingRow()
            labels.skip(cells: off)
            for (k, i) in row.enumerated() {
                let active = i == selectedIndex
                let hovered = i == style.hoveredIndex && !(active && chip.isBreathing) && !tabs[i].isDisabled
                let resting =
                    active ? chip.labelNow : restingInk(i, inactive: style.inactiveFg, palette: style.palette)
                labels.append(String(glyphs.wall), cells: 1, ink: style.border, field: glyphs.field(style.border))
                // One column reached two ways: this row's, which places the claim,
                // and `bodySpans`', which places the run and the click region.
                // Asserted, because a run one cell off repaints a wall forever.
                assert(
                    labels.cells == bodySpans[k].start,
                    "folder label at \(labels.cells), span at \(bodySpans[k].start)")
                labels.append(contentsOf: drawLabel(
                    i, background: active ? chip.surface : style.inactiveBg,
                    foreground: hovered ? style.palette.hoveredForeground(resting) : resting,
                    active: active))
                // The chrome above and below a tab is the tab's, not the
                // page's: a folder tab is drawn as three rows and read as one
                // control, so a click on the line over the title should not
                // miss. The top border always belongs to it; the row below
                // does too on the bottom row, where it is the content box's
                // own border — higher up it is the NEXT row's top border, and
                // two tabs claiming one row would make the answer arbitrary.
                regions.append((
                    x: bodySpans[k].start, y: labelsY - 1, width: bodySpans[k].len,
                    height: isBottom ? 3 : 2, index: i))
                if active,
                    let run = chip.run(
                        offsetX: bodySpans[k].start, offsetY: labelsY,
                        draw: { drawLabel(i, background: chip.surface, foreground: $0, active: true).text })
                {
                    animatedCells.append(run)
                }
            }
            labels.append(String(glyphs.rightWall), cells: 1, ink: style.border, field: glyphs.field(style.border))
            labels.skip(cells: style.boxWidth - off - folderRowWidth(row))
            lines.append(labels)

            // Under the active (bottom) row: the content box's top border, curving
            // up to wrap the active tab and opening (surface gap) beneath it.
            if isBottom {
                lines.append(activeRowBottomBorder(
                    wallCols: wallCols, bodySpans: bodySpans, selectedIndex: selectedIndex,
                    boxWidth: style.boxWidth, border: style.border, surface: style.surface, glyphs: glyphs))
            }
        }
        return (lines, regions, animatedCells)
    }

    /// A tab's label between its chip's caps or its folder walls: ` title `, or
    /// ` title badge ` with the badge in the palette's tertiary ink, as a list
    /// row's badge is drawn. One function for both strips and for every frame
    /// of the active chip's breath, so each draws the cells the others do.
    ///
    /// A tab with no badge is the one ` title ` run it always was, so its bytes
    /// do not change with the badge's arrival.
    func tabLabelBody(
        _ index: Int, background: Color, foreground: Color, active: Bool, palette: any Palette,
        legibility: LegibilityWeight?
    ) -> ClaimingRow {
        var row = ClaimingRow()
        let badge = tabs[index].badgeSuffix
        // The title and the badge are text: a tier heavier under a bold
        // legibility weight, the active title bold either way.
        let bold = legibility.applied(bold: active, faint: false).bold
        guard !badge.isEmpty else {
            let title = " \(tabs[index].title) "
            row.append(title, cells: title.strippedLength, ink: foreground, field: background, bold: bold)
            return row
        }
        let title = " \(tabs[index].title)"
        row.append(title, cells: title.strippedLength, ink: foreground, field: background, bold: bold)
        row.append(
            badge, cells: badge.strippedLength, ink: palette.foregroundTertiary, field: background,
            bold: legibility.drawsPlainBold)
        row.append(" ", cells: 1, ink: foreground, field: background)
        return row
    }

    /// The ink an inactive tab's label rests in: the strip's, or the
    /// palette's quaternary for a disabled tab.
    func restingInk(_ index: Int, inactive: Color, palette: any Palette) -> Color {
        tabs[index].isDisabled ? palette.foregroundQuaternary : inactive
    }

    /// The inactive chips' foreground and background. Shared by both strip
    /// styles; the ACTIVE chip's label comes from ``ActiveChipCycle``, which
    /// owns both ends of its breath.
    func stripLabelColors(palette: any Palette) -> (inactiveFg: Color, inactiveBg: Color) {
        (palette.foregroundSecondary, palette.background.resolve(with: palette))
    }

    /// The glyph for a tab-strip top wall: the border's corners at the strip
    /// ends and around the active tab (`╭`/`╮` under the rounded border), its
    /// `┬` for an ordinary shared wall. The precedence (strip-end before
    /// active-tab) makes a wall that is both read as the strip end.
    static func topWallGlyph(
        isStripStart: Bool, isStripEnd: Bool, activeRight: Bool, activeLeft: Bool, glyphs: TabBoxGlyphs
    ) -> Character {
        if isStripStart {
            glyphs.topLeft
        } else if isStripEnd {
            glyphs.topRight
        } else if activeRight {
            glyphs.meeting(glyphs.wall, glyphs.topRight)
        } else if activeLeft {
            glyphs.meeting(glyphs.wall, glyphs.topLeft)
        } else {
            glyphs.teeDown
        }
    }

    /// The content box's top border drawn beneath the active (bottom) tab row: it
    /// curves up to wrap the active tab (`╯` … `╰`, with a surface-coloured gap
    /// across the tab body) and meets the inactive walls with `┴` — in the
    /// border's own glyphs (``TabBoxGlyphs``).
    func activeRowBottomBorder(
        wallCols: [Int], bodySpans: [(start: Int, len: Int, index: Int)],
        selectedIndex: Int, boxWidth: Int, border: Color, surface: Color, glyphs: TabBoxGlyphs
    ) -> ClaimingRow {
        let field = glyphs.field(border)
        var line = ClaimingRow()
        let activeWall = wallCols.firstIndex { wc in
            bodySpans.contains { $0.index == selectedIndex && $0.start == wc + 1 }
        } ?? 0
        let aLeft = wallCols[activeWall]
        guard let aBody = bodySpans.first(where: { $0.index == selectedIndex }) else {
            let rule =
                String(glyphs.bottomLeft) + String(repeating: glyphs.horizontal, count: max(0, boxWidth - 2))
                + String(glyphs.bottomRight)
            line.append(rule, cells: rule.count, ink: border, field: field)
            return line
        }
        let aRight = aBody.start + aBody.len
        let inactiveWalls = Set(wallCols).subtracting([aLeft, aRight])
        // The wall coming down into this line at column `c`: the strip's last is
        // its right wall, as the label row drew it.
        let lastWall = wallCols.last
        func wall(_ c: Int) -> Character { c == lastWall ? glyphs.rightWall : glyphs.wall }
        func borderGlyph(_ c: Int) -> Character {
            if c == 0 { return glyphs.topLeft }
            if c == boxWidth - 1 { return glyphs.topRight }
            if c == aLeft { return glyphs.meeting(wall(c), glyphs.bottomRight) }
            if c == aRight { return glyphs.meeting(wall(c), glyphs.bottomLeft) }
            return inactiveWalls.contains(c) ? glyphs.meeting(wall(c), glyphs.teeUp) : glyphs.horizontal
        }
        var left = ""
        for c in 0..<aBody.start { left.append(borderGlyph(c)) }
        var right = ""
        for c in aRight..<boxWidth { right.append(borderGlyph(c)) }
        line.append(left, cells: aBody.start, ink: border, field: field)
        // The mouth: the active tab's body opening into the panel, in the panel's
        // surface with nothing drawn in it — so it owes a field and no ink. Nothing at
        // all for a body of no width.
        if aBody.len > 0 {
            line.append(String.spaces(aBody.len), cells: aBody.len, ink: nil, field: surface)
        }
        line.append(right, cells: boxWidth - aRight, ink: border, field: field)
        return line
    }

    /// Lets a drag held still over tab `index`'s chip select that tab, as a
    /// click on it does — without moving the focus, which a drag leaves where
    /// it is. Nothing is registered for a tab that does not spring-load.
    @MainActor
    func registerSpringLoading(forTab index: Int, handlerID: HitTestRegion.HandlerID, context: RenderContext) {
        guard tabs[index].springLoads(inheriting: context.environment.springLoadingBehavior),
            let session = context.environment.dragAndDropSession
        else { return }
        let value = tabs[index].value
        let selection = self.selection
        session.registerSpringLoadTarget(
            DragAndDropSession.SpringLoadTarget(
                handlerID: handlerID, identity: Self.springLoadingIdentity(ofTab: index, in: context),
                activate: { if let v = value.base as? SelectionValue { selection.wrappedValue = v } }),
            in: context)
    }

    /// The tab whose chip is drawn lifted: the one under the pointer, or else
    /// the one a paused drag rests on, while the spring-loading pause runs and
    /// as it fires (owner ruling B82).
    @MainActor
    func liftedTab(context: RenderContext) -> Int? {
        if let hovered = hoveredTabBox(context: context).value { return hovered }
        guard let session = context.environment.dragAndDropSession, session.active != nil else { return nil }
        return tabs.indices.first { session.springLoadPhase(of: Self.springLoadingIdentity(ofTab: $0, in: context)) != nil }
    }

    /// The identity tab `index`'s chip spring-loads as: one of its own, below
    /// the tab view's, so the pause names the chip it rests on and a drag out
    /// of the tab view's content still reaches another tab.
    private static func springLoadingIdentity(ofTab index: Int, in context: RenderContext) -> ViewIdentity {
        context.identity.child(erasedType: SpringLoadedTabChip.self, index: index)
    }
}

/// The identity step a tab chip spring-loads at.
private enum SpringLoadedTabChip {}
