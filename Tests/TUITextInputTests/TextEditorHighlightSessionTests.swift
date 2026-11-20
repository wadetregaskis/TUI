//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHighlightSessionTests.swift
//
//  A highlight session on its own (the highlighting design's B-ATTRED-20,
//  21, 24, 27 to 30, lane H6′), the test playing both the editor and the
//  highlighter one step at a time: updates, whole-line changes folded into
//  one, stale publishes refused, tokens carried through edits, the window,
//  the guards, closing and cancellation. Nothing here sleeps or races.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization
import Testing

@testable import TUIFoundation
@_spi(TextEditorHighlighting) @testable import TUITextInput

// A wait that never ends would otherwise hang the run. Very generous, as NamedTaskTests' is: its awaits hop
// through the cooperative pool, which a full parallel run saturates; three minutes timed out four of these
// tests in the batch50b gate (2026-11-20, "Time limit was exceeded: 180.000 seconds"), each passing alone.
@Suite("Text editor: a highlight session", .timeLimit(.minutes(45)))
struct TextEditorHighlightSessionTests {
    typealias Token = FakeTreeStyler.Token
    typealias Session = TextEditorHighlightSession<Token>

    /// Counts the frames a session asks for.
    final class Frames: Sendable {
        private let count = Mutex(0)
        var asked: Int { count.withLock { $0 } }
        func ask() { count.withLock { $0 += 1 } }
    }

    /// A session over `text`, the frames it asks for counted.
    static func session(_ text: String, maximumLineLength: Int = 20_000) -> (Session, Frames) {
        let frames = Frames()
        let layout = EditorLayout(text: text)
        let session = Session(
            text: text, lineCount: layout.lines.count, maximumLineLength: maximumLineLength,
            requestFrame: { frames.ask() })
        return (session, frames)
    }

    /// Tokens from `(offset, token)` pairs.
    static func tokens(_ pairs: [(Int, Token)]) -> TextEditorTokens<Token> {
        var tokens = TextEditorTokens<Token>()
        for (offset, token) in pairs { tokens.append(token, at: offset) }
        return tokens
    }

    /// Edits `text` as the editor does, and tells `session`: the layout's
    /// own splice of `edited`'s lines, its change found by the handler's
    /// code. Returns the text after.
    @MainActor
    static func edit(_ session: Session, _ text: String, to edited: String) throws -> String {
        let handler = TextEditorHandler(focusID: "t", text: .constant(text))
        let before = handler.layout()
        let key = EditorHighlighterKey(SteppedHighlighter(inbox: SessionInbox()))
        handler.connectHighlighter(
            EditorHighlightConnection(key: key, feed: session, style: { _ in AttributeContainer() }), layout: before)
        var editedLines = EditedLines(before.lines)
        let last = TextEditorPosition(line: before.lines.count - 1, column: before.lines[before.lines.count - 1].count)
        editedLines.apply(
            TextEditorReplacement(
                from: TextEditorPosition(line: 0, column: 0), to: last, with: EditorLayout(text: edited).lines))
        let edit = try #require(before.replacing(editedLines))
        #expect(edit.text == edited)
        let change = try #require(handler.highlightEdit(edit, from: before))
        let after = before.laidOut(edit, reusingStorage: false)
        _ = session.textChanged(to: after.text, lineCount: after.lines.count, by: change)
        return after.text
    }

    // MARK: - Updates

    @Test("The first update is the text whole; with nothing new, the next waits until the editor rings")
    func firstUpdateIsWhole() async throws {
        let (session, _) = Self.session("one\ntwo\r\nthree\rfour")
        let update = try #require(await session.nextUpdate())
        #expect(update.change == nil)
        #expect(update.text.version == 0)
        #expect(update.text.lineCount == 4)
        #expect(String(update.text.line(1)) == "two", "without its CRLF")
        #expect(String(update.text.line(2)) == "three", "a lone CR is a break")
        #expect(update.text.utf8Offset(ofLine: 3) == 15)
        #expect(update.text.line(containingUTF8Offset: 7) == 1, "a line's break is its own")
        #expect(update.text.line(containingUTF8Offset: 999) == 3)
        // An unsafe pointer, read: `unsafe` for 6.4, which checks it; 6.2 does not.
        let bytes = unsafe update.text.withUTF8 { unsafe Array($0) }
        #expect(bytes == Array("one\ntwo\r\nthree\rfour".utf8))
        // Rung by a scroll: the version unchanged (B-ATTRED-27).
        _ = session.show(lines: 1..<3)
        let scroll = try #require(await session.nextUpdate())
        #expect(scroll.text.version == 0)
        #expect(scroll.change == nil)
        #expect(scroll.visibleLines == 1..<3)
    }

    @Test("Edits fold into one change by whole lines, which takes the old text's bytes to the new's")
    @MainActor
    func editsFoldIntoOneChange() async throws {
        let original = "alpha\nbeta\ngamma\ndelta\nepsilon"
        let (session, _) = Self.session(original)
        _ = try #require(await session.nextUpdate())
        var text = try Self.edit(session, original, to: "alpha\nbeta!\ngamma\ndelta\nepsilon")
        text = try Self.edit(session, text, to: "alpha\nbeta!\ngamma\nDELTA\nepsilon")
        let update = try #require(await session.nextUpdate())
        let change = try #require(update.change)
        #expect(update.text.version == 2)
        #expect(change.oldLines == 1..<4)
        #expect(change.newLines == 1..<4)
        Self.expectApplies(change, from: original, to: text)
        // A line added at the end, and one taken from it: the line before is
        // in the change too, which starts at a line's start.
        let added = try Self.edit(session, text, to: text + "\nzeta")
        let addedChange = try #require(await session.nextUpdate()?.change)
        #expect(addedChange.oldLines == 4..<5 && addedChange.newLines == 4..<6)
        Self.expectApplies(addedChange, from: text, to: added)
        let taken = try Self.edit(session, added, to: "alpha\nbeta!")
        let takenChange = try #require(await session.nextUpdate()?.change)
        #expect(takenChange.oldLines == 1..<6 && takenChange.newLines == 1..<2)
        Self.expectApplies(takenChange, from: added, to: taken)
    }

    /// `change` replaces `old`'s `oldUTF8` with `new`'s `newUTF8`, leaving
    /// the rest, and both start at a line's start.
    static func expectApplies(_ change: TextEditorTextChange, from old: String, to new: String) {
        let (oldBytes, newBytes) = (Array(old.utf8), Array(new.utf8))
        #expect(oldBytes[..<change.oldUTF8.lowerBound] == newBytes[..<change.newUTF8.lowerBound])
        #expect(oldBytes[change.oldUTF8.upperBound...] == newBytes[change.newUTF8.upperBound...])
        #expect(change.oldUTF8.lowerBound == change.newUTF8.lowerBound)
        let oldText = TextEditorText(version: 0, string: old)
        let newText = TextEditorText(version: 1, string: new)
        #expect(oldText.utf8Offset(ofLine: change.oldLines.lowerBound) == change.oldUTF8.lowerBound)
        #expect(newText.utf8Offset(ofLine: change.newLines.lowerBound) == change.newUTF8.lowerBound)
        #expect(oldText.lineCount - change.oldLines.upperBound == newText.lineCount - change.newLines.upperBound)
    }

    @Test("An update's lines are found from the last text's, through the change, as a whole walk finds them")
    @MainActor
    func linesFoundThroughTheChange() async throws {
        // Each edit as lines, in each kind of break: in place, a line put in,
        // lines taken, a break at the end, two edits folded into one update,
        // and nothing (last: a text with no break has no kind of break).
        let edits = [
            [["alpha", "beta!", "gamma"]], [["alpha", "beta!", "new", "gamma"]], [["alpha", "gamma"]],
            [["alpha", "gamma", ""]], [["alpha!", "gamma", ""], ["alpha!", "gamma", "z"]], [[""]],
        ]
        for ending in ["\n", "\r\n", "\r"] {
            var text = ["alpha", "beta", "gamma"].joined(separator: ending)
            let (session, _) = Self.session(text)
            var previous = try #require(await session.nextUpdate()).text
            for (index, steps) in edits.enumerated() {
                for lines in steps { text = try Self.edit(session, text, to: lines.joined(separator: ending)) }
                let update = try #require(await session.nextUpdate())
                let label = "edit \(index), \(ending.debugDescription)"
                #expect(update.text.lineStarts == EditorLayout.lineBreaks(in: text).starts, "\(label)")
                // The short way, not a whole walk, except after a lone CR, which
                // an LF the edit put after it would join.
                let change = try #require(update.change)
                let found = TextEditorText.lineStarts(of: update.text.string.utf8, changing: previous, by: change)
                if ending != "\r" || change.oldUTF8.lowerBound == 0 {
                    #expect(found == update.text.lineStarts, "\(label) walked whole")
                }
                previous = update.text
            }
        }
    }

    // MARK: - Publishing

    @Test("A publish is kept for the window, and asks for a frame only when a line on screen changed")
    func publishAsksForFramesOnlyOnScreen() async throws {
        let (session, frames) = Self.session((0..<100).map { "line \($0)" }.joined(separator: "\n"))
        _ = session.show(lines: 10..<20)
        let update = try #require(await session.nextUpdate())
        #expect(session.window == 0..<30, "a screen either side")
        let word = Self.tokens([(0, .word), (4, .gap), (5, .number)])
        #expect(session.publish(word, forLine: 12, of: update.text.version))
        #expect(frames.asked == 1)
        #expect(session.publish(Self.tokens([(0, .number)]), forLine: 13, of: update.text.version))
        #expect(frames.asked == 1, "one frame asked until the editor draws")
        #expect(session.takeChangedLines() == [12, 13])
        #expect(session.publish(word, forLine: 12, of: update.text.version))
        #expect(frames.asked == 1, "the same tokens: nothing to draw")
        #expect(session.publish(word, forLine: 25, of: update.text.version))
        #expect(frames.asked == 1, "off screen, in the window: kept, no frame")
        #expect(session.keptLine(25) != nil)
        #expect(session.publish(word, forLine: 50, of: update.text.version), "outside the window: taken")
        #expect(session.keptLine(50) == nil, "and kept nowhere")
        #expect(session.publish(Self.tokens([(0, .word)]), forLine: 14, of: update.text.version))
        #expect(frames.asked == 2)
        // The runs: the tokens interned in order, from 1.
        #expect(session.runs(ofLine: 12).map(\.style) == [1, 2, 3])
        #expect(session.token(2) == .gap)
        #expect(session.tokenCount == 3)
        // A scroll drops what leaves the window.
        #expect(session.show(lines: 60..<70).sorted() == [12, 13, 14, 25])
    }

    @Test("A publish for a text the editor no longer has, or a line it lacks, is refused and kept nowhere")
    @MainActor
    func stalePublishIsRefused() async throws {
        let (session, frames) = Self.session("a\nb\nc")
        _ = session.show(lines: 0..<3)
        let first = try #require(await session.nextUpdate())
        #expect(!session.publish(Self.tokens([(0, .word)]), forLine: 3, of: first.text.version), "no line 3")
        #expect(!session.publish([Self.tokens([])], forLines: 0..<2, of: first.text.version), "one tokens a line")
        _ = try Self.edit(session, "a\nb\nc", to: "a\nbb\nc")
        #expect(!session.publish(Self.tokens([(0, .word)]), forLine: 0, of: first.text.version), "stale")
        #expect(session.keptLine(0) == nil)
        #expect(frames.asked == 0)
        let second = try #require(await session.nextUpdate())
        #expect(!session.publish(Self.tokens([(0, .word)]), forLine: 0, of: second.text.version + 1), "a version to come")
        #expect(session.publish(Self.tokens([(0, .word)]), forLine: 0, of: second.text.version))
        #expect(frames.asked == 1)
    }

    @Test("An edit that lands while a highlighter is styling refuses its publish, and the next update holds both")
    @MainActor
    func editMidPublish() async throws {
        let (session, _) = Self.session("x = 1\ny = 2")
        _ = session.show(lines: 0..<2)
        let styler = FakeTreeStyler()
        let first = try #require(await session.nextUpdate())
        styler.step(first, in: session)
        #expect(session.keptLine(1)?.runs.count == 3)
        // The highlighter takes the next text, and the editor edits again
        // before it publishes.
        let typed = try Self.edit(session, "x = 1\ny = 2", to: "x = 1\ny = 23")
        let taken = try #require(await session.nextUpdate())
        _ = try Self.edit(session, typed, to: "x = 1\ny = 234")
        styler.step(taken, in: session)
        #expect(session.keptLine(1)?.isProvisional == true, "the stale publish refused: the carried tokens stay")
        let next = try #require(await session.nextUpdate())
        #expect(next.text.version == taken.text.version + 1)
        #expect(next.change?.oldLines == 1..<2)
        styler.step(next, in: session)
        #expect(session.keptLine(1) == EditorHighlightLine(runs: session.runs(ofLine: 1)))
        #expect(session.runs(ofLine: 1).map(\.utf8Offset) == [0, 1, 4])
    }

    @Test("Offsets that go back or past the line are clamped; a line past the limit is drawn unstyled")
    func offsetsAreClampedAndLongLinesRefused() async throws {
        let (session, _) = Self.session("abcd\n0123456789ab", maximumLineLength: 10)
        _ = session.show(lines: 0..<2)
        let update = try #require(await session.nextUpdate())
        #expect(session.publish(Self.tokens([(2, .word), (1, .number), (100, .gap)]), forLine: 0, of: 0))
        #expect(session.runs(ofLine: 0).map(\.utf8Offset) == [2, 2, 4])
        #expect(session.publish(Self.tokens([(0, .number)]), forLine: 1, of: update.text.version))
        #expect(session.keptLine(1) == nil, "12 bytes, past 10")
    }

    // MARK: - Carrying tokens through edits (B-ATTRED-24, 28)

    @Test("A line edited in place keeps its tokens, shifted past the edit, as provisional; lines below move")
    @MainActor
    func tokensAreCarried() async throws {
        let text = "one\nkey = word\nlast"
        let (session, _) = Self.session(text)
        _ = session.show(lines: 0..<3)
        let update = try #require(await session.nextUpdate())
        session.publish(Self.tokens([(0, .word), (3, .gap), (6, .word)]), forLine: 1, of: update.text.version)
        session.publish(Self.tokens([(0, .number)]), forLine: 2, of: update.text.version)
        // "key" to "keyXY": the gap and the word after move 2 bytes on.
        let typed = try Self.edit(session, text, to: "one\nkeyXY = word\nlast")
        let carried = try #require(session.keptLine(1))
        #expect(carried.isProvisional)
        #expect(carried.runs.map(\.utf8Offset) == [0, 5, 8])
        #expect(session.keptLine(2)?.isProvisional == false, "a line the edit left: kept as published")
        // A line put in above: the lines below move with it.
        _ = session.show(lines: 0..<4)
        _ = try Self.edit(session, typed, to: "zero\none\nkeyXY = word\nlast")
        #expect(session.keptLine(2)?.runs.map(\.utf8Offset) == [0, 5, 8])
        #expect(session.keptLine(3)?.runs.map(\.utf8Offset) == [0])
        #expect(session.keptLine(1) == nil, "\"one\" had none")
        // The text replaced whole: nothing carried.
        _ = session.textChanged(to: "new", lineCount: 1, by: nil)
        #expect(session.keptLine(0) == nil && session.keptLine(2) == nil)
        let whole = try #require(await session.nextUpdate())
        #expect(whole.change == nil)
    }

    @Test("A line shift moves offsets before, inside and after the edit as the design has it")
    func lineShift() {
        let shift = EditorLineShift(from: Array("abcdef".utf8), to: Array("abXYZef".utf8))
        #expect(shift == EditorLineShift(from: Array("abcdef".utf8), to: Array("abXYZef".utf8)))
        #expect((shift.prefix, shift.oldSuffixStart, shift.delta, shift.newLength) == (2, 4, 1, 7))
        let runs = [0, 2, 3, 4, 6].map { EditorHighlightRun(utf8Offset: $0, style: 1) }
        #expect(shift.shifted(runs).map(\.utf8Offset) == [0, 2, 2, 5, 7])
    }

    // MARK: - The end of a session

    @Test("Closed, a session's next update is nil, its publishes refused, and its checkpoint throws")
    func closing() async throws {
        let (session, _) = Self.session("a")
        let waiting = Task { await session.nextUpdate() }
        #expect(await waiting.value != nil)
        let ended = Task { await session.nextUpdate() }
        session.close()
        #expect(await ended.value == nil)
        #expect(!session.publish(Self.tokens([(0, .word)]), forLine: 0, of: 0))
        await #expect(throws: CancellationError.self) { try await session.checkpoint() }
    }

    @Test("Cancelled while it waits, a highlighter's next update is nil")
    func cancellationEndsTheWait() async throws {
        let (session, _) = Self.session("a")
        _ = try #require(await session.nextUpdate())
        let waiting = Task { await session.nextUpdate() }
        waiting.cancel()
        #expect(await waiting.value == nil)
        // And the session still serves a highlighter that asks again.
        _ = session.show(lines: 0..<1)
        #expect(await session.nextUpdate()?.visibleLines == 0..<1)
    }
}
