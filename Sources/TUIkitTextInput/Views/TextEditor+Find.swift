//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditor+Find.swift
//
//  The find and replace bar a text editor draws above its text, presented by
//  `findNavigator(isPresented:)` or the editor's own Ctrl-G.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

// MARK: - Matching

/// Where a search string occurs in a text: SwiftUI's find interface matches
/// without regard to case, and so does this.
enum FindMatches {
    /// The ranges, as character offsets, at which `query` occurs in `text` —
    /// none for an empty query.
    static func ranges(of query: String, in text: String) -> [Range<Int>] {
        guard !query.isEmpty else { return [] }
        var found: [Range<Int>] = []
        var searchStart = text.startIndex
        var offset = 0
        while let match = text.range(of: query, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            // Offsets counted forward from the last match only, so a text with
            // many matches is walked once.
            let lower = offset + text.distance(from: searchStart, to: match.lowerBound)
            let length = text.distance(from: match.lowerBound, to: match.upperBound)
            found.append(lower..<(lower + length))
            offset = lower + length
            searchStart = match.upperBound
            if match.isEmpty { break }
        }
        return found
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
    let supportsReplace: Bool
    /// Selects a match, as character offsets, in the editor.
    let select: (Range<Int>) -> Void
    /// Closes the bar.
    let close: () -> Void

    @FocusState private var isQueryFocused: Bool

    private func string(_ key: String) -> String {
        LocalizationService.shared.frameworkString(for: key)
    }

    var body: some View {
        let matches = FindMatches.ranges(of: query, in: text.wrappedValue)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                TextField(string(LocalizationKey.Label.find.rawValue), text: $query)
                    .focused($isQueryFocused)
                    .onSubmit { step(by: 1, in: matches) }
                Text(matches.isEmpty ? "0/0" : "\(min(current, matches.count - 1) + 1)/\(matches.count)")
                Button("‹") { step(by: -1, in: matches) }
                Button("›") { step(by: 1, in: matches) }
                Button(string(LocalizationKey.Button.done.rawValue)) { close() }
            }
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
        .onAppear { isQueryFocused = true }
        .onChange(of: query) { _, newQuery in
            current = 0
            if let first = FindMatches.ranges(of: newQuery, in: text.wrappedValue).first { select(first) }
        }
    }

    /// Moves to the next (`delta` 1) or previous (-1) match, wrapping.
    private func step(by delta: Int, in matches: [Range<Int>]) {
        guard !matches.isEmpty else { return }
        let count = matches.count
        let stepped: Int = min(current, count - 1) + delta
        current = (stepped % count + count) % count  // `delta` may be negative
        select(matches[current])
    }

    /// Replaces the current match, then shows the one that takes its place.
    private func replaceCurrent(in matches: [Range<Int>]) {
        guard !matches.isEmpty else { return }
        let index = min(current, matches.count - 1)
        text.wrappedValue = FindMatches.replacing(matches[index], in: text.wrappedValue, with: replacement)
        let remaining = FindMatches.ranges(of: query, in: text.wrappedValue)
        guard !remaining.isEmpty else { return }
        // The next match after the replacement, which now sits at this index
        // unless the replacement itself matched.
        let after = matches[index].lowerBound + replacement.count
        current = remaining.firstIndex { $0.lowerBound >= after } ?? 0
        select(remaining[current])
    }

    /// Replaces every match.
    private func replaceAll() {
        let matches = FindMatches.ranges(of: query, in: text.wrappedValue)
        var result = text.wrappedValue
        for match in matches.reversed() {
            result = FindMatches.replacing(match, in: result, with: replacement)
        }
        text.wrappedValue = result
        current = 0
    }
}
