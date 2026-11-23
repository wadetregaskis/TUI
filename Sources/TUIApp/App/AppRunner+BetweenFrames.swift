//  🖥️ TUI — A Terminal UI framework for Swift
//  AppRunner+BetweenFrames.swift
//
//  What the run loop does between frames, and what the exit writes on its way out.
//  Split from `App.swift`, which had reached the file-length limit, unchanged.
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

// MARK: - Between frames, and the exit's farewell

extension AppRunner {
    /// What the loop does at `now` once any frame due is drawn, and how long it
    /// may then wait: `nil` to block until woken.
    ///
    /// First the progress bar, sent again where it has gone unsent long enough
    /// for a terminal to drop it (`RenderLoop.keepHostStateAlive(atNanos:)`): a
    /// write between frames, which draws nothing, so a still screen with a bar
    /// up renders no frame for it. Then the wait until the next render is due
    /// (cap and/or animation folded into one instant). While the input parser
    /// holds something that resolves on a timeout — a lone ESC being
    /// disambiguated from a sequence, or a split sequence awaiting its tail —
    /// the wait is shortened to a poll, so the partial resolves on a bounded
    /// wall-clock deadline (a prompt Escape) instead of waiting for unrelated
    /// input or an animation tick. The progress bar's next send shortens it
    /// too, and owes no frame.
    ///
    /// Internal rather than `fileprivate` only so a test can name it, for the
    /// reason `foldPendingWork` gives: its one caller is the `while isRunning`
    /// loop, which nothing a unit test can drive reaches.
    func betweenFrames(renderer: RenderLoop<A>, pacer: FramePacer, now: UInt64) -> UInt64? {
        renderer.keepHostStateAlive(atNanos: Int64(bitPattern: now))
        return pacer.waitNanos(
            now: now, pollingPendingInput: terminal.hasPendingInput,
            until: renderer.hostState.keepAliveDeadline.map { UInt64(bitPattern: $0) })
    }

    /// What the exit writes before the terminal leaves the alternate screen:
    /// the image deletes and the hairlines' strips, and then a copy made in
    /// the last moments — a Ctrl-C and then Ctrl-Q before a frame drew — which is
    /// still owed to the terminal's clipboard; likewise attention asked for on the way out
    /// (`requestAttention("Done")` and then `dismiss()`), which no frame would
    /// write; and what the app set on the terminal emulator, given back.
    ///
    /// Internal rather than `fileprivate` only so a test can name it: its one
    /// caller is the exit's cleanup, which hands back the console.
    func exitFarewell(renderer: RenderLoop<A>) -> String {
        let attention = renderer.attentionWrites()
        return tuiContext.terminalImageStore.takePending() + renderer.handBackHairlines()
            + renderer.handBackPicturesUnderText()
            + tuiContext.clipboardWriter.takePendingSequences()
            + attention.notifications + attention.bell + renderer.handBackHostState()
    }
}
