//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHighlightSession+Testing.swift
//
//  What a test that drives a highlight session needs of it (B-ATTRED-60):
//  to be told of each publish and what became of it, and to wait until the
//  highlighter has taken every update and waits for the next. `package`, for
//  TUITesting's `TestHighlightSession`; an editor uses neither.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import TUIFoundation

/// A publish a session was made, and what became of it.
package struct EditorHighlightPublishRecord: Sendable {
    /// The lines tokens were published for, or `nil` for marks.
    package var lines: Range<Int>?
    /// How many marks were published.
    package var marks: Int
    /// The version of the text they were for.
    package var version: Int
    package var outcome: TextEditorPublishOutcome
}

extension TextEditorHighlightSession {
    /// Calls `observer` with each publish made from now on, on the
    /// publisher's task, after it is kept or refused.
    package func observePublishes(_ observer: @escaping @Sendable (EditorHighlightPublishRecord) -> Void) {
        publishObserver.withLock { $0 = observer }
    }

    /// `outcome`, told to the observer, if there is one.
    func observed(_ outcome: TextEditorPublishOutcome, lines: Range<Int>?, marks: Int = 0, of version: Int)
        -> TextEditorPublishOutcome
    {
        if let observer = publishObserver.withLock({ $0 }) {
            observer(EditorHighlightPublishRecord(lines: lines, marks: marks, version: version, outcome: outcome))
        }
        return outcome
    }

    /// Returns once the highlighter waits in ``nextUpdate()`` with no update
    /// to take, or the session has closed (its highlighter returned, or the
    /// editor went). A highlighter that waits on anything else is waited for
    /// until it asks for its next update.
    package func untilIdle() async {
        await withCheckedContinuation { (stepped: CheckedContinuation<Void, Never>) in
            let now = state.withLock { state -> Bool in
                if state.isClosed || (state.waiter != nil && !state.hasUpdate) { return true }
                state.idleWaiters.append(stepped)
                return false
            }
            if now { stepped.resume() }
        }
    }
}

extension EditorHighlightState {
    /// The steps waiting for the highlighter to wait, no longer waiting.
    mutating func takeIdleWaiters() -> [CheckedContinuation<Void, Never>] {
        defer { idleWaiters = [] }
        return idleWaiters
    }
}
