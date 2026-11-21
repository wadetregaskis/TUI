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
    /// The ranges, as character offsets, at which `query` occurs in `text` —
    /// none for an empty query.
    static func ranges(of query: String, in text: String, options: FindOptions = FindOptions()) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var (searchStart, offset) = (text.startIndex, 0)
        for match in matches(of: query, in: text, options: options) {
            // Offsets counted forward from the last match only, so a text with
            // many matches is walked once.
            let lower = offset + text.distance(from: searchStart, to: match.lowerBound)
            let length = text.distance(from: match.lowerBound, to: match.upperBound)
            (searchStart, offset) = (match.upperBound, lower + length)
            found.append(lower..<(lower + length))
        }
        return found
    }

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

    /// `text` with the characters at `offsets` replaced by `replacement`.
    static func replacing(_ offsets: Range<Int>, in text: String, with replacement: String) -> String {
        let lower = text.index(text.startIndex, offsetBy: offsets.lowerBound, limitedBy: text.endIndex) ?? text.endIndex
        let upper = text.index(lower, offsetBy: offsets.count, limitedBy: text.endIndex) ?? text.endIndex
        var result = text
        result.replaceSubrange(lower..<upper, with: replacement)
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
    let text: Binding<String>
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
        cache.matches(of: query, options: options, in: text.wrappedValue)
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

    private func writeText(_ newText: String) {
        if let handler {
            _ = handler.recordingUndoStep {
                handler.write(newText)
                return true
            }
        } else {
            text.wrappedValue = newText
        }
    }

    /// Replaces the current match, then shows the one that takes its place.
    private func replaceCurrent(in matches: FindMatchSet) {
        let offsets = FindMatches.ranges(of: query, in: text.wrappedValue, options: options)
        guard !offsets.isEmpty else { return }
        let index = min(current, offsets.count - 1)
        writeText(FindMatches.replacing(offsets[index], in: text.wrappedValue, with: replacement))
        let remaining = FindMatches.ranges(of: query, in: text.wrappedValue, options: options)
        guard !remaining.isEmpty else { return }
        // The next match after the replacement, which now sits at this index
        // unless the replacement itself matched.
        let after = offsets[index].lowerBound + replacement.count
        current = remaining.firstIndex { $0.lowerBound >= after } ?? 0
        select(found(query, options: options), current)
    }

    /// Replaces every match.
    private func replaceAll() {
        let matches = FindMatches.ranges(of: query, in: text.wrappedValue, options: options)
        var result = text.wrappedValue
        for match in matches.reversed() {
            result = FindMatches.replacing(match, in: result, with: replacement)
        }
        writeText(result)
        current = 0
    }
}
