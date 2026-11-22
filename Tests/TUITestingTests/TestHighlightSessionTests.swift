//  🖥️ TUI — A Terminal UI framework for Swift
//  TestHighlightSessionTests.swift
//
//  A highlighter tested as an adapter outside TUI tests one (B-ATTRED-60):
//  through `@_spi(TextEditorHighlighting)` imports alone, with no `@testable`
//  and no editor, on TUITesting's `TestHighlightSession`: its edits, writes
//  and scrolls, a highlighter run and stepped, and what it published read
//  back; and `TextEditorText` and `TextEditorTokens`, made and read.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
@_spi(TextEditorHighlighting) import TUITesting
@_spi(TextEditorHighlighting) import TUITextInput

/// Styles each line's first word as a `.keyword` and the rest as `.plain`,
/// publishing only the lines the session asks for, as a stateless styler
/// should (B-ATTRED-57).
private struct FirstWord: TextEditorHighlighter {
    enum Token: Hashable, Sendable { case keyword, plain }

    static func tokens(of line: Substring.UTF8View) -> TextEditorTokens<Token> {
        var tokens = TextEditorTokens<Token>()
        tokens.append(.keyword, at: 0)
        if let space = line.firstIndex(of: UInt8(ascii: " ")) {
            tokens.append(.plain, at: line.distance(from: line.startIndex, to: space))
        }
        return tokens
    }

    func highlight(_ session: TextEditorHighlightSession<Token>) async {
        while let update = await session.nextUpdate() {
            for lines in update.linesToStyle {
                session.publish(lines.map { Self.tokens(of: update.text.line($0)) }, forLines: lines, of: update.text.version)
            }
        }
    }
}

@MainActor
@Suite("A highlight session a test drives", .timeLimit(.minutes(45)))
struct TestHighlightSessionTests {
    fileprivate typealias Token = FirstWord.Token

    @Test("A highlighter run and stepped publishes what the session asks for, and its tokens read back")
    func runAndStep() async {
        let test = TestHighlightSession<Token>(text: "func body\nlet value\nend", visibleLines: 0..<3)
        test.run(FirstWord())
        await test.step()
        #expect(test.tokens(ofLine: 1).map { Array($0.map(\.utf8Offset)) } == [0, 3])
        #expect(test.tokens(ofLine: 1).map { Array($0.map(\.token)) } == [.keyword, .plain])
        #expect(test.publications == [.init(kind: .tokens(lines: 0..<3), version: 0, outcome: .kept(0..<3))])
        // A key typed on the first line: its tokens carried until the highlighter answers.
        test.replace(4..<4, with: "x")
        #expect(test.text == "funcx body\nlet value\nend")
        #expect(test.isProvisional(line: 0))
        await test.step()
        #expect(!test.isProvisional(line: 0))
        #expect(test.publications.last == .init(kind: .tokens(lines: 0..<1), version: 1, outcome: .kept(0..<1)))
        // Written whole, the lines it left keep theirs: only the line it changed is published.
        test.write("funcx body\nlet value\nfinish")
        await test.step()
        #expect(test.publications.last?.kind == .tokens(lines: 2..<3))
        test.close()
    }

    @Test("A test can play the highlighter itself: a stale publish is refused, and says so")
    func playTheHighlighter() async throws {
        let test = TestHighlightSession<Token>(text: "a b\nc", visibleLines: 0..<2)
        let update = try #require(await test.session.nextUpdate())
        #expect(update.window == 0..<2 && update.linesToStyle == [0..<2])
        test.replace(0..<1, with: "z")
        let tokens = FirstWord.tokens(of: update.text.line(0))
        #expect(test.session.publish(tokens, forLine: 0, of: update.text.version) == .refused)
        #expect(test.publications.last?.outcome == .refused)
        #expect(test.tokens(ofLine: 0) == nil, "never published")
        // Marks, through the session, carried by an edit.
        let next = try #require(await test.session.nextUpdate())
        #expect(test.session.publish(marks: [TextEditorHighlightMark(2..<3, token: .plain)], of: next.text.version))
        test.replace(0..<0, with: "!")
        #expect(test.marks == [TextEditorHighlightMark(3..<4, token: .plain)])
        #expect(test.publications.last?.kind == .marks(count: 1))
    }

    @Test("A change that reaches the text's end ends mid-line, its end point found from the text as documented")
    func changeAtTheEnd() async throws {
        // tuitree's SeamTests, "A change that reaches the text's end ends mid-line": `TextEditorTextChange`'s
        // comment put tree-sitter's end points at column 0 of a line after the change, which there is not.
        let test = TestHighlightSession<Token>(text: "a\nb", visibleLines: 0..<2)
        let old = try #require(await test.session.nextUpdate()).text
        test.replace(3..<3, with: "c")
        let update = try #require(await test.session.nextUpdate())
        let change = try #require(update.change)
        #expect(change.oldLines == 1..<2 && change.oldUTF8 == 2..<3 && change.newUTF8 == 2..<4)
        #expect(update.text.lineCount == 2, "no line 2 for column 0 of `oldLines.upperBound` to be")
        // The old end point: row 1, column 1.
        let row = old.line(containingUTF8Offset: change.oldUTF8.upperBound)
        #expect(row == 1 && change.oldUTF8.upperBound - old.utf8Offset(ofLine: row) == 1)
    }

    @Test("A highlighter asks whether its text is still the editor's, without publishing anything")
    func isCurrent() async throws {
        // tuitree's SeamTests, "A publish of no lines says whether a version is still the editor's": the only way to
        // ask, which looked like an accident.
        let test = TestHighlightSession<Token>(text: "a\nb", visibleLines: 0..<2)
        let update = try #require(await test.session.nextUpdate())
        #expect(test.session.isCurrent(update.text.version))
        test.replace(0..<0, with: "x")
        #expect(!test.session.isCurrent(update.text.version), "the editor moved on")
        #expect(test.session.isCurrent(update.text.version + 1))
        #expect(test.publications.isEmpty, "asked, not published")
        test.close()
        #expect(!test.session.isCurrent(update.text.version + 1), "the editor went")
    }

    @Test("A publish refused for a stale text has its lines listed again, where the edits since put them")
    func refusedLinesListedAgain() async throws {
        // tuitree's SeamTests, "A refused publish's lines aren't listed again": the lines a refused parse changed
        // held the tokens published before, so no update named them, and the adapter published its whole window.
        let test = TestHighlightSession<Token>(text: "a 0\nb 1\nc 2\nd 3", visibleLines: 0..<4)
        let publish = { (update: TextEditorHighlightUpdate, lines: Range<Int>) in
            test.session.publish(lines.map { FirstWord.tokens(of: update.text.line($0)) }, forLines: lines, of: update.text.version)
        }
        let first = try #require(await test.session.nextUpdate())
        #expect(publish(first, 0..<4) == .kept(0..<4))
        test.replace(0..<0, with: "x")  // line 0
        let typed = try #require(await test.session.nextUpdate())
        #expect(typed.linesToStyle == [0..<1])
        test.replace(13..<13, with: "y")  // line 3, while the highlighter works on line 0's text
        #expect(publish(typed, 1..<2) == .refused)
        #expect(test.isProvisional(line: 1), "its tokens are the ones the refused publish replaced")
        let next = try #require(await test.session.nextUpdate())
        #expect(next.linesToStyle == [0..<2, 3..<4], "lines 0 and 3, edited, and line 1, whose publish was refused")
        #expect(publish(next, 0..<4) == .kept(0..<4))
        // Moved by the edits since: line 2 of the refused publish's text is line 3 once a line is put in above it.
        test.replace(0..<0, with: "new\n")
        #expect(publish(next, 2..<3) == .refused)
        let moved = try #require(await test.session.nextUpdate())
        #expect(moved.linesToStyle == [0..<1, 3..<4], "the line put in, and line 2 moved to 3")
        #expect(publish(moved, 0..<5) == .kept(0..<5))
        // For a text older than the last update taken, the session can't place them: the whole window.
        let older = moved
        test.replace(0..<0, with: "z")
        let newer = try #require(await test.session.nextUpdate())
        #expect(publish(newer, 0..<1) == .kept(0..<1))
        #expect(publish(older, 4..<5) == .refused)
        test.show(lines: 1..<5)
        #expect(try #require(await test.session.nextUpdate()).linesToStyle == [0..<5])
    }

    @Test("Past 64 edits between two updates, a refused publish's lines are placed among all the lines they changed")
    func refusedLinesPastManyEdits() async throws {
        let test = TestHighlightSession<Token>(text: "a\nb\nc\nd\ne\nf", visibleLines: 0..<6)
        let first = try #require(await test.session.nextUpdate())
        test.session.publish((0..<6).map { FirstWord.tokens(of: first.text.line($0)) }, forLines: 0..<6, of: 0)
        // One edit on line 4, then 70 on line 0: lines 1 to 3 untouched, but between them.
        test.replace(8..<8, with: "y")
        for _ in 0..<70 { test.replace(0..<0, with: "x") }
        #expect(test.session.publish([FirstWord.tokens(of: first.text.line(5))], forLines: 5..<6, of: 0) == .refused)
        #expect(test.isProvisional(line: 5) && !test.isProvisional(line: 2), "line 5 is after every edit")
        #expect(test.session.publish([FirstWord.tokens(of: first.text.line(2))], forLines: 2..<3, of: 0) == .refused)
        let next = try #require(await test.session.nextUpdate())
        #expect(next.linesToStyle == [0..<6], "line 2 is somewhere in lines 0 to 4, and line 5 is line 5")
    }

    @Test("A text and tokens a test makes: lines found as the editor finds them, tokens read in order")
    func textAndTokens() {
        let text = TextEditorText("one\r\ntwo\rthree", version: 7)
        #expect(text.version == 7 && text.lineCount == 3)
        #expect(String(text.line(1)) == "two")
        #expect(text.line(containingUTF8Offset: 9) == 2)
        var tokens = TextEditorTokens<Token>()
        tokens.append(.keyword, at: 0)
        tokens.append(.plain, at: 3)
        #expect(tokens.map(\.utf8Offset) == [0, 3])
        #expect(tokens.last?.token == .plain)
    }
}
