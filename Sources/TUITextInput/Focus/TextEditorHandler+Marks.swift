//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+Marks.swift
//
//  The editor's side of its marks (B-ATTRED-13, lane H3 of the highlighting
//  design's §8.6): the app's and the find bar's matches (decisions B81)
//  taken each frame, carried through the editor's edits, and each drawn
//  line's found; and the find bar's keys.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension TextEditorHandler {
    /// Notes whether the editor has a find bar for Ctrl-F to open
    /// (``yieldsControlFToFind``).
    func noteFind(opensOnControlF: Bool) {
        yieldsControlFToFind = opensOnControlF
    }

    /// Whether `event` is a Control chord on one of `letters` that the editor
    /// leaves to its find bar: Ctrl-F, which opens it, and Ctrl-G, which
    /// steps through its matches — where it has a bar (decisions B81).
    func isFindChord(_ event: KeyEvent, on letters: Set<Character>) -> Bool {
        guard yieldsControlFToFind, event.ctrl, !event.alt, case .character(let letter) = event.key else { return false }
        return letters.contains(letter)
    }

    /// Takes the frame's marks: the app's, stated with their text, whose
    /// attributes are drawn as highlighting's are, under `environment`; and
    /// the find bar's matches.
    @MainActor
    func noteMarks(app: EditorMarkStatement?, find: FindMatchSet?, environment: EnvironmentValues) {
        marks.note(app: app, find: find, in: layout()) {
            (attributedSource != nil ? attributedStyling : nil) ?? EditorAttributedStyling(in: environment)
        }
    }

    /// The find bar's matches of the text, for `request`, or `nil` while the
    /// bar is down: kept by the bar's cache, which the handler holds while
    /// the bar is up and carries through its edits (``findCache``).
    func findMatches(for request: FindRequest?) -> FindMatchSet? {
        findCache = request?.cache
        guard let request else { return nil }
        return request.cache.matches(of: request.query, options: request.options, in: layout().text)
    }

    /// The find bar's matches on `line`, as its columns, which its rows tint.
    func findColumns(ofLine line: Int) -> [Range<Int>] {
        guard marks.hasFindMatches else { return [] }
        return marks.marks(ofLine: line, in: layout()).find
    }

    /// `styles`, `line`'s own with its highlighting, with the app's marks on
    /// the line drawn over them (B-ATTRED-8).
    func marked(_ styles: [EditorStyledRun], ofLine line: Int) -> [EditorStyledRun] {
        guard marks.hasMarks else { return styles }
        let runs = marks.marks(ofLine: line, in: layout()).runs
        return runs.isEmpty ? styles : EditorStyledRun.overlaying(runs, on: styles)
    }

    /// What the marks are carried through for `edit`, made from `before`,
    /// whose text must still be its own: `nil` where nothing is carried.
    func markEdit(_ edit: EditorLayout.Edit, from before: EditorLayout) -> (text: String, edit: EditorMarkEdit)? {
        guard !edit.isUnchanged, marks.carries(from: before) else { return nil }
        return (before.text, EditorMarkEdit(edit, from: before))
    }
}
