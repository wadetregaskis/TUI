//  🖥️ TUI — A Terminal UI framework for Swift
//  ActivationHold.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// Keeps the input behind a control's action unread until a frame has drawn the
/// action.
///
/// The run loop reads every input event waiting before it draws, and a state
/// change takes effect in the next frame. So an action that writes
/// `.disabled(isSaving)` left its button enabled for the rest of the batch, and a
/// second press read right behind the first ran the action again. Keystrokes
/// bunch like that over ssh, during a slow frame, and when a key repeats faster
/// than the frame rate. SwiftUI applies the write first, for a click, Return,
/// Space, a shortcut, a tap, a toggle, a link and `onSubmit`, and for a write made
/// first thing in a `Task` (measured on macOS 15.8:
/// `Tools/SwiftUIProbes/Disabled between queued events`), so a program written
/// for it relies on that.
///
/// So after an action the loop stops reading (`drainTerminalEvents`), gives a
/// `Task` the action started its first slice, draws, and carries on from the next
/// event. Nothing is dropped, and nothing but an action stops the reading:
/// typing, arrow keys, scrolling, a drag and a paste stay one batch and one frame
/// (``AppState/noteControlActivated()`` says what notes one).
///
/// ## The frame-rate cap
///
/// The frame waits for the cap like any other: the app chose that rate, perhaps
/// to spare a slow link, and a burst of presses is no reason to send it frames
/// faster. The wait is at most one interval, and only what is behind an action
/// pays it. A press's own frame waits for the cap today anyway.
///
/// ## A held key
///
/// A press on a button still enabled afterwards costs a frame now, and a key held
/// down on one repeats about thirty times a second. On a frame slower than that
/// the presses arrive faster than they are handled. With the limit below lifted, a
/// hold of three seconds on frames of 100 ms was still acting four seconds after
/// the release, each press its own frame, with 35 of its 91 presses to come
/// (measured). A person takes that for a hung app, and nothing in a legacy terminal
/// encoding tells a repeat from a press, so none can be dropped.
///
/// Hence the limit. Once the loop has been behind for ``backlogLimitNanos``,
/// that is, has not once read everything waiting, an action stops nothing, and the
/// backlog goes through as a batch did until the loop has caught up. Every press
/// still runs, in order, and the action stops within a frame or so of the limit
/// after the release. What is given up is narrow: under that backlog, a press may
/// reach a control that a press before it, not the first, was about to disable.
/// The first action's own frame is always drawn, so `.disabled(isSaving)` set by
/// the first press holds however slow the frames are; and a key held on a button
/// that disables itself runs nothing further, so it builds no backlog at all.
///
/// Time is passed in, never read, as ``FramePacer``'s is, and the clock is read
/// only when an action has run: a frame with no action costs a flag test.
struct ActivationHold {
    /// How long the loop may stay behind, stopping for a frame after every action,
    /// before it lets the backlog through. Long enough for a few frames, short
    /// enough that a release is seen to take effect at once, or nearly.
    static let backlogLimitNanos: UInt64 = 250_000_000

    /// Whether the reading has stopped, and waits for a frame.
    private(set) var isHolding = false

    /// When the run of actions under way began: `nil` once the reading has found
    /// nothing more waiting.
    private var behindSinceNanos: UInt64?

    /// An action has run, and it is `now`: whether the reading stops for a frame.
    mutating func actionRan(atNanos now: UInt64) -> Bool {
        let since = behindSinceNanos ?? now
        behindSinceNanos = since
        guard now &- since <= Self.backlogLimitNanos else { return false }
        isHolding = true
        return true
    }

    /// The reading found nothing more waiting: the loop is not behind.
    mutating func readEverything() {
        behindSinceNanos = nil
    }

    /// A frame has been drawn, which is what a hold waits for.
    ///
    /// - Returns: Whether the reading was holding for it, so what is behind it
    ///   goes next, with no wait.
    @discardableResult
    mutating func frameDrawn() -> Bool {
        defer { isHolding = false }
        return isHolding
    }
}
