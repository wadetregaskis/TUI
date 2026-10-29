//  🖥️ TUI — A Terminal UI framework for Swift
//  PictureSettle.swift
//
//  When a terminal-graphics picture's box has held still long enough to be
//  sent at its exact size: the owner's ruling of 2026-10-28, that a picture
//  at rest is drawn from pixels sent for its box, not ones the terminal
//  scales (measured softer in Ghostty).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

/// A picture's box, and the frame clock's instant it was first drawn at that
/// size — kept per view (`_ImageCore.settleStateIndex`).
struct PictureSettle: Equatable {
    var width: Int
    var height: Int
    var since: Int64

    /// How long a box holds still before its picture is sent at its exact
    /// size: a quarter of a second, fifteen frames at 60 Hz — longer than the
    /// gap between the frames of any animation, shorter than a person waits.
    static let delayNanos: Int64 = 250_000_000

    /// Whether the picture drawn at `context`'s identity has held `box` for
    /// ``delayNanos``. Notes a new box when it changes (a write only then), and
    /// until the box has settled asks for a frame when it will have, so a
    /// picture at rest is sent again without anything else changing.
    @MainActor
    static func isSettled(box: (width: Int, height: Int), context: RenderContext, token: String) -> Bool {
        guard let storage = context.stateStorage else { return true }
        let now = context.environment.frameNowNanos
        let kept: StateBox<Self> = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: _ImageCore.settleStateIndex),
            default: Self(width: box.width, height: box.height, since: now))
        if kept.value.width != box.width || kept.value.height != box.height {
            kept.value = Self(width: box.width, height: box.height, since: now)
        }
        let due = kept.value.since &+ delayNanos
        guard now < due else { return true }
        context.requestWake(token: "picture-settle-" + token, atNanos: due)
        return false
    }
}
