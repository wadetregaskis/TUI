//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditor+Find.swift
//
//  The find and replace bar a text editor draws above its text, presented by
//  `findNavigator(isPresented:)` or the editor's own Ctrl-F.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

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
        guard !query.isEmpty else { return [] }
        var found: [Range<Int>] = []
        var searchStart = text.startIndex
        var offset = 0
        let compare: String.CompareOptions = options.ignoresCase ? .caseInsensitive : []
        while let match = text.range(of: query, options: compare, range: searchStart..<text.endIndex) {
            // Offsets counted forward from the last match only, so a text with
            // many matches is walked once.
            let lower = offset + text.distance(from: searchStart, to: match.lowerBound)
            let length = text.distance(from: match.lowerBound, to: match.upperBound)
            offset = lower + length
            searchStart = match.upperBound
            if Self.stands(match, in: text, as: options.placement) { found.append(lower..<(lower + length)) }
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
struct _FindBar: View {
    let text: Binding<String>
    @Binding var query: String
    @Binding var replacement: String
    @Binding var current: Int
    @Binding var options: FindOptions
    let supportsReplace: Bool
    /// Selects a match, as character offsets, in the editor.
    let select: (Range<Int>) -> Void
    /// Closes the bar.
    let close: () -> Void

    @FocusState private var isQueryFocused: Bool

    private func string(_ key: String) -> String {
        LocalizationService.shared.frameworkString(for: key)
    }

    /// `focused(_:)` and `onAppear(perform:)` are applied, and erased, by
    /// TUIkitFoundation (`erasedFocused(_:)`, `erasedOnAppear(perform:)`): their
    /// results name types only it can see, which this module would look up at
    /// run time on every evaluation (CONTRIBUTING.md, "Crossing a module
    /// boundary").
    var body: some View {
        let matches = FindMatches.ranges(of: query, in: text.wrappedValue, options: options)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                TextField(string(LocalizationKey.Label.find.rawValue), text: $query)
                    .erasedFocused($isQueryFocused)
                    .onSubmit { step(by: 1, in: matches) }
                Text(matches.isEmpty ? "0/0" : "\(min(current, matches.count - 1) + 1)/\(matches.count)")
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
            if let first = FindMatches.ranges(of: newQuery, in: text.wrappedValue, options: options).first { select(first) }
        }
        .onChange(of: options) { _, newOptions in
            current = 0
            if let first = FindMatches.ranges(of: query, in: text.wrappedValue, options: newOptions).first { select(first) }
        }
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
    private func step(by delta: Int, in matches: [Range<Int>]) {
        guard !matches.isEmpty else { return }
        current = FindMatches.index(from: current, by: delta, among: matches.count)
        select(matches[current])
    }

    /// Replaces the current match, then shows the one that takes its place.
    private func replaceCurrent(in matches: [Range<Int>]) {
        guard !matches.isEmpty else { return }
        let index = min(current, matches.count - 1)
        text.wrappedValue = FindMatches.replacing(matches[index], in: text.wrappedValue, with: replacement)
        let remaining = FindMatches.ranges(of: query, in: text.wrappedValue, options: options)
        guard !remaining.isEmpty else { return }
        // The next match after the replacement, which now sits at this index
        // unless the replacement itself matched.
        let after = matches[index].lowerBound + replacement.count
        current = remaining.firstIndex { $0.lowerBound >= after } ?? 0
        select(remaining[current])
    }

    /// Replaces every match.
    private func replaceAll() {
        let matches = FindMatches.ranges(of: query, in: text.wrappedValue, options: options)
        var result = text.wrappedValue
        for match in matches.reversed() {
            result = FindMatches.replacing(match, in: result, with: replacement)
        }
        text.wrappedValue = result
        current = 0
    }
}
