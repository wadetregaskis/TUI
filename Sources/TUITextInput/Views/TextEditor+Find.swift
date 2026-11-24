//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditor+Find.swift
//
//  The find and replace bar a text editor draws above its text, presented by
//  `findNavigator(isPresented:)` or the editor's own Ctrl-F.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - Matching

/// How the find bar matches: the options its menu sets, as macOS's find bar's
/// (decisions B81). By default, as SwiftUI's find interface does: anywhere,
/// without regard to case.
struct FindOptions: Equatable {
    /// Where in a word a match may stand.
    enum Placement: Equatable, CaseIterable {
        /// Anywhere.
        case contains
        /// At the start of a word.
        case startsWith
        /// A whole word, start and end.
        case fullWord
    }

    var ignoresCase = true
    var placement = Placement.contains
}

/// Where a search string occurs in a text, under the find bar's options.
enum FindMatches {
    /// The ranges of `text` at which `query` occurs, from the start of
    /// `bounds` (all of it by default) to its end — none for an empty query.
    /// Each starts where the last ends: a match is never searched for inside
    /// another.
    static func matches(
        of query: String, in text: String, options: FindOptions = FindOptions(), within bounds: Range<String.Index>? = nil
    ) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        let bounds = bounds ?? text.startIndex..<text.endIndex
        var searchStart = bounds.lowerBound
        let compare: String.CompareOptions = options.ignoresCase ? .caseInsensitive : []
        while let match = text.range(of: query, options: compare, range: searchStart..<bounds.upperBound) {
            searchStart = match.upperBound
            if Self.stands(match, in: text, as: options.placement) { found.append(match) }
            if match.isEmpty { break }
        }
        return found
    }

    /// Whether `match` stands where `placement` asks: at a word's start, where
    /// the character before is no word's; a whole word, at its end too.
    private static func stands(_ match: Range<String.Index>, in text: String, as placement: FindOptions.Placement)
        -> Bool
    {
        func isWord(_ character: Character) -> Bool { character.isLetter || character.isNumber || character == "_" }
        let startsWord = match.lowerBound == text.startIndex || !isWord(text[text.index(before: match.lowerBound)])
        switch placement {
        case .contains: return true
        case .startsWith: return startsWord
        case .fullWord: return startsWord && (match.upperBound == text.endIndex || !isWord(text[match.upperBound]))
        }
    }

    /// The match `delta` steps on from `current`, wrapping round `count`
    /// matches: what the bar's arrows and Ctrl-G step to.
    static func index(from current: Int, by delta: Int, among count: Int) -> Int {
        let stepped = min(current, count - 1) + delta
        return (stepped % count + count) % count  // `delta` may be negative
    }

    /// `text` with each of `matches`, UTF-8 offsets into it in order and
    /// apart, replaced by `replacement`: built in one pass, the text between
    /// the matches copied once. Replace All used to make each replacement in
    /// a copy of the whole text, found by walking it from its start, a hang
    /// at thousands of matches in a large text (TEXTIN-2).
    static func replacing(_ matches: [Range<Int>], in text: String, with replacement: String) -> String {
        let view = text.utf8
        var result = ""
        result.reserveCapacity(
            view.count + matches.count * replacement.utf8.count - matches.reduce(0) { $0 + $1.count })
        var taken = text.startIndex
        for match in matches {
            let lower = view.index(view.startIndex, offsetBy: match.lowerBound)
            result += text[taken..<lower]
            result += replacement
            taken = view.index(view.startIndex, offsetBy: match.upperBound)
        }
        result += text[taken...]
        return result
    }
}

// MARK: - The bar

/// The find bar: a search field, the count, the previous and next buttons and
/// Done, and below it, where replace is allowed, a replacement field with
/// Replace and Replace All.
///
/// Return in the search field finds the next match, and in the replacement
/// field replaces the current one; Escape closes the bar. A match is shown by
/// selecting it in the editor, which scrolls to it.
///
/// The matches are asked of the editor's ``FindMatchCache``, which finds them
/// once for a query and a text and carries them through the editor's edits:
/// asked afresh in this body and the editor's on every evaluation, a key
/// with the bar up searched the whole document two or three times (TEXTIN-1).
struct _FindBar: View {
    /// The text, written by Replace before the editor has drawn.
    let text: Binding<String>
    /// The text as the matches are found in: the editor's
    /// (`TextEditor.searchedText()`), the same `String` while it is unchanged,
    /// which the cache knows at once.
    let searched: () -> String
    @Binding var query: String
    @Binding var replacement: String
    @Binding var current: Int
    @Binding var options: FindOptions
    let supportsReplace: Bool
    var menuTarget: TextEditingMenuTarget?
    /// Where the matches are kept.
    let cache: FindMatchCache
    /// Selects match `index` of the matches given, in the editor.
    let select: (FindMatchSet, Int) -> Void
    /// Closes the bar.
    let close: () -> Void

    private var handler: TextEditorHandler? { menuTarget?.handler as? TextEditorHandler }

    private func found(_ query: String, options: FindOptions) -> FindMatchSet {
        cache.matches(of: query, options: options, in: searched())
    }

    @FocusState private var isQueryFocused: Bool

    private func string(_ key: String) -> String {
        LocalizationService.shared.frameworkString(for: key)
    }

    /// `focused(_:)` and `onAppear(perform:)` are applied, and erased, by
    /// TUIFoundation (`erasedFocused(_:)`, `erasedOnAppear(perform:)`): their
    /// results name types only it can see, which this module would look up at
    /// run time on every evaluation (CONTRIBUTING.md, "Crossing a module
    /// boundary").
    var body: some View {
        let matches = found(query, options: options)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                TextField(string(LocalizationKey.Label.find.rawValue), text: $query)
                    .erasedFocused($isQueryFocused)
                    .onSubmit { step(by: 1, in: matches) }
                Text(verbatim: Self.counter(current: current, of: matches.count))
                Button("‹") { step(by: -1, in: matches) }
                Button("›") { step(by: 1, in: matches) }
                Button(string(LocalizationKey.Button.done.rawValue)) { close() }
            }
            optionsRow
            if supportsReplace {
                HStack(spacing: 1) {
                    TextField(string(LocalizationKey.Label.replaceWith.rawValue), text: $replacement)
                        .onSubmit { replaceCurrent(in: matches) }
                    Button(string(LocalizationKey.Button.replace.rawValue)) { replaceCurrent(in: matches) }
                    Button(string(LocalizationKey.Button.replaceAll.rawValue)) { replaceAll() }
                }
            }
        }
        .onExitCommand { close() }
        .erasedOnAppear { isQueryFocused = true }
        .onChange(of: query) { _, newQuery in
            current = 0
            let first = found(newQuery, options: options)
            if !first.isEmpty { select(first, 0) }
        }
        .onChange(of: options) { _, newOptions in
            current = 0
            let first = found(query, options: newOptions)
            if !first.isEmpty { select(first, 0) }
        }
    }

    /// Which match is current, of how many: `3/7`, or `0/0` with none. A
    /// position, not words, so it is drawn as it is and never looked up.
    ///
    /// A function of its own, not an expression in ``body``: written there as
    /// a key, its ternary of a literal and an interpolation took the body past
    /// the type-check guard's 2,000 solver scopes once `LocalizedStringKey`
    /// had SwiftUI's typed interpolations, and as a `String` it still did.
    private static func counter(current: Int, of count: Int) -> String {
        count == 0 ? "0/0" : "\(min(current, count - 1) + 1)/\(count)"
    }

    /// The options macOS's find bar has in the menu under its magnifier:
    /// whether case matters, and where in a word a match may stand — here a
    /// row of their own, a toggle and a button that steps through the three
    /// placements, since `Menu` and `Picker` live in modules a text editor
    /// does not depend on (decisions B81).
    private var optionsRow: some View {
        HStack(spacing: 1) {
            Toggle(string(LocalizationKey.Label.ignoreCase.rawValue), isOn: $options.ignoresCase)
            Button(string(Self.placementKey(options.placement).rawValue)) {
                let all = FindOptions.Placement.allCases
                options.placement = all[((all.firstIndex(of: options.placement) ?? 0) + 1) % all.count]
            }
        }
    }

    /// The words a placement is named by.
    private static func placementKey(_ placement: FindOptions.Placement) -> LocalizationKey.Label {
        switch placement {
        case .contains: .findContains
        case .startsWith: .findStartsWith
        case .fullWord: .findFullWord
        }
    }

    /// Moves to the next (`delta` 1) or previous (-1) match, wrapping.
    private func step(by delta: Int, in matches: FindMatchSet) {
        guard !matches.isEmpty else { return }
        current = FindMatches.index(from: current, by: delta, among: matches.count)
        select(matches, current)
    }

    /// Replaces `replaced`, matches in the text in order, as one step to
    /// undo: as the editor's own edit where it has drawn
    /// (``TextEditorHandler/replace(_:with:)``), else in the bound text.
    private func replace(_ replaced: [Range<Int>]) {
        if let handler {
            _ = handler.recordingUndoStep {
                handler.replace(replaced, with: replacement)
                return true
            }
        } else {
            text.wrappedValue = FindMatches.replacing(replaced, in: text.wrappedValue, with: replacement)
        }
    }

    /// Replaces the current match, then shows the one that takes its place.
    private func replaceCurrent(in matches: FindMatchSet) {
        guard !matches.isEmpty else { return }
        let match = matches.utf8[min(current, matches.count - 1)]
        replace([match])
        let remaining = found(query, options: options)
        guard !remaining.isEmpty else { return }
        // The next match after the replacement, which now sits at this index
        // unless the replacement itself matched.
        let after = FindMatchSet.firstIndex(
            in: remaining.utf8, startingAtOrAfter: match.lowerBound + replacement.utf8.count)
        current = after < remaining.count ? after : 0
        select(remaining, current)
    }

    /// Replaces every match.
    private func replaceAll() {
        let matches = found(query, options: options)
        guard !matches.isEmpty else { return }
        replace(matches.utf8)
        current = 0
    }
}
