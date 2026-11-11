//  🖥️ TUI — A Terminal UI framework for Swift
//  AppRunner+Suspend.swift
//
//  What the run loop does about being stopped: Ctrl-Z, an external `SIGSTOP`, and being
//  resumed from either. Split from `App.swift`, which had reached the file-length limit,
//  unchanged but for access.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIChrome
import TUIFoundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#elseif canImport(WASILibc)
    import WASILibc
#endif

extension AppRunner {
    /// Serves a stop asked for or a resume noticed since the last iteration of the loop.
    func serveStops(renderer: RenderLoop<A>, cursorTimer: CursorTimer, pacer: inout FramePacer) {
        // Ctrl-Z (SIGTSTP): hand the terminal back to the shell, stop for
        // real, and rebuild everything when `fg` resumes us. Runs here —
        // not in the signal handler — because only the loop owns the
        // terminal state it has to tear down and rebuild.
        if signals.consumeSuspendFlag() {
            // The one scene-phase transition a terminal can actually
            // report. Render a frame at `.background` BEFORE stopping, so
            // an `onChange(of: scenePhase)` observer gets to run while the
            // process is still alive — an app that saves on the way down
            // has no other moment. See ``ScenePhase``.
            tuiContext.scenePhase = .background
            renderOutsidePacer(renderer: renderer, cursorTimer: cursorTimer)
            suspendUntilContinued(renderer: renderer)
            // The animation clocks are the monotonic clock, which ran on while
            // the process was stopped: looping animations resume where it now
            // is, and the caret and focus breath restart at their bright end.
            cursorTimer.restartFocusPhase()
            tuiContext.scenePhase = .active
            frameTrace?.note(.resume)
            pacer.requestRender()
        }

        // Resumed from an *external* SIGSTOP, which cannot be caught, so
        // nothing was handed back — and while the process slept the shell
        // had the terminal, in this process's raw mode and modes, and may
        // have changed both. Taken back as a Ctrl-Z resume takes it.
        if signals.consumeContinueFlag() {
            recoverFromExternalStop(renderer: renderer)
            // The same long gap as Ctrl-Z's, so the same restart.
            cursorTimer.restartFocusPhase()
            frameTrace?.note(.resume)
            pacer.requestRender()
        }
    }

    /// The Ctrl-Z round trip: hands the terminal back to the shell exactly the
    /// way quitting would, stops the process for real, and — execution resumes
    /// at the next line when `fg` delivers SIGCONT — rebuilds the terminal
    /// exactly the way `run` set it up.
    ///
    /// `SIGSTOP` is used for the stop because it cannot be caught or ignored:
    /// SIGTSTP's default action is suppressed by the signal source's
    /// registration (stopping the instant it lands would strand the shell in
    /// raw mode on the alternate screen), so re-raising it would just re-enter
    /// the handler.
    private func suspendUntilContinued(renderer: RenderLoop<A>) {
        handBackTerminal(renderer: renderer)
        // Our own resume delivers a SIGCONT too; the repaint is already
        // forced below, so arm the source to swallow that one signal.
        // Arming (not consume-after-resume): the SIGCONT source runs on the
        // main queue, which cannot fire until this synchronous path has
        // finished — a consume here would run before the flag is ever set,
        // and the loop would double-repaint on the next iteration.
        signals.expectSelfResume()
        // The stop itself, and the dance with the foreground process group that
        // follows it, are job control — POSIX, and absent on wasip1. The whole
        // path is unreachable there (nothing ever sets the suspend flag), but
        // unreachable code still has to compile.
        #if !canImport(WASILibc)
        raise(SIGSTOP)
        // ── stopped; `fg` resumes here ──
        #endif
        waitUntilForeground()
        retakeTerminal(renderer: renderer)
    }

    /// Takes the terminal back after an *external* `SIGSTOP` (`kill -STOP`,
    /// then `fg`), which cannot be caught, so nothing was handed back: the
    /// shell had the terminal in this process's raw mode, with every mode it
    /// set — and may have changed them, as a line editor resets bracketed
    /// paste or pushes kitty flags of its own, and `stty sane` or `reset`
    /// change the rest. So: once in the foreground, raw mode is turned off
    /// by this process's own books (``Terminal/disableRawMode()``: the modes
    /// off, the kitty flags popped, the shell's termios back) and taken back
    /// as a Ctrl-Z resume takes it (``retakeTerminal(renderer:)``): raw mode
    /// made again from the shell's original termios, every mode asserted,
    /// the flags pushed again. Without leaving the alternate screen, which
    /// would show the shell's screen for a moment for nothing. The pop
    /// before the push keeps one entry of this process's on the kitty stack
    /// whether or not the shell left it there (a pop of an empty stack does
    /// nothing).
    private func recoverFromExternalStop(renderer: RenderLoop<A>) {
        waitUntilForeground()
        terminal.applyMouseSupport(.disabled)
        tuiContext.mouseEventDispatcher.forgetRestingPointer()
        terminal.disableRawMode()
        retakeTerminal(renderer: renderer)
    }

    /// Hands the terminal back to the shell: the mouse mode off, the
    /// hairlines' strips, the pictures drawn under text and the window title
    /// taken back, the styling reset, raw mode off with every mode it set, the
    /// cursor shown and the alternate screen left. Shared by
    /// the Ctrl-Z suspend and a hand-off to another program
    /// (``handOffTerminal(renderer:cursorTimer:running:)``).
    ///
    /// The mouse mode is set to `.none` here and NOT re-applied by
    /// ``retakeTerminal(renderer:)``: the loop re-evaluates the effective mode
    /// every frame and re-emits it on change, so the first frame after —
    /// forced by the diff-cache invalidation — restores whatever mode the
    /// scene wants.
    func handBackTerminal(renderer: RenderLoop<A>) {
        terminal.applyMouseSupport(.disabled)
        // The pointer goes where it likes, unreported, until the mode is back.
        tuiContext.mouseEventDispatcher.forgetRestingPointer()
        // The styling reset first: a frame may have ended with styling in
        // force, and leaving the alternate screen does not restore SGR. The
        // shell's window title back with it; the first frame after the resume
        // sets the app's again. The hairlines' strips go too: iTerm2 shows a
        // line left on the alternate screen on the shell's (`HairlineLayer`).
        terminal.handBack(
            farewell: renderer.handBackHairlines() + renderer.handBackPicturesUnderText()
                + renderer.handBackHostState(),
            restoringStyling: renderer.restoreTerminalStyling)
        // The shell's screen is back, so held soft-trap reports can be read there.
        SoftTrap.terminalRestored()
    }

    /// Waits until this process is the terminal's foreground job, stopping
    /// again while it is not: the resume of a stop, by `fg` or `bg`.
    func waitUntilForeground() {
        #if !canImport(WASILibc)
        // `bg` resumes a stopped job too, and a BACKGROUND process must not touch the terminal:
        // the escapes below would garble the shell's prompt, and grabbing raw
        // mode would steal the foreground shell's keystrokes. Re-stop until
        // the shell actually hands the terminal over (`fg` makes this group
        // the foreground group) — which is also what the kernel's SIGTTOU
        // default would do to a background job touching the tty, so `bg`
        // behaves the way it does for any full-screen program: the job
        // reports stopped again, and finishes its resume when foregrounded.
        // The `>= 0` guards a failed query (not a tty): never loop on an
        // answer that cannot change.
        while tcgetpgrp(STDIN_FILENO) >= 0, tcgetpgrp(STDIN_FILENO) != getpgrp() {
            signals.expectSelfResume()
            raise(SIGSTOP)
        }
        #endif
    }

    /// Takes the terminal back the way `run` set it up, after a stop: the
    /// alternate screen, the cursor hidden, raw mode and its modes, the
    /// host's own modes, and every line repainted. Shared by the Ctrl-Z
    /// resume, the recovery from an external stop, and the end of a hand-off
    /// to another program.
    func retakeTerminal(renderer: RenderLoop<A>) {
        terminal.enterAlternateScreen()
        SoftTrap.holdUntilTerminalRestored()
        terminal.hideCursor()
        terminal.enableRawMode()
        // `disableRawMode` put grapheme clustering (mode 2027) back the way the
        // shell had it, and `enableRawMode` re-emits bracketed paste and the
        // cursor-key mode but not that: the advance model was frozen into the
        // diff writer at startup on the strength of the pin, so a resume
        // without it compensated every later frame against a terminal whose
        // mode had changed under it. Paste events (mode 5522) likewise.
        terminal.resumeModesOfIdentifiedHost()
        // The kitty keyboard protocol's flags are pushed again by
        // `enableRawMode`, as `disableRawMode` popped them.
        renderer.invalidateDiffCache()
    }
}
