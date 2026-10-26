//  🖥️ TUI — A Terminal UI framework for Swift
//  CellSGRState.swift
//
//  Reading back what a drawn line says about one cell: the SGR state in force
//  where a word starts, and the background a colour paints, spelled the way that
//  state spells it. Shared by the suites that ask what a cursor row or a
//  highlighted menu row is filled with across frames.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling

/// The SGR state in force on the first cell of `word`, on the first of `lines`
/// that shows it, or `nil` where none does.
func sgrState(of word: String, in lines: [String]) -> SGRState? {
    guard let line = lines.first(where: { $0.stripped.contains(word) }),
        let range = line.stripped.range(of: word)
    else { return nil }
    let target = line.stripped.distance(from: line.stripped.startIndex, to: range.lowerBound)
    var state = SGRState()
    var index = 0
    for segment in line.ansiSegments() {
        switch segment {
        case .ansi(let sequence, true): state.apply(sequence)
        case .ansi: continue
        case .visible:
            if index == target { return state }
            index += 1
        }
    }
    return nil
}

/// The background `color` paints under the palette of a render that sets none,
/// as a cell's SGR state spells it — see ``asDrawn(_:in:)``.
func renderedBackground(of color: Color) -> String {
    var state = SGRState()
    state.apply(ANSIRenderer.backgroundCode(for: asDrawn(color).opaqueSpelling))
    return state.renderedBackground
}

#endif
