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
    /// taken last as one change, and the lines on screen. Returns at once
    /// when the text changed or the lines on screen moved since the last
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
                return TextEditorHighlightUpdate(text: text, change: taken.change, visibleLines: taken.visible)
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
                let resume = state.withLock { state -> Bool in
                    // Rung since the update was looked for, or never to ring.
                    guard !state.hasUpdate, !state.isClosed, !Task.isCancelled else { return true }
                    state.waiter?.resume()
                    state.waiter = waiter
                    return false
                }
                if resume { waiter.resume() }
            }
        } onCancel: {
            state.withLock { $0.takeWaiter() }?.resume()
        }
    }

    /// Publishes `tokens` for `line` of the text of `version`. Returns
    /// whether it was taken: `false` for a text that is no longer the
    /// editor's, or a line it does not have, and then kept nowhere. A line
    /// off screen by more than a screen, or longer than
    /// ``maximumLineLength``, is taken and kept nowhere.
    @discardableResult
    public func publish(_ tokens: TextEditorTokens<Token>, forLine line: Int, of version: Int) -> Bool {
        keepPublished(CollectionOfOne(tokens), forLines: line..<(line + 1), of: version)
    }

    /// Publishes each of `tokens` for the line of `lines` at its place, under
    /// one lock (B-ATTRED-29): as ``publish(_:forLine:of:)`` for each, and
    /// all refused if one line is out of the text or `tokens` is not one a
    /// line.
    @discardableResult
    public func publish(_ tokens: [TextEditorTokens<Token>], forLines lines: Range<Int>, of version: Int) -> Bool {
        keepPublished(tokens, forLines: lines, of: version)
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
    func run<Highlighter: TextEditorHighlighter>(_ highlighter: Highlighter) async
    where Highlighter.Token == Token {
        await highlighter.highlight(self)
        close()
    }
}

// MARK: - Publishing

extension TextEditorHighlightSession {
    /// ``publish(_:forLines:of:)``'s work: the text checked under the lock,
    /// the runs made outside it, and written under it again if the text is
    /// still the one they were made for, so a frame waits only for the copy.
    private func keepPublished(
        _ tokens: some Collection<TextEditorTokens<Token>>, forLines lines: Range<Int>, of version: Int
    ) -> Bool {
        guard tokens.count == lines.count, lines.lowerBound >= 0 else { return false }
        guard let publishable = state.withLock({ $0.publishable(version: version) }),
            lines.upperBound <= publishable.text.lineCount
        else { return false }
        let (text, window) = publishable
        var made: [(line: Int, runs: [EditorHighlightRun]?)] = []
        for (line, lineTokens) in zip(lines, tokens) where window.contains(line) {
            let length = text.utf8End(ofLine: line) - text.utf8Offset(ofLine: line)
            made.append((line, length > maximumLineLength ? nil : runs(lineTokens, length: length)))
        }
        let outcome = state.withLock { $0.keep(made, ofVersion: version) }
        if outcome == .askForFrame { requestFrame() }
        return outcome != .refused
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
