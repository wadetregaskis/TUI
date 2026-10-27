//  🖥️ TUI — A Terminal UI framework for Swift
//  TextUndoHistoryDifferentialTests.swift
//
//  Undo as edits (owner ruling B-PASTE-1-EDITOR, 2026-10-26), checked against
//  the whole-text snapshots it replaced: the same random runs of edits,
//  typing, undos, redos, replacements from outside and the step limit, driven
//  through both histories the way a text control drives one, must leave the
//  same text, caret and marks after every operation.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUITextInput

/// The snapshot history `TextUndoHistory` replaced, kept as the reference:
/// every state is the whole text before its edit. Two rules changed with the
/// edits, and changed here too: texts compare by their bytes, not by `==`
/// (canonically equivalent texts are not the text an edit left), and a
/// record not made, because the text is unchanged, still forgets redo.
private struct SnapshotUndoHistory<Caret: Equatable> {
    private struct Entry {
        let text: String
        let caret: Caret
        let mark: TextUndoMark
    }

    private var states: [Entry] = []

    private var redoStates: [Entry] = []

    private var written: String?

    private var dropped: [TextUndoMark] = []

    private var typingRun: (text: String, caret: Caret, mark: TextUndoMark?)?

    let limit: Int

    init(limit: Int = 50) {
        self.limit = limit
    }

    @discardableResult
    mutating func forgetIfReplaced(current: String) -> Bool {
        guard let written, !TextEdit.sameBytes(written, current) else { return false }
        forget()
        return true
    }

    mutating func forget() {
        dropped += heldMarks
        states.removeAll()
        redoStates.removeAll()
        written = nil
        typingRun = nil
    }

    @discardableResult
    mutating func record(text: String, caret: Caret, continuingTyping: Bool = false) -> TextUndoMark? {
        if continuingTyping, let run = typingRun, run.caret == caret, TextEdit.sameBytes(run.text, text) {
            return nil
        }
        typingRun = nil
        if let last = states.last, TextEdit.sameBytes(last.text, text) {
            // As the edit history does: the edit about to be made is a new
            // branch, so redo goes.
            dropped += redoStates.map(\.mark)
            redoStates.removeAll()
            return nil
        }
        dropped += redoStates.map(\.mark)
        redoStates.removeAll()
        let mark = TextUndoMark()
        append(Entry(text: text, caret: caret, mark: mark))
        return mark
    }

    private mutating func append(_ entry: Entry) {
        states.append(entry)
        if states.count > limit {
            dropped.append(states.removeFirst().mark)
        }
    }

    mutating func noteTyped(text: String, caret: Caret) {
        typingRun = (text, caret, states.last?.mark)
    }

    mutating func endTypingRun(unlessNewestIn manager: UndoManager?) {
        guard let manager, let mark = typingRun?.mark, !TextUndoBridge.isNewestStep(mark, on: manager) else { return }
        typingRun = nil
    }

    mutating func noteWritten(_ text: String) {
        written = text
    }

    mutating func undo(
        from current: (text: String, caret: Caret), mark: TextUndoMark? = nil
    ) -> (text: String, caret: Caret)? {
        guard let previous = states.last, mark.map({ $0 === previous.mark }) ?? true else { return nil }
        typingRun = nil
        states.removeLast()
        redoStates.append(Entry(text: current.text, caret: current.caret, mark: previous.mark))
        return (previous.text, previous.caret)
    }

    mutating func redo(
        from current: (text: String, caret: Caret), mark: TextUndoMark? = nil
    ) -> (text: String, caret: Caret)? {
        guard let next = redoStates.last, mark.map({ $0 === next.mark }) ?? true else { return nil }
        typingRun = nil
        redoStates.removeLast()
        append(Entry(text: current.text, caret: current.caret, mark: next.mark))
        return (next.text, next.caret)
    }

    mutating func takeDroppedMarks() -> [TextUndoMark] {
        defer { dropped.removeAll() }
        return dropped
    }

    var allMarks: [TextUndoMark] {
        heldMarks + dropped
    }

    private var heldMarks: [TextUndoMark] {
        states.map(\.mark) + redoStates.map(\.mark)
    }
}

/// A seeded generator, so a failing run can be replayed.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// One text control's document and caret, driven through a history as the
/// controls drive theirs.
private struct Document<History> {
    var text: String
    var caret: Int
    var history: History
}

@Suite("Undo as edits matches whole-text snapshots")
struct TextUndoHistoryDifferentialTests {
    /// Pieces that make the bytes hard: a combining mark, a flag, a joined
    /// family, a CRLF, a wide character, plain letters, a newline.
    private static let pieces = ["a", "b", "z", " ", "\n", "\r\n", "e\u{301}", "\u{301}", "🇦🇺", "🇦", "👩‍👩‍👧", "漢", "é"]

    private static func piece(_ rng: inout SplitMix) -> String {
        let count = Int.random(in: 0...4, using: &rng)
        return (0..<count).map { _ in pieces.randomElement(using: &rng)! }.joined()
    }

    /// `text` with a random range of its characters replaced by a random piece.
    private static func edited(_ text: String, _ rng: inout SplitMix) -> (String, Int) {
        let characters = Array(text)
        let start = Int.random(in: 0...characters.count, using: &rng)
        let end = Int.random(in: start...min(characters.count, start + 3), using: &rng)
        let inserted = piece(&rng)
        let result = String(characters[..<start]) + inserted + String(characters[end...])
        return (result, start + inserted.count)
    }

    @Test("Random runs leave the same text, caret and marks", arguments: 0..<200)
    func randomRuns(seed: UInt64) {
        var rng = SplitMix(state: seed)
        let start = Self.piece(&rng)
        var edits = Document(text: start, caret: 0, history: TextUndoHistory<Int>(limit: 6))
        var snaps = Document(text: start, caret: 0, history: SnapshotUndoHistory<Int>(limit: 6))
        for step in 0..<120 {
            let operation = Int.random(in: 0..<10, using: &rng)
            switch operation {
            case 0...3:
                // An edit, a typing one (continuing a run) half the time.
                let typing = Bool.random(using: &rng)
                let (after, caret) = Self.edited(edits.text, &rng)
                // A control checks for a replacement before it writes, as at
                // every render.
                edits.history.forgetIfReplaced(current: edits.text)
                snaps.history.forgetIfReplaced(current: snaps.text)
                let markA = edits.history.record(text: edits.text, caret: edits.caret, continuingTyping: typing)
                let markB = snaps.history.record(text: snaps.text, caret: snaps.caret, continuingTyping: typing)
                #expect((markA == nil) == (markB == nil), "seed \(seed) step \(step): record")
                for document in [0, 1] {
                    if document == 0 {
                        edits.text = after
                        edits.caret = caret
                        edits.history.noteWritten(after)
                        if typing { edits.history.noteTyped(text: after, caret: caret) }
                    } else {
                        snaps.text = after
                        snaps.caret = caret
                        snaps.history.noteWritten(after)
                        if typing { snaps.history.noteTyped(text: after, caret: caret) }
                    }
                }
            case 4...6:
                edits.history.forgetIfReplaced(current: edits.text)
                snaps.history.forgetIfReplaced(current: snaps.text)
                let a = edits.history.undo(from: (edits.text, edits.caret))
                let b = snaps.history.undo(from: (snaps.text, snaps.caret))
                #expect(a?.text == b?.text && a?.caret == b?.caret, "seed \(seed) step \(step): undo")
                if let a { (edits.text, edits.caret) = (a.text, a.caret); edits.history.noteWritten(a.text) }
                if let b { (snaps.text, snaps.caret) = (b.text, b.caret); snaps.history.noteWritten(b.text) }
            case 7...8:
                edits.history.forgetIfReplaced(current: edits.text)
                snaps.history.forgetIfReplaced(current: snaps.text)
                let a = edits.history.redo(from: (edits.text, edits.caret))
                let b = snaps.history.redo(from: (snaps.text, snaps.caret))
                #expect(a?.text == b?.text && a?.caret == b?.caret, "seed \(seed) step \(step): redo")
                if let a { (edits.text, edits.caret) = (a.text, a.caret); edits.history.noteWritten(a.text) }
                if let b { (snaps.text, snaps.caret) = (b.text, b.caret); snaps.history.noteWritten(b.text) }
            default:
                // The app replaces the text from outside, now and then.
                if Int.random(in: 0..<4, using: &rng) == 0 {
                    let replacement = Self.piece(&rng)
                    edits.text = replacement
                    snaps.text = replacement
                }
            }
            #expect(edits.text == snaps.text, "seed \(seed) step \(step): the texts drifted")
            #expect(Array(edits.text.utf8) == Array(snaps.text.utf8), "seed \(seed) step \(step): the bytes drifted")
            #expect(
                edits.history.takeDroppedMarks().count == snaps.history.takeDroppedMarks().count,
                "seed \(seed) step \(step): dropped marks")
            #expect(edits.history.allMarks.count == snaps.history.allMarks.count, "seed \(seed) step \(step): marks held")
        }
    }

    @Test("An edit gives back exactly the bytes it took, splitting a cluster or not")
    func byteExact() {
        let pairs = [("a🇦🇺b", "a🇦b"), ("e\u{301}x", "ex"), ("x\r\ny", "x\ry"), ("", "👩‍👩‍👧"), ("abc", "abc"), ("ab", "ba")]
        for (before, after) in pairs {
            let edit = TextEdit(from: before, to: after)
            #expect(edit.applied(before).map { Array($0.utf8) } == Array(after.utf8), "\(before) → \(after)")
            #expect(edit.reverted(after).map { Array($0.utf8) } == Array(before.utf8), "\(after) ← \(before)")
        }
    }

    @Test("A text the history did not produce is not spliced into: the history forgets itself")
    func foreignTextForgets() {
        var history = TextUndoHistory<Int>()
        history.record(text: "one", caret: 0)
        history.noteWritten("one two")
        history.record(text: "one two", caret: 0)
        history.noteWritten("one two three")
        // The newest step is whole text; undo it, then hand the edit below a
        // text that is not the one it left.
        _ = history.undo(from: ("one two three", 0))
        #expect(history.undo(from: ("something else", 0)) == nil)
        #expect(history.undo(from: ("one two", 0)) == nil, "forgotten")
    }

    @Test("Fifty steps over a large text keep one copy of it, not fifty")
    func memoryIsTheEdits() {
        var history = TextUndoHistory<Int>()
        var text = String(repeating: "line of text\n", count: 20_000)
        for step in 0..<50 {
            history.record(text: text, caret: 0)
            text += "step \(step)\n"
            history.noteWritten(text)
        }
        #expect(history.keptBytes < text.utf8.count + 50 * 64, "kept \(history.keptBytes) bytes for \(text.utf8.count)")
    }
}
