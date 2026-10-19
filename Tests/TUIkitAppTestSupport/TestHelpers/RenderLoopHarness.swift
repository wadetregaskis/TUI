//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoopHarness.swift
//
//  Everything `RenderLoop` needs, assembled the way `AppRunner` does, so a test
//  can drive whole frames against a `MockTerminal`. Shared rather than copied:
//  two suites drive the loop now — the render-pass scope tests and the
//  animation-replay tests — and a second copy of this assembly would be a
//  second thing to keep in step with `AppRunner`'s own.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUIkitTestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
final class RenderLoopHarness {
    let terminal = MockTerminal()
    /// The context's render state — the instance the status bar was built
    /// around and the loop's frame requests reach — so a test can post the
    /// signals the run loop consumes (`setNeedsAnimationTick`, and so on) and
    /// read the ones it raises.
    let appState: AppState
    let statusBar: StatusBarState
    let focusManager = FocusManager()
    let tuiContext: TUIContext
    let paletteManager: ThemeManager
    let appearanceManager: ThemeManager

    /// What every loop built here has published about the terminal's colours,
    /// in order.
    ///
    /// Kept here rather than assigned to `TerminalColors.current`, which every
    /// suite in the process reads: a colour answer one wiring test fed its loop
    /// stayed the terminal's background, and a later suite's translucent ground
    /// came out blended over it.
    var publishedColors: [TerminalColors] { colourRecord.published }

    /// A class so the loop's closure and this harness share one record.
    private final class ColourRecord {
        var published: [TerminalColors] = []
    }
    private let colourRecord = ColourRecord()

    /// - Parameter tuiContext: The context the loop renders with. A test that
    ///   drives an `AppRunner` seam — a terminal focus report, say — passes the
    ///   runner's own, so what the seam changes is what the loop draws.
    init(tuiContext: TUIContext = TUIContext()) {
        self.tuiContext = tuiContext
        self.appState = tuiContext.appState
        self.statusBar = StatusBarState(appState: tuiContext.appState)
        self.paletteManager = ThemeManager(items: PaletteRegistry.all, renderTrigger: {})
        self.appearanceManager = ThemeManager(items: AppearanceRegistry.all, renderTrigger: {})
    }

    /// A loop over this harness's terminal.
    ///
    /// `isTmux` is the seam `Terminal.askColors(isTmux:)` already uses:
    /// `TerminalHost.isTmux` is read from the environment once per process, so a
    /// test that needs the tmux branch has to say so rather than set it.
    ///
    /// What the loop publishes about the terminal's colours goes to
    /// ``publishedColors``.
    ///
    /// `reducesMotion` is what the app runner reads from `TUIKIT_REDUCE_MOTION`,
    /// and `keyNotation` what it reads from `TUIKIT_KEY_SYMBOLS`; a test states
    /// them, and by default the loop draws as if both were unset.
    func loop<A: App>(
        _ app: A, isTmux: Bool = false, reducesMotion: Bool = false, keyNotation: KeyNotation = .symbols
    ) -> RenderLoop<A> {
        loop(app, on: terminal, isTmux: isTmux, reducesMotion: reducesMotion, keyNotation: keyNotation)
    }

    /// A loop over another terminal: a real `Terminal` writing to a script
    /// (`ScriptedTerminalOutput`), for a test of the bytes a frame is sent as.
    func loop<A: App>(
        _ app: A, on terminal: any TerminalProtocol, isTmux: Bool = false, reducesMotion: Bool = false,
        keyNotation: KeyNotation = .symbols
    ) -> RenderLoop<A> {
        RenderLoop(
            app: app,
            terminal: terminal,
            statusBar: statusBar,
            focusManager: focusManager,
            paletteManager: paletteManager,
            appearanceManager: appearanceManager,
            tuiContext: tuiContext,
            isTmux: isTmux,
            publishTerminalColors: { [colourRecord] in colourRecord.published.append($0) },
            reducesMotion: reducesMotion,
            keyNotation: keyNotation)
    }
}

#endif
