//  🖥️ TUI — A Terminal UI framework for Swift
//  InputHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - Input Handler

/// Dispatches key events through a five-layer priority chain (layers 0–4) plus
/// four refinements wedged between them — the ESC pre-route, a carried drag,
/// layer 0.5 and layer 3.5, described after the list.
///
/// Ahead of them all comes the **focus path**: SwiftUI's `onKeyPress` handlers
/// on the views that contain the focused control, outermost first, as SwiftUI
/// asks them. They are focus-gated, which is what makes it safe to ask them
/// before even a focused text input. The same path is asked again, innermost
/// first, for SwiftUI's move, exit and delete **commands**, inside the focus
/// system's dispatch (Layer 0 or 3): after the focused control lets the key go,
/// before the focus system moves the focus with an arrow, and so before the
/// app's shortcuts.
///
/// The dispatch order is:
/// 0. **Text input** (conditional) — a focused `TextField`/`SecureField`/
///    `TextEditor` consumes the event first, except an Emacs editing chord
///    that an app's keyboard shortcut is registered on (see
///    `textInputGivesWay(_:)`)
/// 1. **Status bar** — items with actions
/// 2. **View handlers** — registered via `onKeyEvent` modifiers
/// 3. **Focus system** (conditional) — Tab/Shift+Tab navigation, Enter/Space
///    on focused buttons
/// 4. **Default bindings** — `q` (quit), undo and redo (``UndoShortcuts``),
///    Ctrl-Z where neither binds it (re-raised as SIGTSTP, so the key and the
///    external signal suspend by one path), `t` (theme), `a` (appearance)
///
/// Layers 0 and 3 are mutually exclusive, gated on
/// `focusManager.hasTextInputFocus`: when a text-input element is focused,
/// layer 0 runs and layer 3 is skipped. If a layer consumes the event,
/// subsequent layers are skipped.
///
/// The four refinements, all in `handle(_:)`:
/// - An open modal that has claimed Escape is routed through the focus system
///   ahead of layer 1, so a page-level `onKeyEvent` cannot close the page out
///   from under an open drop-down. Declined there means declined: layer 3 must
///   not offer the same event twice.
/// - **A carried drag**, ahead of everything but a screen selection: while the
///   keyboard carries a drag (Ctrl-R on a focused `.draggable`), Tab and the
///   arrows move it among the stops that can take it, Return drops it and
///   Escape puts it back (`DragAndDropSession.handleCarryKey(_:)`, owner
///   ruling A53-KEYBOARD-DRAG).
/// - **Layer 0.5**, also ahead of the status bar: while a drag is in flight the
///   arrow and paging keys scroll whatever the pointer is OVER — that is how an
///   off-screen drop destination is reached without letting go, and every layer
///   below would spend the key on the focused control instead (`6df636cd`,
///   2026-07-31).
/// - **Layer 3.5**, between the focus system and the default bindings: an
///   app's `.keyboardShortcut` fires — Return the default button and Escape the
///   cancel button, à la SwiftUI's `.keyboardShortcut(.defaultAction)` /
///   `.keyboardShortcut(.cancelAction)`, and any other key equivalent the
///   app registered. Reached only when the focused control let the key fall
///   through (`2a106663`, 2026-07-09) — or when layer 0 skipped a focused text
///   control because the chord is an editing command that gives way to an app
///   shortcut on it (``KeyboardShortcutRegistry/hasAppShortcut(for:)``).
///
/// A ⌘ chord, which only the kitty keyboard protocol delivers, takes none of
/// this: it reaches the focus path's `onKeyPress` handlers and the app's
/// shortcuts, and nothing that matches a bare key (`dispatchCommandChord(_:)`).
internal struct InputHandler {
    /// The status bar state for item-level event handling.
    let statusBar: StatusBarState

    /// The key event dispatcher for view-registered handlers.
    let keyEventDispatcher: KeyEventDispatcher

    /// The focus manager for Tab navigation and focused element activation.
    let focusManager: FocusManager

    /// The palette manager for theme cycling (`t` key).
    let paletteManager: ThemeManager

    /// The appearance manager for appearance cycling (`a` key).
    let appearanceManager: ThemeManager

    /// The app's keyboard shortcuts — default and cancel buttons and any other
    /// key equivalent. Fired at layer 3.5, after the focused control declines
    /// the key; asked BEFORE layer 0 too, without firing, whether an app
    /// shortcut is on a chord a focused text control would take, so the
    /// control can give way to it.
    let keyboardShortcuts: KeyboardShortcutRegistry

    /// The drag-and-drop session, consulted before every other layer while a
    /// drag is in flight so the navigators reach the view under the pointer.
    let dragAndDropSession: DragAndDropSession?

    /// The tooltip state, for the help key. Optional and defaulted so a test
    /// harness driving the chain need not wire a service it is not exercising.
    var tooltipState: TooltipState?

    /// The bell rung for a key press nothing took — the app's, set by the
    /// runner. `nil` (a test harness) rings nothing.
    var unhandledKeyBell: TerminalBell?

    /// Called when the user requests to quit the application.
    let onQuit: () -> Void

    /// Invoked when Ctrl-Z falls through every layer unconsumed — the runner
    /// re-raises SIGTSTP so the suspend machinery handles the key and the
    /// external signal identically.
    let onSuspend: () -> Void

    /// The app's undo manager, whose undo and redo keys (``undoKeys``) are
    /// default bindings: an app's own shortcut on the chord comes first.
    /// Optional and defaulted, as ``tooltipState`` is, for a test harness that
    /// does not exercise it.
    var undoManager: UndoManager?

    /// The app's undo and redo keys, as the scene set them
    /// (``Scene/undoShortcuts(_:)``) — the app's, published each frame, in a
    /// running app; TUI's defaults by default.
    var undoKeys = AppUndoKeys()

    /// TUI's selection of what is on the screen, whose copy and clear keys
    /// come before every layer while a selection is drawn. Optional and
    /// defaulted, as ``tooltipState`` is.
    var screenSelection: ScreenSelection?

    /// The user's quit key, as the byte a legacy encoding sends for it
    /// (`Terminal.quitKeyByte`: ⌃\\'s 0x1C unless they moved it), asked when
    /// a Control chord nothing took arrives; `nil` where there is none.
    /// Defaulted, as ``undoManager`` is, for a test harness that does not
    /// exercise it.
    ///
    /// While the quit key is live the driver turns the byte into `SIGQUIT`
    /// before the app reads it, so the chord reaches the chain as a kitty
    /// keyboard protocol report, which the terminal sends in its place, or
    /// as the byte where the driver's quit is masked because the app binds
    /// a chord it could be (`Terminal.maskQuitKey(for:)`). The app's
    /// bindings are offered it first, as any key, and ``handle(_:)`` does
    /// what the driver would have only if none takes it (``onQuitKey``).
    var quitKey: () -> UInt8? = { nil }

    /// Invoked when the user's quit key reaches the end of the chain with
    /// nothing taking it: the runner sends `SIGQUIT` to the app's process
    /// group, as the driver does for the byte (`QuitKeyReport`).
    var onQuitKey: () -> Void = {}

    /// Which chords a key that arrives as ⌃\ may be instead — ⌃4, and ⌃|
    /// and ⌃⇧\: those the host may send ⌃\\'s 0x1C for in its legacy
    /// encoding, as measured of it or assumed of one not measured
    /// (`TerminalClient.quitByteAliases(_:)`), while the terminal is in that
    /// encoding; none under the kitty keyboard protocol. Asked for a ⌃\
    /// nothing took. Defaulted, as ``quitKey`` is.
    var quitByteAliasing: () -> TerminalClient.QuitByteAliases = { [] }
}

// MARK: - Internal API

extension InputHandler {
    /// Sends the pointer's tooltip away for a key going down — any but the
    /// help key, which reveals the focused view's instead
    /// (`TooltipState.noteKeyPress()`).
    ///
    /// - Returns: Whether one went, so the frame that takes it away is drawn
    ///   whether or not anything takes the key.
    func silencePointerTooltip(for event: KeyEvent) -> Bool {
        guard event.phase != .release, let tooltipState, event.key != tooltipState.helpKey else { return false }
        return tooltipState.noteKeyPress()
    }

    /// Dispatches a key event through the five-layer priority chain.
    ///
    /// - Parameter event: The key event to handle.
    /// - Returns: `true` if some layer consumed the event. The run loop uses
    ///   this to request a render — a consumed key has, by definition, done
    ///   something (moved focus, activated a control, typed text, cycled the
    ///   theme), and much of that mutates state the demand-driven loop can't
    ///   otherwise observe. In particular `ItemListHandler`/`FocusManager` move
    ///   their focus/scroll position through plain stored properties, not
    ///   `@State`, so nothing calls `setNeedsRender()` for them; without this
    ///   signal arrow-key navigation in a `List` would change the selection but
    ///   never repaint. (Symmetric with the mouse path, which already re-renders
    ///   when a handler consumes an event.) An unconsumed key returns `false`
    ///   so a genuine no-op key doesn't wake the loop.
    @discardableResult
    func handle(_ event: KeyEvent) -> Bool {
        let taken = dispatchKey(event)
        // A key press nothing took rings the bell, as an unhandled key does
        // on a Mac (NSBeep): typing at a page with nothing to type into,
        // an arrow at the end of a list that has nowhere to go. A release, or
        // a repeat the kitty keyboard protocol reports as one, rings nothing:
        // the press already did.
        if !taken, event.phase == .press { unhandledKeyBell?.ring() }
        return taken
    }

    /// Offers `event` to the chain's layers in order, reporting whether one
    /// took it.
    private func dispatchKey(_ event: KeyEvent) -> Bool {
        // A release goes to the focus path's key-press handlers and nowhere
        // else. Every other layer acts on a key going down, and a release
        // offered to them would act a second time for one keystroke. Only a
        // terminal speaking the kitty keyboard protocol sends one; a repeat,
        // which it also reports, is a press to every layer, as the legacy
        // encodings' identical copies always were.
        guard event.phase != .release else { return handleRelease(event) }
        if event.command { return dispatchCommandChord(event) }
        // Layer -1, while a selection of the screen is drawn: the app's ⌘C
        // (Ctrl-C by default) copies it, and Escape clears it. Ahead of
        // everything, the focused text input included: the selection is the
        // newest thing the user did — any left press clears it, and so does any
        // key a text input takes (layer 0) — so a field focused before the drag
        // must not copy its own older selection instead.
        if let taken = screenSelection?.handleKey(event) { return taken }
        // A drag the keyboard carries takes the keys that carry it, drop it
        // and put it back, ahead of the focused control (A53-KEYBOARD-DRAG).
        if let taken = dragAndDropSession?.handleCarryKey(event) { return taken }
        if event.isControlReturn { return dispatchControlReturn(event) }
        if dispatchPress(event) { return true }

        // Ctrl-H, I, J, M and [ arrive as themselves only where the kitty
        // keyboard protocol is on. Everywhere else they arrive as Backspace,
        // Tab, Return and Escape, and hands have learnt them as those: Ctrl-[
        // to leave, Ctrl-H to rub out. So a chord nothing took goes round once
        // more as the key it would have been — a binding on the chord still
        // wins, and an unbound one does what it always did.
        if let legacy = event.legacyControlEquivalent {
            return dispatchPress(legacy)
        }

        // ⌃\ in a legacy encoding is the byte 0x1C, which some terminals
        // send for ⌃4, ⌃| and ⌃⇧\ as well. Nothing in the byte says which,
        // so ⌃\ is asked first (a binding on it wins), and an unbound one
        // goes round once more as each of the others the host may send it
        // for — to the bindings the app declared for them alone, so a ⌃4
        // shortcut fires, while a handler that hears every key, or a field's
        // digits, hears the byte once, as ⌃\ (`dispatchToDeclaredBindings(_:)`).
        for alias in event.quitByteAliases(on: quitByteAliasing()) where dispatchToDeclaredBindings(alias) {
            return true
        }

        // The user's quit key, where nothing took it: what the driver would
        // have done had it had the byte — `SIGQUIT`. It gets here as a kitty
        // keyboard protocol report, which the driver never sees, or as the
        // byte itself where the driver's quit is masked because the app
        // declares a binding the byte could be for
        // (`Terminal.maskQuitKey(for:)`). A binding on the chord takes it
        // first, as it takes any key: the owner's rule (2026-10-06), that an
        // app's own ⌃\ overrides the quit.
        if let byte = event.legacyControlByte, byte == quitKey() {
            onQuitKey()
            return true
        }
        return false
    }

    /// Ctrl-Return, which arrives as itself only where the terminal speaks the
    /// kitty keyboard protocol — every legacy encoding sends a plain CR, which
    /// is Return and never comes here — offered as macOS layers it (owner
    /// ruling B63-KITTY, 2026-10-26):
    ///
    /// 1. to the app: its key handlers on the way to the focused view, then
    ///    its keyboard shortcuts (an app's ⌘↩ is Ctrl-Return under
    ///    `.commandKey(.control)`), then the handlers it registered;
    /// 2. to a context menu on what has the focus, as macOS's Control-Return
    ///    "Show contextual menu": an app's `.contextMenu` answers the chord
    ///    itself, and where no text input has the focus it goes round as the
    ///    context-menu key, Shift-F10, so a list's or a tab's row menu opens
    ///    too. A text control's own editing menu is not one of them: its
    ///    line break comes first;
    /// 3. to the focused control as itself, where a vertical text field reads
    ///    it as a line separator (U+2028), the text system's
    ///    `insertLineBreak:`;
    /// 4. and, nothing having taken it, as the Return the legacy encodings
    ///    would have sent.
    ///
    /// On macOS the terminal itself may keep the chord for its own contextual
    /// menu, and then it never arrives: nothing relies on it alone.
    private func dispatchControlReturn(_ event: KeyEvent) -> Bool {
        if focusPathHearsKeys, let focused = focusManager.focusedIdentity,
            keyEventDispatcher.dispatchFocusPath(event, focusedIdentity: focused, stage: .keyPress)
        {
            focusManager.noteInputToFocusedControl()
            return true
        }
        if keyboardShortcuts.trigger(
            for: event, activePane: focusManager.activePaneID, reachesPage: !focusManager.activeSectionIsModal)
        {
            return true
        }
        if keyEventDispatcher.dispatch(event) { return true }
        if !focusManager.hasTextInputFocus,
            dispatchPress(KeyEvent(key: .f10, alt: event.alt, shift: true, phase: event.phase))
        {
            return true
        }
        if dispatchPress(event) { return true }
        return dispatchPress(KeyEvent(key: .enter, alt: event.alt, phase: event.phase))
    }

    /// The chain for a ⌘ chord, which only a terminal speaking the kitty
    /// keyboard protocol delivers: the focus path's `onKeyPress` handlers,
    /// which see `.command` in its modifiers as in SwiftUI, then the app's
    /// shortcuts — which hold a real-⌘ trigger only where the app asked for
    /// one (`View.keyboardShortcutsMatchCommand(_:)`), so by default none
    /// does. Nothing else: every other layer matches a key by its character
    /// and the modifiers it knows, and would take ⌘K for a bare `k` — a text
    /// field would type it, type select would search for it, the status bar,
    /// `t` and `a` and an `onKeyEvent` handler would fire. Keeping the chord
    /// from them is the one place that refusal is made, rather than in each
    /// of them (decisions D1K, B-D1K-1).
    ///
    /// Not while an open drop-down holds the keyboard, as the focus path is
    /// not (``focusPathHearsKeys``): an app's shortcut must not fire from
    /// under it.
    private func dispatchCommandChord(_ event: KeyEvent) -> Bool {
        guard focusPathHearsKeys else { return false }
        if let focused = focusManager.focusedIdentity,
            keyEventDispatcher.dispatchFocusPath(event, focusedIdentity: focused, stage: .keyPress)
        {
            focusManager.noteInputToFocusedControl()
            return true
        }
        return keyboardShortcuts.trigger(
            for: event, activePane: focusManager.activePaneID, reachesPage: !focusManager.activeSectionIsModal)
    }

    /// The five-layer chain for a key going down or repeating — everything
    /// ``handle(_:)`` does but the release and the legacy fallback.
    private func dispatchPress(_ event: KeyEvent) -> Bool {
        // The focus path: SwiftUI's `onKeyPress` handlers on the way to the
        // focused view, outermost first, BEFORE the focused control has the
        // key — a text input included, so a `.handled` letter is never typed.
        // That is SwiftUI's order (macOS 15), and it is safe here only because
        // these handlers are focus-gated: one cannot take typing from a field
        // it does not contain, as a focus-blind `onKeyEvent` at Layer 2 could.
        if focusPathHearsKeys, let focused = focusManager.focusedIdentity,
            keyEventDispatcher.dispatchFocusPath(event, focusedIdentity: focused, stage: .keyPress)
        {
            // Taken on its way to the focused control: input all the same, so
            // a focus the manager chose by itself now counts as held (B35).
            focusManager.noteInputToFocusedControl()
            return true
        }

        // Layer 0: Text input (conditional). When a text-input element
        // (TextField/SecureField) is focused, let it handle the event FIRST.
        // This ensures printable characters, backspace, delete, arrows, home,
        // end, and enter reach the text field before any other layer can
        // intercept them.
        //
        // Only structural/navigation keys that the text field does NOT consume
        // (Escape, Tab, unhandled Ctrl+shortcuts) fall through to other layers.
        // Mutually exclusive with Layer 3 (focus system), which is skipped
        // below when text input has focus.
        //
        // The one key the text input is not offered: an editing chord it
        // gives up to an app shortcut. It goes on down the chain as a chord
        // the input does not bind would, and Layer 3.5 fires the shortcut.
        if focusManager.hasTextInputFocus, !textInputGivesWay(event) {
            if focusManager.dispatchKeyEvent(event, commands: focusedViewCommands) {
                // Typing or selecting in a field is the newest thing the user
                // did; a selection on the screen gives way to it.
                screenSelection?.clear()
                return true
            }
        }

        // Modal-claimed ESC: when an open Picker drop-down (or similar
        // transient surface) has signalled "I own ESC for this frame" by
        // setting `escapeLabelOverride`, route the key through the focus
        // system *before* the status bar or any view-registered handler
        // gets a shot. Otherwise a page-level onKeyEvent that returns to
        // the menu (the example app's ContentView, for one) would close
        // the page out from under the open drop-down.
        //
        // Declined here means declined: layer 3 below must not offer the
        // SAME event to the focus system a second time — a dispatch can
        // have side effects (a list consuming its one-shot ESC claim, a
        // handler advancing internal state) even when it returns false.
        var focusDeclinedEscape = false
        if event.key == .escape, statusBar.escapeLabelOverride != nil,
            !focusManager.hasTextInputFocus
        {
            if focusManager.dispatchKeyEvent(event, commands: focusedViewCommands) {
                return true
            }
            focusDeclinedEscape = true
        }

        // The exit command (`.onExitCommand`) of a view that holds or contains
        // the focus answers Escape before the status bar's items and the
        // page's own key handlers, as the view nearest the focus answers
        // first in SwiftUI: an app's "⎋ back" bound to Escape took the key
        // from a focused board whose exit command was to fill it again. Only
        // the command stage, which nothing but an exit command answers
        // Escape at — a control's own Escape still comes after the bar.
        if event.key == .escape, !focusDeclinedEscape, !focusManager.hasTextInputFocus,
            focusedViewCommands(event)
        {
            return true
        }

        // Layer 0.5: mid-drag navigators. While something is in hand they
        // scroll whatever the pointer is over — reaching a destination that is
        // off screen without letting go — and they must beat every layer below,
        // all of which would otherwise spend them on the focused control (a
        // page-level `onKeyEvent` returning to the menu, the source list moving
        // its own selection). Declines unless a drag is actually in flight AND
        // the pointer is over something that drag could land in.
        if dragAndDropSession?.handleDragNavigator(event) == true {
            return true
        }

        // Layer 1: Status bar items with actions
        if statusBar.handleKeyEvent(event) {
            return true
        }

        // Layer 2: View-registered key handlers (onKeyEvent, Menu arrow keys).
        //
        // Layer 2.5: an open menu's type select. The menu holds the keyboard
        // without holding the focus, so it is asked here, where a focused
        // list's type select is asked at layer 3: after the menu's own keys,
        // and by the same rule — it takes every character type select takes,
        // and no bare-key binding below hears one (B77-KEYTIME).
        if keyEventDispatcher.dispatch(event) || openMenuTypeSelect(event) {
            return true
        }

        // Layer 3: Focus system (Tab navigation, Enter/Space on focused buttons)
        // Skipped when text-input has focus since it was already dispatched
        // above — and when the modal-claimed ESC pre-route already offered
        // this very event and was declined.
        if !focusManager.hasTextInputFocus, !focusDeclinedEscape {
            if focusManager.dispatchKeyEvent(event, commands: focusedViewCommands) {
                return true
            }
        }

        // Layer 3.5: semantic shortcut actions — the default button
        // (Return/Enter) and the cancel button (Escape), à la SwiftUI's
        // `.keyboardShortcut(.defaultAction / .cancelAction)`. Reached only
        // when the focused control let the key fall through: a TextEditor
        // inserting a newline, a list activating its row, or a focused
        // Button firing itself all consumed it earlier (macOS responder-
        // chain semantics); a TextField without `onSubmit` deliberately
        // lets Return through so the dialog's default button fires.
        if keyboardShortcuts.trigger(
            for: event, activePane: focusManager.activePaneID, reachesPage: !focusManager.activeSectionIsModal)
        {
            return true
        }

        // Layer 4: Default key bindings.
        //
        // Quit stays available even behind a transient surface — a modal's status
        // bar still offers `q quit` as an escape hatch — so it is handled first,
        // unconditionally.
        if runQuitShortcut(event) {
            return true
        }

        // Undo and redo: the scene's keys (`UndoShortcuts`), by default Ctrl-Z,
        // Ctrl-minus and Ctrl-/ for undo, Ctrl-Shift-Z, Ctrl-_ and Option-_ for
        // redo, where the terminal can send them. Down here, after the app's
        // shortcuts, so a binding of the app's own on the chord — a ⌘- zoom-out
        // under `.commandKey(.control)` — keeps it.
        if runUndoKey(event) {
            return true
        }

        // Ctrl-Z: job-control suspend, where neither undo nor redo binds it.
        // Raw mode turns ^Z off as a signal character (only the quit key, ^\,
        // stays one: `Terminal.rawModeAttributes(from:)`), so the terminal
        // driver never turns it into SIGTSTP — it arrives here as an
        // ordinary key event. Reaching THIS
        // layer means no view claimed it (a text editor binding Ctrl-Z to undo
        // wins, exactly as it should) and the app's undo keys do not include
        // it, so give it its shell meaning: re-raise it as the signal, which
        // the suspend machinery observes and acts on between frames. With
        // Shift too, which a legacy encoding cannot even send apart from
        // Ctrl-Z (both are 0x1A): only a Ctrl-Shift-Z the redo keys leave
        // unbound reaches here. And with Option, as before the app had an
        // undo: Ctrl-Option-Z is not one of undo's keys, and a shell reads
        // its `ESC 0x1A` as a suspend too (Terminal compatibility survey.md, "Undo
        // and redo").
        if event.ctrl, case .character(let character) = event.key,
            character == "z" || character == "Z"
        {
            onSuspend()
            return true
        }

        // The remaining global shortcuts (appearance / theme cycling) are app
        // chrome, not part of any modal's interaction. Suppress them while an
        // input-grabbing transient surface is up — a presented modal / alert
        // (its focus section is marked modal) or an open drop-down (which has
        // claimed ESC). Otherwise `a` would cycle the border style and `t` the
        // theme from *behind* the modal, which the user never asked for and
        // can't see the controls for.
        // A lightweight ESC claim (a list's clearable selection) re-routes
        // only the ESC key; it doesn't ground the chrome shortcuts the way
        // an open drop-down does — hence the grabs-input qualifier.
        return handleGlobalShortcut(event, inputGrabbed: globalChromeGrabbed)
    }

    /// Layer 4's quit: the status bar's quit key (`q` by default), which
    /// quits through the bar, so a top-level dismissal confirmation can ask
    /// first — and does nothing where the bar does not allow a quit.
    ///
    /// - Returns: Whether `event` was the quit key: taken, quit or not.
    func runQuitShortcut(_ event: KeyEvent) -> Bool {
        guard statusBar.quitShortcut.matches(event) else { return false }
        quit()
        return true
    }

    /// The quit key's quit, with no key: through the status bar, so a
    /// top-level dismissal confirmation can ask first, and nothing where the
    /// bar does not allow a quit. What the menu bar's Quit asks for
    /// (`KeysAfterFrame.Owed.quit`).
    func quit() {
        if statusBar.isQuitAllowed {
            statusBar.requestQuit(onQuit)
        }
    }

    /// Does what a frame owed once it is on the screen (`KeysAfterFrame`): a
    /// key through the whole chain, or the quit.
    func perform(_ owed: KeysAfterFrame.Owed) {
        switch owed {
        case .key(let event): _ = handle(event)
        case .quit: quit()
        }
    }

    /// Layer 4's undo and redo: the scene's keys (``undoKeys``), once there
    /// is an undo manager. A bound key is the command's whether or not there
    /// is a step: with nothing to undo, Ctrl-Z does nothing, rather than
    /// suspend the app some of the time.
    ///
    /// - Returns: Whether `event` was one of the keys.
    func runUndoKey(_ event: KeyEvent) -> Bool {
        guard let undoManager, let command = undoKeys.command(for: event) else { return false }
        _ = command.perform(on: undoManager)
        return true
    }

    /// Offers a key's release to the focus path's key-press handlers, the
    /// only layer that takes one — see the top of ``handle(_:)``.
    private func handleRelease(_ event: KeyEvent) -> Bool {
        guard focusPathHearsKeys, let focused = focusManager.focusedIdentity else { return false }
        return keyEventDispatcher.dispatchFocusPath(event, focusedIdentity: focused, stage: .keyPress)
    }

    /// Whether a transient surface holds the input, so the global chrome keys
    /// (`t`, `a`) are grounded: a modal's section, or an escape claim that
    /// grabs input (see the default bindings in `handle(_:)`).
    private var globalChromeGrabbed: Bool {
        let escapeClaimGrabs =
            statusBar.escapeLabelOverride != nil && statusBar.escapeClaimGrabsInput
        return focusManager.activeSectionIsModal || escapeClaimGrabs
    }

    /// Layer 2.5: offers `event` to the type select of the open menu holding
    /// the keyboard, if one is. It takes every character type select takes,
    /// whether or not a row answers to it, so no bare-key binding below hears
    /// one while a menu is open — a row's own bare key equivalent included,
    /// the row being found by its title (the owner's ruling B77-KEYTIME,
    /// 2026-10-23).
    private func openMenuTypeSelect(_ event: KeyEvent) -> Bool {
        guard let menu = keyEventDispatcher.typeSelectTarget else { return false }
        return menu.typeSelect(event)
    }

    /// Offers `event` to the focused view's commands — SwiftUI's move, exit and
    /// delete commands — innermost first. The focus system asks this once the
    /// focused control lets the key go, and before it spends an arrow on moving
    /// the focus; that is also before the app's shortcuts, as on macOS 15,
    /// where an exit command takes Escape from the cancel button.
    private func focusedViewCommands(_ event: KeyEvent) -> Bool {
        guard focusPathHearsKeys, let focused = focusManager.focusedIdentity else { return false }
        return keyEventDispatcher.dispatchFocusPath(event, focusedIdentity: focused, stage: .command)
    }

    /// Whether the focus path is offered keys at all.
    ///
    /// Not while an open drop-down holds the keyboard (an escape claim that
    /// grabs input): SwiftUI's open menu takes every key before any view sees
    /// it, and the drop-down's own keys are the focus system's. Nor while a
    /// pointer drag is in flight, whose arrow and paging keys belong to the
    /// navigators at Layer 0.5.
    var focusPathHearsKeys: Bool {
        if statusBar.escapeLabelOverride != nil, statusBar.escapeClaimGrabsInput { return false }
        if let session = dragAndDropSession, session.active != nil || session.autoScrollArmed { return false }
        return true
    }

    /// Whether the focused text input gives `event` up to an app's keyboard
    /// shortcut: the event is one of the input's Emacs editing chords, of the
    /// kind that gives way there
    /// (``TextInputFocusHandler/givesWayToKeyboardShortcut(_:)``), and an app
    /// shortcut is registered on it.
    ///
    /// Asked before the input is offered the key, not after it declines,
    /// because the input would not decline: Ctrl-F moves its caret. Under the
    /// default `.commandKey(.control)` that same Ctrl-F is SwiftUI's ⌘F, and
    /// an app's Find must not lose it to a caret motion the arrow keys also
    /// make. The registry answers from the same table
    /// ``KeyboardShortcutRegistry/trigger(for:)`` fires from, so the key it
    /// says is claimed is the key Layer 3.5 fires.
    private func textInputGivesWay(_ event: KeyEvent) -> Bool {
        guard let input = focusManager.currentFocused as? any TextInputFocusHandler,
            input.givesWayToKeyboardShortcut(event)
        else { return false }
        return keyboardShortcuts.hasAppShortcut(
            for: event, activePane: focusManager.activePaneID, reachesPage: !focusManager.activeSectionIsModal)
    }

    /// The tail of layer 4: the global appearance/theme cycling shortcuts.
    ///
    /// These bindings mean the BARE letter. A modifier chord that fell
    /// through the earlier layers unconsumed (Ctrl+T from a page with no
    /// binding for it, Ctrl+A over a single-select list) is not a request to
    /// restyle the app — swallowing it here mutated chrome as a surprise.
    private func handleGlobalShortcut(_ event: KeyEvent, inputGrabbed: Bool) -> Bool {
        // The help key with Option shows every tooltip on the screen, or hides
        // them (Help ▸ Show All Tooltips): one key for each purpose, and Option
        // the one modifier a terminal delivers on `?` — Control-? is DEL, the
        // Backspace byte, in every legacy encoding (Terminal compatibility
        // survey.md, "The help key").
        if event.alt, !event.ctrl, let tooltipState, let helpKey = tooltipState.helpKey, event.key == helpKey {
            return tooltipState.toggleShowsAllTooltips()
        }
        // Shift-F1 does the same where Option does not arrive (Apple Terminal
        // sends no Meta by default): the portable key for it (owner ruling
        // B-HELP-2, 2026-10-26). Here, in the chain's last layer, so any
        // handler of the app's or a built-in view's on the chord takes it first.
        if event.key == .f1, event.shift, !event.ctrl, !event.alt, let tooltipState {
            return tooltipState.toggleShowsAllTooltips()
        }
        guard !event.ctrl, !event.alt else { return false }
        // The help key, before the chrome shortcuts and NOT suppressed by
        // `inputGrabbed`: a tooltip explains the control that has the focus, and
        // inside a modal that control is the one the reader is looking at. It
        // mutates no app state, so the argument for grounding `t` and `a` behind
        // a modal does not transfer.
        //
        // Declining when there is nothing to reveal is the point of the returned
        // Bool: this is the last layer, so a `true` here would swallow the key
        // and report that something happened when nothing did.
        if let tooltipState, let helpKey = tooltipState.helpKey, event.key == helpKey {
            return tooltipState.toggleKeyboardReveal(focusID: focusManager.currentFocusedID)
        }
        switch event.key {
        case .character(let character) where character == "t" || character == "T":
            if statusBar.showThemeItem && !inputGrabbed {
                paletteManager.cycleNext()
                return true
            }
            return false

        // `a` is opt-in, as `t` is: a bare key restyling every app was a
        // chrome default nobody asked for, and with no bar there is nothing to
        // say what it does (A28, owner answer 6).
        case .character(let character) where character == "a" || character == "A":
            if statusBar.showAppearanceItem && !inputGrabbed {
                appearanceManager.cycleNext()
                return true
            }
            return false

        default:
            return false
        }
    }
}
