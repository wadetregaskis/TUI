//  🖥️ TUI — A Terminal UI framework for Swift
//  BigTextHighlightedSession.swift
//
//  `bigtext` highlighted: the same 3.2 MB of JSON, typed into by the same
//  keys, with the JSON styler (`TUIJSONStyler`) highlighting it through the
//  seam, as tuitree's tree-sitter adapter will. What a key and a scroll cost
//  the editor when what it draws is highlighted: the session told of each
//  edit, the tokens kept moved with it, the window's runs joined to the
//  text's and drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Dispatch
import Synchronization
import TUI
import TUIJSONStyler
@_spi(TextEditorHighlighting) import TUITextInput

// MARK: - The page

/// ``BigTextPage``, its editor highlighted by `gate`'s highlighter.
struct BigTextHighlightedPage: View {
    let document: BigTextDocument
    let gate: HighlightGate

    var body: some View {
        BigTextPage(document: document)
            .textEditorHighlighter(GatedJSONHighlighter(gate: gate), style: JSONLineStyler.style)
    }
}

// MARK: - The session

/// `bigtext`'s document and keys, highlighted. Between steps, and never
/// during one, the highlighter answers what the last step changed, so every
/// frame draws what a highlighter as quick as tree-sitter's queries would
/// have published by then (a frame behind the edit, the edited line's
/// tokens carried), and the twin and the bench draw the same.
@MainActor
final class BigTextHighlightedSession: StressSession {
    private let document: BigTextDocument
    private var script: BigTextScript
    private let gate = HighlightGate()
    /// Steps at whose start the highlighter did not answer in time.
    private var stalls: [Int] = []

    init(config: StressConfig) {
        document = BigTextDocument(text: BigTextSession.documentText(config))
        script = BigTextScript(seed: config.seed, bytes: document.text.utf8.count)
    }

    var page: BigTextHighlightedPage { BigTextHighlightedPage(document: document, gate: gate) }

    func step(_ index: Int) -> SessionStep {
        // Outside the timed region, as a step's choosing is.
        if !gate.catchUp(to: document.text) { stalls.append(index) }
        return script.step(index, bytes: document.text.utf8.count) { offset in
            let text = document.text
            document.selection = TextSelection(insertionPoint: text.utf8.index(text.startIndex, offsetBy: offset))
        }
    }

    /// `bigtext`'s check, and the highlighter answered every step and has
    /// published.
    func check(_ screen: [String], after index: Int) -> String? {
        if let stall = stalls.first { return "the highlighter did not answer at step \(stall)" }
        if index >= 0, gate.answers == 0 { return "the highlighter has published nothing" }
        return script.check(screen, bytes: document.text.utf8.count)
    }

    static let descriptor = SessionDescriptor(
        id: "bigtext-highlighted",
        summary: "bigtext highlighted: 3.2 MB of JSON styled through the highlight seam, typed into in the middle",
        exercises: "a key and a scroll with highlighting: the session told of the edit, its tokens carried, "
            + "the window's runs joined to the text's and drawn; the styler's own work is off the main actor",
        make: { config, width, height, cold in
            DrivenSession(BigTextHighlightedSession(config: config), width: width, height: height, cold: cold)
        })
}

// MARK: - The highlighter, held to the steps

/// The JSON styler as a highlighter that styles only when its gate lets it:
/// once a step, before the step's keys, so that what a frame draws never
/// depends on when the highlighter's task happened to run.
struct GatedJSONHighlighter: TextEditorHighlighter {
    let gate: HighlightGate

    func highlight(_ session: TextEditorHighlightSession<JSONToken>) async {
        await gate.serve(session)
    }
}

/// Where a session's step lets its highlighter answer, and waits for it.
///
/// The step blocks the main actor on a semaphore while the highlighter, on
/// its own task off the main actor, takes the update and publishes. Nothing
/// it does waits for the main actor: the frame it asks for is a task queued
/// there, which a headless run never reaches, and needs not, every step
/// drawing the editor again.
final class HighlightGate: Sendable {
    private struct State: Sendable {
        var session: TextEditorHighlightSession<JSONToken>?
        /// The text and the lines on screen the highlighter answered last.
        var answered: (text: String, visible: Range<Int>)?
        var answers = 0
    }

    private let state = Mutex(State())
    private let permits: AsyncStream<Void>
    private let permit: AsyncStream<Void>.Continuation
    private let attached = DispatchSemaphore(value: 0)
    private let answeredOne = DispatchSemaphore(value: 0)
    /// How long a step waits for the highlighter before reporting a stall.
    private static let patience = DispatchTimeInterval.seconds(10)

    init() {
        (permits, permit) = AsyncStream.makeStream()
    }

    /// How many updates the highlighter has answered.
    var answers: Int { state.withLock { $0.answers } }

    /// The highlighter's work: an update answered for each permit.
    func serve(_ session: TextEditorHighlightSession<JSONToken>) async {
        state.withLock { $0.session = session }
        attached.signal()
        for await _ in permits {
            if let update = await session.nextUpdate() {
                JSONLineStyler.publish(update, in: session)
                state.withLock {
                    $0.answered = (update.text.string, update.visibleLines)
                    $0.answers += 1
                }
            }
            answeredOne.signal()
        }
    }

    /// Lets the highlighter answer the editor's text, `text`, and the lines
    /// on screen, if it has not, and waits until it has. Returns `false` if
    /// it did not in time.
    func catchUp(to text: String) -> Bool {
        // Started by the editor's first frame, on a task of its own.
        if state.withLock({ $0.session == nil }) {
            guard attached.wait(timeout: .now() + Self.patience) == .success else { return false }
        }
        guard let (session, answered) = state.withLock({ state in state.session.map { ($0, state.answered) } })
        else { return false }
        // Nothing to answer: an update would wait, and so would this.
        if let answered, answered.visible == session.visibleLines, answered.text == text { return true }
        permit.yield()
        return answeredOne.wait(timeout: .now() + Self.patience) == .success
    }
}
