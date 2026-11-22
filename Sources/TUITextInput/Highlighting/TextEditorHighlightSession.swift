//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHighlightSession.swift
//
//  A highlighter's session with its editor, and the store between them (the
//  highlighting design's B-ATTRED-20 to 22, 24, 27 to 30, lane H6′): the
//  latest text and the change not yet taken, the lines on screen, and the
//  tokens published for those and a screen either side, under one lock. The
//  highlighter's half is here; the editor's (edits, the viewport, what a
//  frame reads) is in `TextEditorHighlightSession+Editor.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import TUIFoundation

/// TUI-specific. A ``TextEditorHighlighter``'s link to the editor it styles:
/// where it takes the editor's text from, and where it publishes tokens.
///
/// The editor never waits on it. A frame reads what was published under a
/// lock and runs none of the highlighter's code (B-ATTRED-20). A publish is
/// checked where it is made, on the highlighter's task: one for a text that
/// is no longer the editor's, or a line it does not have, is refused, and
/// offsets that go backwards or past the line are clamped. Tokens are kept
/// only for the lines on screen and a screen either side, however many are
/// published, and the editor draws again only when a line on screen changed.
/// Each update says which of those lines hold no tokens of its text
/// (``TextEditorHighlightUpdate/linesToStyle``).
///
/// Made by the editor, one for each highlighter it starts: a highlighter
/// cannot make one.
@_spi(TextEditorHighlighting)
public final class TextEditorHighlightSession<Token: Hashable & Sendable>: Sendable {
    /// What the editor and the highlighter share.
    let state: Mutex<EditorHighlightState>
    /// Each token's style index, from 1; apart from ``state``, so that
    /// interning a publish's tokens never holds the lock a frame reads under.
    let interned = Mutex(EditorHighlightTokens<Token>())
    /// Asks the editor for a frame: a line on screen changed its tokens.
    let requestFrame: @Sendable () -> Void
    /// Told of each publish and what became of it: a test's (B-ATTRED-60).
    let publishObserver = Mutex<(@Sendable (EditorHighlightPublishRecord) -> Void)?>(nil)

    /// Lines longer than this many UTF-8 bytes are drawn unstyled, and their
    /// tokens refused (B-ATTRED-15, 30): a minified file's one line would be
    /// hundreds of thousands of tokens.
    public let maximumLineLength: Int

    /// A session over `text`, version 0, which its first update gives whole.
    init(
        text: String, lineCount: Int, maximumLineLength: Int = 20_000,
        requestFrame: @escaping @Sendable () -> Void
    ) {
        state = Mutex(EditorHighlightState(string: text, lineCount: lineCount, utf8Count: text.utf8.count))
        self.maximumLineLength = maximumLineLength
        self.requestFrame = requestFrame
    }

    /// The lines on screen: a hint of what to style first.
    public var visibleLines: Range<Int> { state.withLock { $0.visible } }

    /// The next thing to style: the latest text, every edit since the text
    /// taken last as one change, the lines on screen, the window tokens are
    /// kept for, and the lines of it that hold none of this text. Returns at
    /// once when the text changed or the lines on screen moved since the last
    /// update, and otherwise waits until one does. `nil` once the editor has
    /// gone, or the task is cancelled.
    public func nextUpdate() async -> TextEditorHighlightUpdate? {
        while !Task.isCancelled {
            switch state.withLock({ $0.takeUpdate() }) {
            case .closed: return nil
            case .update(let taken):
                // The lines found here, on the highlighter's task, never on
                // the main actor.
                let text = taken.madeText()
                state.withLock { $0.noteTaken(text) }
                return TextEditorHighlightUpdate(
                    text: text, change: taken.change, visibleLines: taken.visible, window: taken.window,
                    linesToStyle: taken.linesToStyle)
            case .wait: await waitForChange()
            }
        }
        return nil
    }

    /// Waits until the editor rings: an edit, a scroll, or its going. A
    /// cancellation rings too.
    private func waitForChange() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
                let (resume, idle) = state.withLock { state -> (Bool, [CheckedContinuation<Void, Never>]) in
                    // Rung since the update was looked for, or never to ring.
                    guard !state.hasUpdate, !state.isClosed, !Task.isCancelled else { return (true, []) }
                    state.waiter?.resume()
                    state.waiter = waiter
                    // Waiting with nothing to take: a test's step is done.
                    return (false, state.takeIdleWaiters())
                }
                if resume { waiter.resume() }
                for stepped in idle { stepped.resume() }
            }
        } onCancel: {
            state.withLock { $0.takeWaiter() }?.resume()
        }
    }

    /// Publishes `tokens` for `line` of the text of `version`. Returns what
    /// became of them: refused for a text that is no longer the editor's, or
    /// a line it does not have, and then kept nowhere; else kept, for the
    /// line if it is in the window (``TextEditorHighlightUpdate/window``) and
    /// for no line if it is not. A line longer than ``maximumLineLength`` is
    /// kept as drawn unstyled, whatever its tokens.
    @discardableResult
    public func publish(_ tokens: TextEditorTokens<Token>, forLine line: Int, of version: Int) -> TextEditorPublishOutcome {
        let lines = line..<(line + 1)
        return observed(keepPublished(CollectionOfOne(tokens), forLines: lines, of: version), lines: lines, of: version)
    }

    /// Publishes each of `tokens` for the line of `lines` at its place, under
    /// one lock (B-ATTRED-29): as ``publish(_:forLine:of:)`` for each, and
    /// all refused if one line is out of the text or `tokens` is not one a
    /// line. Kept for the lines of `lines` in the window.
    @discardableResult
    public func publish(
        _ tokens: [TextEditorTokens<Token>], forLines lines: Range<Int>, of version: Int
    ) -> TextEditorPublishOutcome {
        observed(keepPublished(tokens, forLines: lines, of: version), lines: lines, of: version)
    }

    /// Whether the text of `version` is still the editor's: what a publish
    /// for it is checked against, so `false` means the next update has a
    /// newer text, or the editor has gone. A long parse can ask it between
    /// slices and leave a text the editor has moved on from (B-ATTRED-61).
    public func isCurrent(_ version: Int) -> Bool {
        state.withLock { !$0.isClosed && $0.version == version }
    }

    /// Ends a slice of work: throws if the task is cancelled or the editor
    /// has gone, and otherwise lets other work run. A highlighter on a single
    /// thread (WebAssembly) holds it until it reaches this.
    public func checkpoint() async throws {
        if Task.isCancelled || state.withLock({ $0.isClosed }) { throw CancellationError() }
        await Task.yield()
    }

    /// Runs `highlighter` on this session, off the main actor, and closes
    /// the session when it returns (B-ATTRED-22).
    @concurrent
    package func run<Highlighter: TextEditorHighlighter>(_ highlighter: Highlighter) async
    where Highlighter.Token == Token {
        await highlighter.highlight(self)
        close()
    }
}

// MARK: - Publishing

extension TextEditorHighlightSession {
    /// ``publish(_:forLines:of:)``'s work: the text checked under the lock,
    /// the runs of the lines in the window made outside it, and written under
    /// it again if the text is still the one they were made for, so a frame
    /// waits only for the copy.
    private func keepPublished(
        _ tokens: some Collection<TextEditorTokens<Token>>, forLines lines: Range<Int>, of version: Int
    ) -> TextEditorPublishOutcome {
        guard tokens.count == lines.count, lines.lowerBound >= 0 else { return .refused }
        guard let publishable = state.withLock({ $0.publishable(version: version) }),
            lines.upperBound <= publishable.text.lineCount
        else { return .refused }
        let (text, window) = publishable
        let inWindow = lines.clamped(to: window)
        var made: [(line: Int, runs: [EditorHighlightRun])] = []
        made.reserveCapacity(inWindow.count)
        for (line, lineTokens) in zip(lines, tokens) where inWindow.contains(line) {
            let length = text.utf8End(ofLine: line) - text.utf8Offset(ofLine: line)
            // Past the limit: kept as drawn unstyled, so it is a line styled.
            made.append((line, length > maximumLineLength ? [] : runs(lineTokens, length: length)))
        }
        let outcome = state.withLock { $0.keep(made, madeFor: inWindow, of: lines, ofVersion: version) }
        switch outcome {
        case .refused: return .refused
        case .kept(let kept, let askForFrame):
            if askForFrame { requestFrame() }
            return .kept(kept)
        }
    }

    /// `tokens` as runs of a line `length` bytes long, their offsets clamped
    /// to it and never going back, and each token interned.
    private func runs(_ tokens: TextEditorTokens<Token>, length: Int) -> [EditorHighlightRun] {
        guard !tokens.isEmpty else { return [] }
        let styles = interned.withLock { $0.indices(of: tokens.tokens) }
        var runs: [EditorHighlightRun] = []
        runs.reserveCapacity(tokens.count)
        var floor = 0
        for (offset, style) in zip(tokens.offsets, styles) {
            floor = min(max(floor, offset), length)
            runs.append(EditorHighlightRun(utf8Offset: floor, style: style))
        }
        return runs
    }

    /// The token style index `index` names, or `nil` for none.
    func token(_ index: UInt16) -> Token? { interned.withLock { $0.token(index) } }

    /// How many tokens have been interned: their style indices are 1 to this.
    var tokenCount: Int { interned.withLock { $0.tokens.count } }
}

/// The distinct tokens a session has been given, each with its style index:
/// from 1, in the order first given, 0 being "none" (B-ATTRED-10, 33). Past
/// 65,535 a token is drawn as none, as ``EditorHighlightStyles`` draws one.
struct EditorHighlightTokens<Token: Hashable & Sendable>: Sendable {
    private var indices: [Token: UInt16] = [:]
    private(set) var tokens: [Token] = []

    /// Each of `tokens`' style index, interning those not seen before.
    mutating func indices(of tokens: [Token]) -> [UInt16] {
        tokens.map { token in
            if let index = indices[token] { return index }
            guard self.tokens.count < Int(UInt16.max) else { return EditorHighlightStyles.none }
            self.tokens.append(token)
            let index = UInt16(self.tokens.count)
            indices[token] = index
            return index
        }
    }

    /// The token of style index `index`, or `nil` for none.
    func token(_ index: UInt16) -> Token? {
        index > 0 && Int(index) <= tokens.count ? tokens[Int(index) - 1] : nil
    }
}
