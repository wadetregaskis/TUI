//  🖥️ TUI — A Terminal UI framework for Swift
//  AppRunner+HandOff.swift
//
//  Handing the terminal to another program for as long as a closure runs —
//  `\.handOffTerminal` — and taking it back: the Ctrl-Z round trip without the
//  stop.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension AppRunner {
    /// Gives the context's hand-off (``TerminalHandOff``) its handler for this
    /// run, so that `\.handOffTerminal` hands this app's terminal over. The
    /// teardown (`cleanup`) takes it away again: after that, a closure handed
    /// to the action just runs.
    func installTerminalHandOff(renderer: RenderLoop<A>, cursorTimer: CursorTimer) {
        tuiContext.terminalHandOff.handler = { [weak self] body in
            guard let self else { return body() }
            self.handOffTerminal(renderer: renderer, cursorTimer: cursorTimer, running: body)
        }
    }

    /// Hands the terminal to another program while `body` runs, and takes it
    /// back: the Ctrl-Z round trip (`suspendUntilContinued`), with `body` where
    /// the stop was.
    ///
    /// On the way out, a frame at `.background`, as a suspend draws one, so an
    /// `onChange(of: scenePhase)` that saves on the way down runs — but not
    /// inside a frame being drawn, which a call from a view's `body` would be
    /// in. Then the terminal handed back as a suspend hands it
    /// (``handBackTerminal(renderer:)``), which turns raw mode off and with it
    /// disarms both watches on the input (the stall watchdog and the quit
    /// key's), as they are armed only in raw mode: nothing of the app's reads
    /// the other program's keystrokes or writes to its screen. The run loop
    /// itself reads nothing until `body` returns, as `body` holds the main
    /// actor; the arrival notifier's read source only wakes it, and can't run
    /// meanwhile either. And the signals set as `system(3)` sets them
    /// (``SignalManager/beginHandOff()``).
    ///
    /// On the way back, the signals put back first, then the terminal taken
    /// back as after an external stop, since the program may have left any
    /// mode in any state: once in the foreground, raw mode made again, every
    /// mode asserted, the diff cache invalidated, and a frame asked for, which
    /// reads the size again and repaints every line.
    func handOffTerminal(renderer: RenderLoop<A>, cursorTimer: CursorTimer, running body: () -> Void) {
        tuiContext.scenePhase = .background
        if !renderer.isRendering {
            renderOutsidePacer(renderer: renderer, cursorTimer: cursorTimer)
        }
        handBackTerminal(renderer: renderer)
        signals.beginHandOff()

        body()

        signals.endHandOff()
        // A ⌃Z in the program stopped the app with it, and a `bg` may have
        // resumed the job in the background, where it must not touch the
        // terminal.
        waitUntilForeground()
        retakeTerminal(renderer: renderer)
        // The animation clocks ran on while the program had the terminal, as
        // across a stop: the caret and focus breath restart at their bright end.
        cursorTimer.restartFocusPhase()
        tuiContext.scenePhase = .active
        frameTrace?.note(.resume)
        // The app's render state, which `tuiContext.appState` is.
        tuiContext.appState.setNeedsRender()
    }
}
