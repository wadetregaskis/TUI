//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+LiveWords.swift
//
//  A live title for a consumer that draws its title as a string: a table
//  column's header. The words a live `Text` or key reads, read again at each
//  frame, with their next change declared as a live `Text` declares it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// Words that read the clock, for a consumer that draws a title as a string
/// rather than as a `Text`: a table column's header (owner ruling B51-LIVE,
/// 2026-10-23: live where it makes sense).
///
/// One reference, so a value that may carry it — a column — grows by a word.
/// The words are the `Text`'s, its Markdown parsed; their styles stay behind,
/// as a header draws its title in its own style.
package struct LiveWords: Hashable, Sendable {
    /// The `Text`'s runs, live ones read at the date they are asked for.
    let box: LiveTextBox

    /// The words at the frame being drawn, having declared their next change
    /// as a live `Text` does (``RenderContext/declareLiveChange(at:readAt:token:measuring:)``):
    /// a measure records the clocked read, a render asks for one wake under
    /// `token`.
    @MainActor package func read(declaringIn context: RenderContext, token: @autoclosure () -> String, measuring: Bool) -> String {
        let date = context.liveFrameDate
        let environment = LiveTextEnvironment(context.environment)
        if let next = box.source.nextChange(after: date, in: environment) {
            context.declareLiveChange(at: next, readAt: date, token: token(), measuring: measuring)
        }
        return box.source.text(at: date, in: environment)
    }
}

extension Text {
    /// This text's words as ``LiveWords`` where any of it reads the clock;
    /// `nil` for a text that does not, which is one check of its runs.
    package var liveWords: LiveWords? {
        guard isLive, let runs else { return nil }
        return LiveWords(box: LiveTextBox(TextRunsSource(runs: runs)))
    }
}

extension LocalizedStringKey {
    /// This key's words as ``LiveWords`` where it has a live value
    /// (`\(date, style:)`, `\(timerInterval:)`, a live `Text`); `nil`
    /// otherwise, at the cost of one check of its live arguments.
    @MainActor package var liveWords: LiveWords? {
        liveArguments.isEmpty ? nil : Text(self).liveWords
    }
}
