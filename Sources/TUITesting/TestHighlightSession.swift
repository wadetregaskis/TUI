//  🖥️ TUI — A Terminal UI framework for Swift
//  TestHighlightSession.swift
//
//  A highlight session a test drives, with no editor and no TestApp
//  (B-ATTRED-60): the test plays the editor (an edit, a write, a scroll),
//  runs a highlighter on the session or plays it too, steps it until it waits
//  for the next update, and reads back what the session holds and every
//  publish it was made, kept or refused. Under the seam's SPI.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
@_spi(TextEditorHighlighting) import TUITextInput

/// TUI-specific. A ``TextEditorHighlightSession`` with no editor, for testing
/// a ``TextEditorHighlighter``: the test makes the edits, the writes and the
/// scrolls an editor would, each told to the session exactly as a
/// `TextEditor` tells it, and reads what the highlighter published.
///
/// ```swift
/// let test = TestHighlightSession<MyToken>(text: source, visibleLines: 0..<40)
/// test.run(MyHighlighter())
/// await test.step()                        // the first update answered
/// #expect(test.tokens(ofLine: 3)?.first?.token == .keyword)
/// test.replace(10..<10, with: "x")         // a key typed at byte 10
/// await test.step()
/// #expect(test.publications.last?.outcome == .kept(0..<120))
/// ```
///
/// A test may instead play the highlighter itself: take ``session``'s
/// ``TextEditorHighlightSession/nextUpdate()`` and publish to it.
@_spi(TextEditorHighlighting)
@MainActor
public final class TestHighlightSession<Token: Hashable & Sendable> {
    /// A publish the highlighter made, and what became of it.
    public struct Publication: Sendable, Equatable {
        /// Tokens for lines, or marks.
        public enum Kind: Sendable, Equatable {
            case tokens(lines: Range<Int>)
            case marks(count: Int)
        }

        public var kind: Kind
        /// The version of the text it was for.
        public var version: Int
        /// What became of it, as the publish returned it: marks are kept
        /// for every line of the text, or refused.
        public var outcome: TextEditorPublishOutcome

        /// A publish of `kind`, for `version`, and what became of it.
        public init(kind: Kind, version: Int, outcome: TextEditorPublishOutcome) {
            self.kind = kind
            self.version = version
            self.outcome = outcome
        }
    }

    private let harness: EditorHighlightHarness<Token>
    /// Every publish, appended on the highlighter's task.
    private final class Log: Sendable {
        let entries = Mutex<[Publication]>([])
    }

    private let log = Log()
    private var task: Task<Void, Never>?

    /// The session a highlighter is given.
    public var session: TextEditorHighlightSession<Token> { harness.session }

    /// The editor's text, as the test's edits and writes have left it.
    public var text: String { harness.text }

    /// How many frames the session has asked the editor for: one for each
    /// publish that changed a line on screen, until ``tookFrame()``.
    public var framesAsked: Int { harness.framesAsked }

    /// Every publish made, in order.
    public var publications: [Publication] { log.entries.withLock { $0 } }

    /// A session over `text`, version 0, with `visibleLines` on screen.
    ///
    /// - Parameters:
    ///   - text: The editor's text.
    ///   - visibleLines: The lines on screen.
    ///   - maximumLineLength: The longest line, in UTF-8 bytes, that is styled.
    public init(text: String, visibleLines: Range<Int>, maximumLineLength: Int = 20_000) {
        harness = EditorHighlightHarness(text: text, visibleLines: visibleLines, maximumLineLength: maximumLineLength)
        let log = log
        harness.session.observePublishes { record in
            let kind: Publication.Kind =
                switch record.lines {
                case .some(let lines): .tokens(lines: lines)
                case .none: .marks(count: record.marks)
                }
            log.entries.withLock { $0.append(Publication(kind: kind, version: record.version, outcome: record.outcome)) }
        }
    }

    /// Runs `highlighter` on the session, off the main actor, as an editor
    /// runs it, until ``close()``.
    ///
    /// It runs beside the test, so between an edit and the next ``step()``
    /// it may or may not have answered the edit yet: read what it published
    /// after a step. A test that needs the state in between (a line
    /// ``isProvisional(line:)`` until published again) plays the highlighter
    /// itself, through ``session``.
    public func run<Highlighter: TextEditorHighlighter>(_ highlighter: Highlighter)
    where Highlighter.Token == Token {
        task?.cancel()
        let session = harness.session
        task = Task.detached { await session.run(highlighter) }
    }

    /// Waits until the running highlighter has taken every update there is
    /// and waits for the next, or has returned. A highlighter that waits on
    /// anything else first is waited for until it asks for its next update.
    public func step() async {
        await harness.session.untilIdle()
    }

    /// Replaces the UTF-8 bytes `utf8` of the text, at character boundaries
    /// and clamped to it, with `replacement`, as an
    /// editor's own edit: a key typed, a paste, a Replace All. Told to the
    /// session as a change by whole lines, each line edited in place keeping
    /// its tokens, shifted, until published again.
    public func replace(_ utf8: Range<Int>, with replacement: String) {
        harness.replace(utf8, with: replacement)
    }

    /// Writes `text` whole, as an app's write to the binding, or an undo or
    /// a redo, does: told to the session as the change from the text before.
    public func write(_ text: String) {
        harness.write(text)
    }

    /// Scrolls so that `lines` are on screen.
    public func show(lines: Range<Int>) {
        harness.show(lines: lines)
    }

    /// The editor drew a frame: the next publish that changes a line on
    /// screen asks for another.
    public func tookFrame() {
        harness.tookFrame()
    }

    /// The tokens the session holds for `line`, each where it starts in the
    /// line, or `nil` where it holds none.
    public func tokens(ofLine line: Int) -> TextEditorTokens<Token>? {
        harness.tokens(ofLine: line)
    }

    /// Whether `line`'s tokens are its old ones, moved with an edit, until
    /// the highlighter publishes it again.
    public func isProvisional(line: Int) -> Bool {
        harness.isProvisional(line: line)
    }

    /// The marks the session holds, in UTF-8 offsets of ``text``.
    public var marks: [TextEditorHighlightMark<Token>] { harness.marks }

    /// Ends the session, as an editor going does: the highlighter's next
    /// update is `nil`, and its task is cancelled.
    public func close() {
        harness.close()
        task?.cancel()
    }
}
