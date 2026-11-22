//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHighlighterTests.swift
//
//  A highlighter through a TextEditor (lane H6′ of the highlighting design):
//  started with the editor, kept while it is the same one, cancelled when
//  the editor goes or is given another (B-ATTRED-22, 25); its tokens drawn,
//  a frame asked for when a line on screen changed (B-ATTRED-20); told of
//  edits, the app's replacements and scrolls (B-ATTRED-21, 27); a fake tree
//  styler's changed ranges drawn; and a real highlighter's task running
//  beside edits, the test the thread sanitizer runs.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@_spi(TextEditorHighlighting) @testable import TUITextInput
@testable import TUIView

@MainActor
// A highlighter that never answers would otherwise hang the run.
// Very generous, as NamedTaskTests' is: in a full parallel run a @MainActor test queues behind every other
// main-actor test its process has started, and a single hop has been measured at 17 s (AsyncSettling.swift).
// Three minutes failed four of these tests in the batch50 gate (2026-11-20) though each passes alone.
@Suite("Text editor: a highlighter through the editor", .timeLimit(.minutes(45)))
struct TextEditorHighlighterTests {
    typealias Box = TextEditorHighlightLayerTests.Box
    typealias Token = FakeTreeStyler.Token

    nonisolated static let green = Color.rgb(20, 200, 40)
    nonisolated static let grey = Color.rgb(120, 120, 120)

    /// Each token's attributes: words green, comments grey, the rest none.
    static func style(_ token: Token) -> AttributeContainer {
        var container = AttributeContainer()
        switch token {
        case .word: container.foregroundColor = green
        case .comment: container.foregroundColor = grey
        case .number, .gap: break
        }
        return container
    }

    /// An editor of a bound text, drawn in a context whose effects fire, so
    /// its highlighter's task starts; each frame a lifecycle pass, so one
    /// without the editor makes it disappear.
    @MainActor
    final class Rig {
        let text: Box<String>
        let context: RenderContext
        let height: Int
        var view: AnyView

        init<Content: View>(_ text: String, height: Int = 4, _ highlighted: (TextEditor) -> Content) {
            self.text = Box(text)
            self.height = height
            context = makeRenderContext(width: 20, height: height)
            view = AnyView(highlighted(TextEditor(text: self.text.binding)).frame(width: 20, height: height))
        }

        @discardableResult
        func draw(_ shown: Bool = true) -> [[(character: Character, state: SGRState)]] {
            let lifecycle = context.environment.lifecycle!
            lifecycle.beginRenderPass()
            defer { lifecycle.endRenderPass() }
            return renderToBuffer(shown ? view : AnyView(EmptyView()), context: context).lines
                .map { TextEditorHighlightLayerTests.cells($0) }
        }

        var handler: TextEditorHandler {
            context.environment.focusManager!.activeSection!.focusables.compactMap { $0 as? TextEditorHandler }.first!
        }

        /// The count the editor's frame requests write.
        var frameRequests: UInt32 {
            context.stateStorage!.values.lazy.filter { $0.key.propertyIndex == _TextEditorCore.highlightsStateIndex }
                .compactMap { $0.value as? StateBox<UInt32> }.first?.value ?? 0
        }

        /// The ink of `line`'s `column`th cell, as drawn now.
        func ink(line: Int, column: Int) -> SGRState.Colour? {
            draw()[line][column].state.foregroundColour
        }
    }

    static func ink(_ color: Color) -> SGRState.Colour? {
        TextEditorHighlightLayerTests.drawn(ink: color).foregroundColour
    }

    /// Waits until `inbox` has been given `count` sessions.
    static func session(
        _ inbox: SessionInbox, count: Int = 1
    ) async throws -> TextEditorHighlightSession<Token> {
        await settle(until: { inbox.sessions.count >= count })
        return try #require(inbox.sessions.last)
    }

    // MARK: - Started, kept, cancelled

    @Test("Started when the editor appears, kept while the same, cancelled when it goes")
    func lifetime() async throws {
        let inbox = SessionInbox()
        let rig = Rig("hello") { $0.textEditorHighlighter(SteppedHighlighter(inbox: inbox), style: Self.style) }
        rig.draw()
        let session = try await Self.session(inbox)
        // A body made again makes a new value of the same highlighter.
        rig.view = AnyView(
            TextEditor(text: rig.text.binding).textEditorHighlighter(SteppedHighlighter(inbox: inbox), style: Self.style)
                .frame(width: 20, height: 4))
        rig.draw()
        rig.draw()
        #expect(inbox.sessions.count == 1, "B-ATTRED-25: the same one")
        rig.draw(false)
        await settle(until: { inbox.ended == 1 })
        #expect(inbox.ended == 1, "cancelled with the editor")
        // Its session closed: asked without waiting, as a closed session's
        // checkpoint throws and an open one's returns.
        await #expect(throws: CancellationError.self, "and its session closed") { try await session.checkpoint() }
        // Back: a new session.
        rig.draw()
        _ = try await Self.session(inbox, count: 2)
    }

    @Test("An Equatable highlighter unequal to the last starts afresh, the last cancelled")
    func newHighlighterRestarts() async throws {
        let inbox = SessionInbox()
        var id = 1
        let text = Box("hello")
        let context = makeRenderContext(width: 20, height: 3)
        func draw() {
            _ = renderToBuffer(
                TextEditor(text: text.binding).textEditorHighlighter(NumberedHighlighter(id: id, inbox: inbox), style: Self.style)
                    .frame(width: 20, height: 3), context: context)
        }
        draw()
        draw()
        _ = try await Self.session(inbox)
        #expect(inbox.sessions.count == 1, "equal: kept")
        id = 2
        draw()
        _ = try await Self.session(inbox, count: 2)
        await settle(until: { inbox.ended == 1 })
        #expect(inbox.ended == 1)
        #expect(inbox.sessions.count == 2)
    }

    @Test("No highlighter in a snapshot render: its effects do not fire")
    func snapshotStartsNothing() {
        let inbox = SessionInbox()
        let snapshot = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false), keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(), stateStorage: StateStorage())
        let context = RenderContext(availableWidth: 20, availableHeight: 3, tuiContext: snapshot).isolatingRenderCache()
        _ = renderToBuffer(
            TextEditor(text: .constant("x")).textEditorHighlighter(SteppedHighlighter(inbox: inbox), style: Self.style),
            context: context)
        #expect(inbox.sessions.isEmpty)
    }

    // MARK: - Drawing what is published

    @Test("Tokens published are drawn, and a line on screen changed asks the editor for a frame")
    func publishedTokensDraw() async throws {
        let inbox = SessionInbox()
        let rig = Rig("key 12\nnext") { $0.textEditorHighlighter(SteppedHighlighter(inbox: inbox), style: Self.style) }
        rig.draw()
        let session = try await Self.session(inbox)
        let update = try #require(await session.nextUpdate())
        #expect(update.visibleLines == 0..<2)
        // Column 0 is the caret's.
        #expect(rig.ink(line: 0, column: 1) != Self.ink(Self.green), "nothing published yet")
        FakeTreeStyler().step(update, in: session)
        await settle(until: { rig.frameRequests == 1 })
        #expect(rig.frameRequests == 1)
        #expect(rig.ink(line: 0, column: 1) == Self.ink(Self.green))
        #expect(rig.ink(line: 0, column: 4) != Self.ink(Self.green), "a number: unstyled")
    }

    @Test("Typing tells the session the line by whole lines, and draws the line's tokens shifted until republished")
    func typingCarriesTokens() async throws {
        let inbox = SessionInbox()
        let rig = Rig("ab cd\nzz") { $0.textEditorHighlighter(SteppedHighlighter(inbox: inbox), style: Self.style) }
        rig.draw()
        let session = try await Self.session(inbox)
        let styler = FakeTreeStyler()
        styler.step(try #require(await session.nextUpdate()), in: session)
        rig.draw()
        // Type "12 " at the start of line 0: "12 ab cd".
        rig.handler.moveCursor(toLine: 0, column: 0)
        for character in "12 " { _ = rig.handler.handleKeyEvent(KeyEvent(key: .character(character))) }
        #expect(rig.text.value == "12 ab cd\nzz")
        // Drawn with the old tokens moved 3 on: "ab" still green (column 3
        // is the caret's).
        #expect(rig.ink(line: 0, column: 4) == Self.ink(Self.green))
        #expect(rig.ink(line: 0, column: 0) != Self.ink(Self.green), "the inserted text takes the run it is in")
        let update = try #require(await session.nextUpdate())
        #expect(update.change?.oldLines == 0..<1)
        #expect(update.change?.newUTF8 == 0..<9)
        styler.step(update, in: session)
        #expect(rig.ink(line: 0, column: 0) != Self.ink(Self.green))
        #expect(rig.ink(line: 0, column: 4) == Self.ink(Self.green))
        // The app replaces the text: all new.
        rig.text.value = "fresh"
        rig.draw()
        let whole = try #require(await session.nextUpdate())
        #expect(whole.change == nil)
        #expect(whole.text.string == "fresh")
    }

    @Test("A fake tree styler's changed ranges: a comment opened restyles the lines below, and a scroll is an update")
    func treeStylerRestylesBelow() async throws {
        let inbox = SessionInbox()
        let lines = (0..<12).map { "word\($0)" }
        let rig = Rig(lines.joined(separator: "\n")) {
            $0.textEditorHighlighter(SteppedHighlighter(inbox: inbox), style: Self.style)
        }
        rig.draw()
        let session = try await Self.session(inbox)
        let styler = FakeTreeStyler()
        styler.step(try #require(await session.nextUpdate()), in: session)
        #expect(styler.steps.last?.published == Set(0..<8), "the screen and one below")
        await settle(until: { rig.frameRequests == 1 })
        // Drawn, so the next publish may ask for a frame again (B-ATTRED-39).
        rig.draw()
        rig.handler.moveCursor(toLine: 1, column: 0)
        for character in "/*" { _ = rig.handler.handleKeyEvent(KeyEvent(key: .character(character))) }
        styler.step(try #require(await session.nextUpdate()), in: session)
        let step = try #require(styler.steps.last)
        #expect(step.change?.oldLines == 1..<2)
        #expect(step.changed == Set(1..<12), "the tree changed below the edit")
        #expect(step.published == Set(1..<8), "only the window's")
        await settle(until: { rig.frameRequests >= 2 })
        // Column 2 of line 1 is the caret's.
        for line in 1..<4 { #expect(rig.ink(line: line, column: 3) == Self.ink(Self.grey), "line \(line)") }
        // Scrolled to the end: an update with the version unchanged.
        rig.handler.moveCursor(toLine: 11, column: 0)
        rig.draw()
        let scroll = try #require(await session.nextUpdate())
        #expect(scroll.text.version == step.version)
        #expect(scroll.visibleLines == 8..<12)
        styler.step(scroll, in: session)
        #expect(styler.steps.last?.published == Set(8..<12))
        #expect(rig.ink(line: 3, column: 2) == Self.ink(Self.grey), "line 11")
    }

    @Test("Scrolled away and back between two updates, the lines that lost their tokens are the next update's to style")
    func scrollAwayAndBackListsLinesToStyle() async throws {
        // tuitree's SeamTests, "Scrolling away and back drops a line's tokens": the update after had the screen
        // where it was and a change of one line, and said nothing of the lines the scroll had emptied.
        let inbox = SessionInbox()
        let rig = Rig((0..<200).map { "line \($0)" }.joined(separator: "\n")) {
            $0.textEditorHighlighter(SteppedHighlighter(inbox: inbox), style: Self.style)
        }
        rig.draw()
        let session = try await Self.session(inbox)
        let first = try #require(await session.nextUpdate())
        #expect(first.visibleLines == 0..<4 && first.window == 0..<8)
        let styler = FakeTreeStyler()
        styler.step(first, in: session)
        #expect(rig.ink(line: 1, column: 1) == Self.ink(Self.green))
        // Away, back, and a key on the first line: all before the highlighter looks again.
        rig.handler.moveCursor(toLine: 150, column: 0)
        rig.draw()
        rig.handler.moveCursor(toLine: 0, column: 0)
        rig.draw()
        _ = rig.handler.handleKeyEvent(KeyEvent(key: .character("x")))
        #expect(rig.ink(line: 1, column: 1) != Self.ink(Self.green), "line 1 lost its tokens to the scroll")
        let next = try #require(await session.nextUpdate())
        #expect(next.visibleLines == first.visibleLines, "the screen is where it was")
        #expect(next.change?.newLines == 0..<1, "and the change is the one line typed on")
        #expect(next.linesToStyle == [0..<8], "but every line of the window is to style")
        // The changed line and the lines to style, as a tree styler publishes them: the screen styled again.
        styler.step(next, in: session)
        #expect(styler.steps.last?.published == Set(0..<8))
        #expect(rig.ink(line: 1, column: 1) == Self.ink(Self.green))
    }

    @Test("An undo and the app's write, written whole, keep the tokens of the lines they left, and come as changes")
    func wholeWritesKeepTokens() async throws {
        // tuitree's SeamTests, "A text written whole comes with no change, and takes every token with it": the undo
        // drew the pane plain until the highlighter answered, and handed it no change to re-parse incrementally.
        let inbox = SessionInbox()
        let text = (0..<4).map { "line \($0)" }.joined(separator: "\n")
        let undo = UndoManager()
        undo.groupsByEvent = false
        let rig = Rig(text) {
            $0.textEditorHighlighter(SteppedHighlighter(inbox: inbox), style: Self.style).environment(\.undoManager, undo)
        }
        rig.draw()
        let session = try await Self.session(inbox)
        let styler = FakeTreeStyler()
        styler.step(try #require(await session.nextUpdate()), in: session)
        #expect(rig.ink(line: 1, column: 1) == Self.ink(Self.green))
        rig.handler.moveCursor(toLine: 2, column: 0)
        _ = rig.handler.handleKeyEvent(KeyEvent(key: .character("x")))
        rig.draw()
        styler.step(try #require(await session.nextUpdate()), in: session)
        // The editor's own undo, which writes the text whole.
        undo.undo()
        try #require(rig.text.value == text, "undone")
        #expect(rig.ink(line: 1, column: 1) == Self.ink(Self.green), "a line the undo left keeps its tokens")
        #expect(rig.ink(line: 2, column: 1) == Self.ink(Self.green), "and the line it edited carries them")
        let undone = try #require(await session.nextUpdate())
        #expect(undone.change?.oldLines == 2..<3 && undone.change?.newLines == 2..<3)
        #expect(undone.linesToStyle == [2..<3])
        styler.step(undone, in: session)
        // The app's own write, as tuitree prints its tree into the pane.
        rig.text.value = text + "!"
        #expect(rig.ink(line: 1, column: 1) == Self.ink(Self.green))
        #expect(try #require(await session.nextUpdate()).change?.newLines == 3..<4)
    }

    // MARK: - A real highlighter beside edits

    @Test("A highlighter's own task, beside a burst of edits, ends with the last text styled (the sanitizer's run)")
    func realTaskBesideEdits() async throws {
        let styler = FakeTreeStyler()
        let rig = Rig((0..<40).map { "w\($0) 1" }.joined(separator: "\n"), height: 6) {
            $0.textEditorHighlighter(FakeTreeHighlighter(styler: styler), style: Self.style)
        }
        rig.draw()
        for step in 0..<60 {
            rig.handler.moveCursor(toLine: step % 6, column: 0)
            _ = rig.handler.handleKeyEvent(KeyEvent(key: .character(step.isMultiple(of: 7) ? "/" : "x")))
            rig.draw()
            await Task.yield()
        }
        let final = rig.handler.layout().text
        await settle(until: { Self.isStyled(final, by: rig) })
        #expect(Self.isStyled(final, by: rig))
        rig.draw(false)
    }

    /// Whether the lines on screen are drawn with `text`'s tokens, as the
    /// fake tree styler makes them: each row's second cell (the caret's line
    /// left out), the row's line found by its text, every line of the test's
    /// text being unlike the rest.
    static func isStyled(_ text: String, by rig: Rig) -> Bool {
        let layout = EditorLayout(text: text)
        let expected = FakeTreeStyler.lines(of: TextEditorText(version: 0, string: text))
        return rig.draw().allSatisfy { row in
            // The last cell is the scroll bar's.
            let drawn = String(row.dropLast().map(\.character)).trimmingCharacters(in: .whitespaces)
            guard drawn.count > 1, let line = layout.lines.firstIndex(where: { String($0) == drawn }),
                line != rig.handler.cursorLine, let token = expected[line].last(where: { $0.offset <= 1 })?.token
            else { return true }
            let ink = row[1].state.foregroundColour
            switch token {
            case .word: return ink == Self.ink(Self.green)
            case .comment: return ink == Self.ink(Self.grey)
            case .number, .gap: return ink != Self.ink(Self.green) && ink != Self.ink(Self.grey)
            }
        }
    }
}
