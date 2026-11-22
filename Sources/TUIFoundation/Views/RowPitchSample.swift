//  🖥️ TUI — A Terminal UI framework for Swift
//  RowPitchSample.swift
//
//  The running estimate a windowed column prices the rows it never measured
//  at: the pitches of the rows it has measured, one sample a row. What a lazy
//  stack's anchored walk and pulled column keep (`StackWindowState`), and a
//  pulled view of rows of varying height (`PulledRows`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// The pitches a column has measured, one per row, and what they price the
/// rows it has not at.
///
/// One sample a ROW, not a measure: a row measured again — on every frame it
/// stays on screen — replaces its sample, so the mean is the rows', not the
/// frames'. That is the design's rule that a level's estimate moves only when
/// it measures a row it had not ("How estimates stay steady", rule 4, in
/// `Documentation/Historical/Scrolling/SCROLL-FIT design.md`). Counted a
/// measure at a time, a stack that sat on its first screen of one-line rows
/// while something above it animated held thousands of samples of one, and
/// the screens of taller rows paged through after it could not move the mean.
///
/// Bounded: past ``limit`` rows a new row is not sampled, so the table stays
/// small at any row count.
/// A ``RowPitchSample`` a walk holds while it records into it: the run of rows
/// it is the sample of can be made the newest by another walk in the same
/// frame (a section's loop inside its stack's column), and the walk must go on
/// recording into its own.
final class RowPitchSampleBox {
    var sample = RowPitchSample()
}

/// The rows a ``RowPitchSample`` is of: their width, their first and last
/// rows' keys, and their count (`StackWindowState.noteRowShape`).
struct RowPitchSampleRun {
    let width: Int
    var firstKey: String?
    var lastKey: String?
    var rowCount = 0
    let box = RowPitchSampleBox()

    init(width: Int) { self.width = width }
}

struct RowPitchSample {
    /// The most rows the sample keeps: enough to describe the rows, few
    /// enough to stay small at any row count.
    static let limit = 1_024

    private var pitches: [Int: Int] = [:]
    private var total = 0

    /// Whether any row has been sampled.
    var isEmpty: Bool { pitches.isEmpty }

    /// Records row `row`'s measured pitch, replacing what it measured before.
    mutating func note(_ pitch: Int, of row: Int) {
        if let old = pitches[row] {
            guard old != pitch else { return }
            pitches[row] = pitch
            total = total.saturatingAdding(pitch.saturatingSubtracting(old))
        } else if pitches.count < Self.limit {
            pitches[row] = pitch
            total = total.saturatingAdding(pitch)
        }
    }

    /// Forgets every sample.
    mutating func removeAll() {
        pitches.removeAll(keepingCapacity: true)
        total = 0
    }

    /// The mean pitch rounded to a line, at least one, or `nil` before a
    /// sample: what a reading in whole rows divides by, and what a measure
    /// that must not move with every row sampled answers with.
    var roundedPitch: Int? {
        guard !pitches.isEmpty else { return nil }
        return max(1, (total + pitches.count / 2) / pitches.count)
    }

    /// `rows` rows at the mean pitch, in lines, rounded, held at `Int`'s
    /// bounds; `nil` before a sample.
    ///
    /// At the mean itself, not the whole line it rounds to: priced at a whole
    /// line, rows of 1.4 lines on average put a total 29% short, and rows of
    /// 1.6, 25% long.
    func lines(ofRows rows: Int) -> Int? {
        guard let mean else { return nil }
        return Int(clamping: (Double(rows) * mean).rounded())
    }

    /// How many whole rows at the mean pitch `lines` lines hold, held at
    /// `Int`'s bounds; `nil` before a sample. The inverse of
    /// ``lines(ofRows:)``: the row a line of the content priced at the mean
    /// falls in, which is where a scrollbar jump lands.
    func rows(inLines lines: Int) -> Int? {
        guard let mean else { return nil }
        return Int(clamping: (Double(lines) / mean).rounded(.down))
    }

    /// The mean pitch, at least a line. A pitch of zero lines is a row that
    /// draws nothing; a mean of them still prices a row at a line, so a
    /// division by it, and a walk priced by it, always progress.
    private var mean: Double? {
        guard !pitches.isEmpty else { return nil }
        return max(1, Double(total) / Double(pitches.count))
    }
}
