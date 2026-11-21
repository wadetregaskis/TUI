//  🖥️ TUI — A Terminal UI framework for Swift
//  FindMatchSetTests.swift
//
//  The find bar's matches found once and carried through the editor's edits
//  (TEXTIN-1).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization
import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("The find bar's matches, kept and carried")
struct FindMatchSetTests {
    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
        var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    /// A seeded generator, so a failure names the case that made it.
    struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(max(1, bound))) }
        mutating func text(_ length: Int, from alphabet: [Character]) -> String {
            String((0..<length).map { _ in alphabet[below(alphabet.count)] })
        }
    }

    /// The characters the random texts are made of: the query's letters in
    /// both cases, a word character, a space, line breaks, and an accented
    /// letter of two bytes.
    static let alphabet: [Character] = ["a", "b", "A", "B", "_", " ", "\n", "é", "a", "b"]

    /// Each match as character offsets.
    static func offsets(_ query: String, in text: String, options: FindOptions = FindOptions()) -> [Range<Int>] {
        FindMatches.matches(of: query, in: text, options: options).map {
            text.distance(from: text.startIndex, to: $0.lowerBound)..<text.distance(from: text.startIndex, to: $0.upperBound)
        }
    }

    // MARK: - Carrying

    /// `before` laid out, edited by `replacement`, and laid out again as the
    /// editor lays its edit out; and `set`, of `before`, carried through it.
    static func carry(
        _ set: FindMatchSet, through replacement: TextEditorReplacement
    ) -> (carried: FindMatchSet, text: String) {
        let before = EditorLayout(text: set.text)
        var lines = EditedLines(before.lines)
        lines.apply(replacement)
        guard let edit = before.replacing(lines) else {
            Issue.record("a text of one kind of line break did not splice")
            return (set, set.text)
        }
        let markEdit = EditorMarkEdit(edit, from: before)
        let after = before.laidOut(edit, reusingStorage: false)
        return (set.carried(through: markEdit, to: after), after.text)
    }

    @Test(
        "Matches carried through random edits are the matches found afresh",
        arguments: [
            ("ab", FindOptions(ignoresCase: true, placement: .contains)),
            ("ab", FindOptions(ignoresCase: false, placement: .contains)),
            ("a", FindOptions(ignoresCase: true, placement: .startsWith)),
            ("ab", FindOptions(ignoresCase: true, placement: .fullWord)),
            // Overlapping candidates: "aa" in "aaa" is one match, not two.
            ("aa", FindOptions(ignoresCase: true, placement: .contains)),
            ("é", FindOptions(ignoresCase: true, placement: .contains)),
            // A break in the query: searched for whole after every edit.
            ("b\na", FindOptions(ignoresCase: true, placement: .contains)),
        ])
    func carriedMatchesFreshSearch(query: String, options: FindOptions) {
        var random = Random(state: UInt64(query.utf8.count) &* 7919 &+ (options.ignoresCase ? 1 : 0))
        var wrong: [String] = []
        for round in 0..<300 {
            let text = random.text(5 + random.below(40), from: Self.alphabet)
            let set = FindMatchSet(query: query, options: options, text: text)
            let lines = EditorLayout(text: text).lines
            // An edit anywhere, from a point to across a few lines, putting in
            // nothing, characters, or line breaks: before, inside and after a
            // match, and joining and splitting lines.
            let startLine = random.below(lines.count)
            let start = TextEditorPosition(line: startLine, column: random.below(lines[startLine].count + 1))
            let endLine = min(lines.count - 1, startLine + random.below(3))
            var end = TextEditorPosition(line: endLine, column: random.below(lines[endLine].count + 1))
            if end < start { end = start }
            let inserted = random.text(random.below(5), from: Self.alphabet)
            let replacement = TextEditorReplacement(
                from: start, to: end,
                with: inserted.split(separator: "\n", omittingEmptySubsequences: false).map { Array($0) })
            let (carried, after) = Self.carry(set, through: replacement)
            let fresh = FindMatchSet(query: query, options: options, text: after)
            if carried.utf8 != fresh.utf8 || carried.text != after {
                wrong.append("round \(round): \(text.debugDescription) → \(after.debugDescription): "
                    + "\(carried.utf8) where a search finds \(fresh.utf8)")
            }
        }
        #expect(wrong.isEmpty, "\(wrong.prefix(3))")
    }

    @Test("Edits before, inside and after a match, and across a line join and split")
    func namedEdits() {
        let set = FindMatchSet(query: "cat", options: FindOptions(), text: "a cat\nthe CAT sat\ncat")
        func carried(_ replacement: TextEditorReplacement) -> [Range<Int>] { Self.carry(set, through: replacement).carried.utf8 }
        #expect(set.utf8 == [2..<5, 10..<13, 18..<21])
        // Before: everything after moves.
        #expect(carried(TextEditorReplacement(line: 0, columns: 0..<0, with: ["x"])) == [3..<6, 11..<14, 19..<22])
        // Inside: the match is gone, the others stay or move.
        #expect(carried(TextEditorReplacement(line: 1, columns: 5..<5, with: ["x"])) == [2..<5, 19..<22])
        // After, at the end of a match: it stays, its neighbour moves.
        #expect(carried(TextEditorReplacement(line: 1, columns: 7..<7, with: ["s"])) == [2..<5, 10..<13, 19..<22])
        // A line split inside a match, and a join that makes one.
        #expect(carried(TextEditorReplacement(
            from: TextEditorPosition(line: 0, column: 3), to: TextEditorPosition(line: 0, column: 3), with: [[], []])) == [11..<14, 19..<22])
        let joined = FindMatchSet(query: "cat", options: FindOptions(), text: "ca\nt")
        let join = Self.carry(
            joined, through: TextEditorReplacement(
                from: TextEditorPosition(line: 0, column: 2), to: TextEditorPosition(line: 1, column: 0)))
        #expect(join.text == "cat" && join.carried.utf8 == [0..<3])
    }

    @Test("Ten keys typed with the bar up search the document no more: the matches are carried")
    func keysWithTheBarUpDoNotSearch() {
        let text = Box(String(repeating: "one two three\n", count: 200))
        let harness = InputChainHarness(width: 50, height: 12)
        func view() -> some View { TextEditor(text: text.binding).findNavigator(isPresented: .constant(true)) }
        harness.frame(view())
        harness.frame(view())
        for character in "two" {
            harness.press(KeyEvent(character: character))
            harness.frame(view())
        }
        guard let handler = harness.focusManager.activeSection?.focusables.compactMap({ $0 as? TextEditorHandler }).first,
            let cache = handler.findCache
        else {
            Issue.record("the editor has no handler, or no find cache while the bar is up")
            return
        }
        let searches = cache.searches
        // Off the match the bar selected, which a key would replace.
        handler.moveCursor(toLine: 100, column: 4)
        handler.selectionAnchor = nil
        for character in "xtwo two " {
            _ = handler.handleKeyEvent(KeyEvent(key: .character(character)))
            harness.frame(view())
        }
        _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        harness.frame(view())
        #expect(cache.searches == searches, "\(cache.searches - searches) whole searches for ten keys")
        let found = cache.matches(of: "two", options: FindOptions(), in: text.value)
        #expect(found.utf8 == FindMatchSet(query: "two", options: FindOptions(), text: text.value).utf8)
        #expect(found.count == 202, "the 200 lines' and the two typed")
        // "one xtwo two " and "two three", split by the Return.
        #expect(handler.findColumns(ofLine: 100) == [5..<8, 9..<12])
        #expect(handler.findColumns(ofLine: 101) == [0..<3])
    }
}
