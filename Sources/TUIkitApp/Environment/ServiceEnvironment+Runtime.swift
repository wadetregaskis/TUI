//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ServiceEnvironment+Runtime.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

// MARK: - Runtime Service Wiring

extension EnvironmentValues {
    /// Wires the runtime services that the render pass and view
    /// modifiers read (state storage, lifecycle, the input
    /// dispatchers, render cache, preferences, localization) from a
    /// ``TUIContext`` into this environment.
    ///
    /// Shared by ``RenderLoop`` — the live pipeline — and
    /// ``ViewRenderer`` — one-off snapshot rendering — so the set of
    /// wired services can't drift between the two. It deliberately
    /// does **not** set the app-level managers (status bar, app
    /// header, focus, palette, appearance); callers add those as they
    /// need them.
    mutating func applyRuntimeServices(from context: TUIContext) {
        keyboardShortcutRegistry = context.keyboardShortcuts
        stateStorage = context.stateStorage
        lifecycle = context.lifecycle
        keyEventDispatcher = context.keyEventDispatcher
        synthesizeKeyEvent = context.synthesizeKeyEvent
        mouseEventDispatcher = context.mouseEventDispatcher
        dragAndDropSession = context.dragAndDropSession
        typedClipboard = context.typedClipboard
        clipboardAccess = context.clipboardAccess
        terminalBell = context.terminalBell
        keysAfterFrame = context.keysAfterFrame
        urlOpener = context.urlOpener
        screenSelection = context.screenSelection
        tooltipState = context.tooltipState
        terminalImageStore = context.terminalImageStore
        renderCache = context.renderCache
        preferenceStorage = context.preferences
        localizationService = LocalizationService.shared
        // Publish the user's locale — their language, or the one the app
        // chose, with their region — as the environment locale each frame
        // (the single source of truth),
        // so `\.locale` tracks it by default while a subtree may still
        // override it. See LocaleEnvironment.swift.
        publishUserLocale(LocalizationService.shared.currentLocale)
        // …and the scene phase from the run loop, for the same reason: one
        // source of truth, republished every frame. `appearsActive` is derived
        // from it rather than held beside it, so the two cannot disagree; it
        // needs no place of its own in the render loop's `EnvironmentSnapshot`,
        // because the phase it is derived from already has one.
        scenePhase = context.scenePhase
        appearsActive = context.scenePhase == .active
        // The top-level `dismiss()`, which exits this app and no other in the
        // process: one action for the context's life, equal every frame.
        dismiss = context.exitAction
        // The app's undo manager: a running app always has one, and nothing
        // else does, so the key's `nil` default stands everywhere else.
        if let undoManager = context.undoManager {
            self.undoManager = undoManager
            departedUndoSteps = context.departedUndoSteps
        }
        // What the terminal reports about the keyboard. Written only where the
        // kitty keyboard protocol is on: the key's default is the legacy
        // answer, so a terminal that does not speak it pays no write per
        // frame. Constant for the run, so it needs no place in the render
        // loop's `EnvironmentSnapshot` either.
        if context.keyboardReporting.isEnhanced {
            keyboardReporting = context.keyboardReporting
            // And the modifier keys, only where they are reported at all: a
            // view that listens for them finds nothing to listen to elsewhere.
            if context.keyboardReporting.reportsModifierKeys {
                modifierKeyMonitor = context.modifierKeys
            }
        }
        // What the terminal does outside its grid, on the same terms: only
        // where it does something, so a terminal that does none pays no write
        // per frame, and constant for the run.
        if context.terminalFeatures != .none {
            terminalFeatures = context.terminalFeatures
        }
    }
}
