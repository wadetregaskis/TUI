//  🖥️ TUI — A Terminal UI framework for Swift
//  RunIntroducers.swift
//
//  The SGR introducers a TextEditor's runs open with, each derived once a
//  frame rather than once a run: a highlighted screen draws hundreds of runs
//  in a handful of looks (the highlighting design's B-ATTRED-44).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The SGR introducer of each look a frame's runs are drawn in
/// (``TextFieldContentRenderer/RunAccumulator``), derived the first time a run
/// in that look is written and kept for the rest of the frame.
///
/// A highlighted editor's screen is some 300 runs in perhaps ten looks: a
/// token's colour over the well, and the selection's, the caret's line, a find
/// match's. Deriving each run's introducer anew (``derive(_:)``) was 70% of
/// writing it (B-ATTRED-44).
///
/// One a frame, made with the rows' styling (``_TextEditorCore/RowStyling``),
/// and never kept past it: an introducer is spelled at the colour depth the
/// frame is drawn at, which the look does not say. Not a memo across frames,
/// and not shared: nothing outside the frame can see it.
final class RunIntroducers {
    /// What a run states of its drawing: its colours, whether they are
    /// exchanged (SGR 7), and its decoration.
    struct Look: Equatable {
        var ink: Color
        var field: Color?
        var isReversed: Bool
        var decoration: CellDecoration?
    }

    /// The looks derived so far, each with its introducer (`nil`: the look
    /// states nothing).
    private var kept: [(look: Look, introducer: String?)] = []
    /// Where the last look was found: a row's runs alternate between few.
    private var last = 0

    /// How many looks are kept: past it, a look is derived each time, as
    /// without a memo. A frame of the editor's draws far fewer.
    static let capacity = 32

    /// `look`'s introducer: derived the first time, kept from then on.
    func introducer(for look: Look) -> String? {
        if last < kept.count, kept[last].look == look { return kept[last].introducer }
        if let index = kept.firstIndex(where: { $0.look == look }) {
            last = index
            return kept[index].introducer
        }
        let introducer = Self.derive(look)
        if kept.count < Self.capacity {
            kept.append((look, introducer))
            last = kept.count - 1
        }
        return introducer
    }

    /// The introducer of `look`, or `nil` where it states nothing: its
    /// colours' opaque spellings, the run's claim carrying their alpha, and
    /// its decoration (``ANSIRenderer/styleSequence(for:)``).
    static func derive(_ look: Look) -> String? {
        var style = TextStyle()
        style.foregroundColor = look.ink.opaqueSpelling
        style.backgroundColor = look.field?.opaqueSpelling
        style.isInverted = look.isReversed
        look.decoration?.apply(to: &style)
        return ANSIRenderer.styleSequence(for: style)
    }
}
