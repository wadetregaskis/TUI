//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+RunsUnderALayer.swift
//
//  A layer composited over a run of its base — a `ZStack`'s later child, an
//  `.overlay`, a `Layout`'s later subview, a `List` row's content over its
//  `.listRowBackground` view — punches the run under its footprint
//  (`FrameBuffer.animatedCellsPunched`): the layer's cells replace the base's, and a
//  run replaying there would paint over them. But a layer's cell that names no field
//  shows the base's, which the composite fills in from the frame the render drew. A
//  run whose frames disagree about that field left the cell on the drawn frame's
//  field at every tick: a label over a breathing fill froze on the colour it was
//  drawn over. The layer's cell and the run's frame are two things one cell shows,
//  and a run carries one; so the compositor asks for a render at each of the run's
//  steps, which draws the cell as it is then, the way a breathing `List` row does
//  for the runs it drops (`Opacity as composition.md` §109). A layer's cell that
//  fades over the run is resolved over the drawn frame, whose field, ink and glyph
//  it mixes with or loses to, so there any difference between the frames asks.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension FrameBuffer {

    /// The runs of this buffer — a base about to have `layer` composited onto it at
    /// `position` — that the layer's cells show differently from step to step, which
    /// the punched run cannot replay:
    ///
    /// - where a cell the layer covers fills with the base's field
    ///   (`String.columnsTakingBaseField(width:)`), in the line it draws or in a frame
    ///   of one of its own runs, and the run's frames disagree about that field;
    /// - where a cell of the layer fades (``columnsFading(onRow:)``), and the run's
    ///   frames disagree about anything there. Such a cell is resolved over the drawn
    ///   frame: it loses its glyph to the frame's, or mixes its ink and field toward
    ///   the frame's.
    ///
    /// A run whose frames change only their glyphs under an unfaded cell, or state no
    /// field there, shows that cell alike at every step, and is not one: a spinner
    /// under a label asks for nothing. Nearly every base has no run under a layer, and
    /// is answered from the runs' rows and columns alone.
    ///
    /// - Parameters:
    ///   - layer: What is about to land.
    ///   - position: Where it lands, in this buffer's cells.
    /// - Returns: The runs to ask a render at each step of.
    package func runsShowingThrough(_ layer: Self, at position: (x: Int, y: Int)) -> [AnimatedCellRun] {
        guard !animatedCells.isEmpty, !layer.lines.isEmpty else { return [] }
        let rows = position.y..<(position.y + layer.lines.count)
        let columns = position.x..<(position.x + layer.width)
        var showing: [AnimatedCellRun] = []
        // What the layer fills with the base's field and what of it fades, per row of
        // the layer, read once.
        var masks: [Int: (taking: [Bool], fading: [Bool])] = [:]
        // Where the run is first, whether it animates after: `isAnimating` compares
        // the frames' bytes, and a `ZStack` or a `Layout` asks this of every run
        // already on its canvas at every later layer.
        for run in animatedCells where rows.contains(run.offsetY) {
            let span = run.offsetX..<(run.offsetX + run.width)
            guard span.overlaps(columns), run.isAnimating else { continue }
            let layerRow = run.offsetY - position.y
            let mask: (taking: [Bool], fading: [Bool])
            if let known = masks[layerRow] {
                mask = known
            } else {
                mask = (layer.columnsTakingBaseField(onRow: layerRow), layer.columnsFading(onRow: layerRow))
                masks[layerRow] = mask
            }
            let under = span.clamped(to: columns)
            let fading = under.filter { mask.fading[$0 - position.x] }
            if !fading.isEmpty {
                let looks = run.frames.map { $0.columnsLook(width: run.width) }
                let disagree = fading.contains { column in
                    let cell = column - run.offsetX
                    return looks.contains { $0[cell] != looks[0][cell] }
                }
                if disagree {
                    showing.append(run)
                    continue
                }
            }
            let taking = under.filter { mask.taking[$0 - position.x] }
            guard !taking.isEmpty else { continue }
            let fields = run.frames.map { $0.columnsFieldShown(width: run.width) }
            let disagree = taking.contains { column in
                let cell = column - run.offsetX
                return fields.contains { $0[cell] != fields[0][cell] }
            }
            if disagree { showing.append(run) }
        }
        return showing
    }

    /// For each column of this buffer's line `row`, whether the cell fades as it lands
    /// on a base: a translucent claim on it, or, on a run of this buffer's, on any of
    /// that run's frames. Resolved over the base's drawn cell, it shows something of
    /// that cell's field, ink or glyph. A material's frost counts with the alphas: it
    /// drops what is behind and averages its colours; a repeating fade counts at any
    /// phase, opaque being only where it happens to be this instant.
    private func columnsFading(onRow row: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: width)
        for region in opacityRegions
        where region.spans(row: row) && (region.isTranslucent || region.frosts || region.cycle != nil) {
            let start = min(max(0, region.offsetX), width)
            for column in start..<max(start, min(width, region.offsetX + region.width)) { mask[column] = true }
        }
        for run in animatedCells where run.offsetY == row {
            guard let alpha = run.alpha else { continue }
            for spans in alpha.perFrame {
                for span in spans where span.ink < 1 || span.field < 1 {
                    let start = min(max(0, run.offsetX + span.start), width)
                    for column in start..<max(start, min(width, run.offsetX + span.start + span.cells)) {
                        mask[column] = true
                    }
                }
            }
        }
        return mask
    }

    /// For each column of this buffer's line `row`, whether a compositor laying it on
    /// a base fills that cell with the base's field — in the line, or in any frame of
    /// a run of this buffer's on that row.
    private func columnsTakingBaseField(onRow row: Int) -> [Bool] {
        var mask = lines[row].columnsTakingBaseField(width: width)
        for run in animatedCells where run.offsetY == row {
            for frame in run.frames {
                for (cell, taken) in frame.columnsTakingBaseField(width: run.width).enumerated() where taken {
                    let column = run.offsetX + cell
                    if mask.indices.contains(column) { mask[column] = true }
                }
            }
        }
        return mask
    }
}
