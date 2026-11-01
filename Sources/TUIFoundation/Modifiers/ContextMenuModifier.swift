//  🖥️ TUI — A Terminal UI framework for Swift
//  ContextMenuModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - Context menu modifier

/// Attaches a right-click / secondary-click pop-up menu to a view — mirrors
/// SwiftUI's `contextMenu(menuItems:)`.
///
/// Right-click (or, where a terminal swallows that, **Ctrl-click**) the content
/// to open a floating menu of `Button`s anchored at the click point; selecting
/// one runs its action and closes the menu, and Escape or an outside click
/// dismisses it. Like the alert / modal presentation modifiers this is
/// *modifier infrastructure* rendered via ``Renderable`` (it is a `some View`
/// wrapper, never a public control with a `Never` body).
///
/// It lives here, below TUIMenus, whose `.contextMenu(menuItems:)` makes
/// it, because ``Link`` offers a menu of its own (Show Link, Copy Link) and
/// TUIFoundation cannot see a module built on it.
nonisolated package struct ContextMenuModifier<Content: View, MenuItems: View>: View {
    let content: Content
    let menuItems: MenuItems
    let keyboardRoute: KeyboardRoute

    /// Whether Ctrl-Return opens the menu too, where the terminal sends it as
    /// itself (the kitty keyboard protocol), as macOS's Control-Return "Show
    /// contextual menu" does: an app's menu, but not a text control's own
    /// editing menu, ahead of whose Ctrl-Return the control's line break comes
    /// (owner ruling B63-KITTY, 2026-10-26).
    let answersControlReturn: Bool

    /// How the keyboard reaches the menu.
    package enum KeyboardRoute {
        /// The content becomes a focus stop of its own, on which Shift+F10
        /// opens the menu: `.contextMenu(menuItems:)`'s, which cannot know
        /// whether its content is a control.
        case ownStop
        /// Shift+F10 opens the menu while a focus stop the content registered
        /// holds the focus, and the content gets no stop of its own: for a
        /// control that is one already, as a ``Link`` is, which would
        /// otherwise be two stops for Tab to cross. It reports nothing to a
        /// list row it is in, whose Shift+F10 opens the row's own menu. A
        /// disabled control offers no menu, to the pointer either.
        case contentStops
        /// ``contentStops``, and the pointer opens the menu only over the
        /// content's regions that carry a focus stop, not over its whole
        /// frame: for a text whose links are its stops, where a right-click
        /// on its other words is not a right-click on a link (decisions B85).
        case contentStopRegions
    }

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIMenus makes these, for `.contextMenu(menuItems:)`.
    package init(
        content: Content, menuItems: MenuItems, keyboardRoute: KeyboardRoute = .ownStop,
        answersControlReturn: Bool = true
    ) {
        self.content = content
        self.menuItems = menuItems
        self.keyboardRoute = keyboardRoute
        self.answersControlReturn = answersControlReturn
    }

    @MainActor package var body: Never {
        fatalError("ContextMenuModifier renders via Renderable")
    }
}

/// A context menu written on a form row is the menu of the row the form lays
/// out, which keeps its place, as SwiftUI's form keeps it (measured,
/// `Tools/SwiftUIProbes/Form rows`).
@MainActor extension ContextMenuModifier: FormRowRewrapping {
    package var formRowContent: Content { content }

    package func rewrappingFormRow<V: View>(_ row: V) -> any View {
        // The route is a type of each specialisation's own, so it is spelled
        // again for the new one.
        let route: ContextMenuModifier<V, MenuItems>.KeyboardRoute =
            switch keyboardRoute {
            case .ownStop: .ownStop
            case .contentStops: .contentStops
            case .contentStopRegions: .contentStopRegions
            }
        return ContextMenuModifier<V, MenuItems>(
            content: row, menuItems: menuItems, keyboardRoute: route, answersControlReturn: answersControlReturn)
    }
}

/// StateStorage property indices for ``ContextMenuModifier``. A free enum because
/// the modifier is generic (which can't hold static stored properties).
private enum StateIndex {
    static let state = 0
    static let focusID = 1
}

// MARK: - Renderable

@MainActor extension ContextMenuModifier: Renderable {
    package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let sectionID = "contextmenu-\(context.identity.path)"
        // Its own child identity, so the content's / menu's @State never collides
        // with this modifier's state slot (mirrors AlertPresentationModifier).
        let contentContext = context.withChildIdentity(type: Content.self, index: 0)

        // In a row of a list or table with a selection menu, that menu answers
        // every secondary click — as on macOS — so this one adds nothing: no
        // trigger, no focus stop, no Shift+F10 of its own.
        guard let stateStorage = context.stateStorage,
            !context.environment.rowsYieldSecondaryClick
        else {
            return TUIView.renderToBuffer(content, context: contentContext)
        }
        let stateBox: StateBox<ContextMenuState> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.state),
            default: ContextMenuState())
        let state = stateBox.value
        // Keep the box alive across the run loop's per-frame StateStorage GC.
        if !context.isMeasuring { stateStorage.markActive(context.identity) }

        // CLOSED: render the content live and attach the right-click trigger. Tear
        // down a section left over from a just-dismissed menu so the page's focus
        // / scroll is restored rather than jumping.
        guard state.isOpen else {
            // The keyboard trigger runs FIRST, because it is what registers the
            // focus stop — and the content has to be told whether that stop
            // holds the focus before it draws itself. Nobody else can say so:
            // the focusable thing here is the caller's own view, so only the
            // caller can decide what part of it shows the focus (see
            // `EnvironmentValues.isFocused`).
            var contentContext = contentContext
            var isFocused: Bool?
            var focusID: String?
            if !context.isMeasuring {
                // Tearing down the section a closed menu left behind is a side
                // effect no memo can make again, and only the first closed frame
                // after a menu has one. Every other closed frame registers only
                // what a memo replays — the focus stop, the Shift+F10 handler,
                // the click trigger — so a row carrying a context menu can be
                // served rather than composed on every frame. It never was: the
                // side effect was declared on every frame, so a list of
                // documents each with a menu served no row at all.
                if state.needsSectionTeardown {
                    context.environment.volatileReadTracker?.recordRenderSideEffect()
                    context.environment.focusManager?.deactivateSection(id: sectionID)
                    state.needsSectionTeardown = false
                }
                // In a list row the list is the stop, and its Shift+F10 opens
                // the cursor row's menu: the row reports it rather than being a
                // stop of its own ahead of, or among, the list's rows.
                if keyboardRoute == .ownStop, !reportsToListRow(stateBox: stateBox, context: context) {
                    focusID = attachKeyboardTrigger(stateBox: stateBox, context: context)
                    isFocused = focusID.map { FocusRegistration.isFocused(context: context, focusID: $0) } ?? false
                }
            }
            // Published the way `.focusable()` publishes it, so a memo inside
            // the content sees the change; the bare assignment this replaced
            // served the unfocused frame after Tab arrived.
            FocusRegistration.publishIsFocused(isFocused, context: context, into: &contentContext)
            var buffer = TUIView.renderToBuffer(content, context: contentContext)
            context.noteDepartureDrawnWhole(of: Content.self, at: contentContext.identity, by: Self.self)
            if !context.isMeasuring, keyboardRoute != .ownStop {
                attachContentStopsTrigger(stateBox: stateBox, regions: buffer.hitTestRegions, context: context)
            }
            if !context.isMeasuring, keyboardRoute == .contentStopRegions {
                if context.environment.isEnabled {
                    ContextMenuPresentation.attachTriggerOverStops(to: &buffer, stateBox: stateBox, context: context)
                }
            } else if !context.isMeasuring, keyboardRoute == .ownStop || context.environment.isEnabled {
                ContextMenuPresentation.attachTrigger(
                    to: &buffer, stateBox: stateBox, focusID: focusID, context: context)
            }
            return buffer
        }
        if !context.isMeasuring { state.needsSectionTeardown = true }

        // OPEN: render the content beneath as an inert backdrop (isolated from
        // focus / key / state) so its controls can't steal the menu's focus. NOT
        // dimmed — a context menu is a popover, not a modal.
        // Noted here too, though nothing is published: the backdrop inherits
        // its `\.isFocused`, and a slot left unvisited while the menu is up is
        // pruned — so it would come back `.first` when the menu closes and the
        // stop takes the focus back, a change nothing would clear.
        var backdropContext = contentContext
        FocusRegistration.publishIsFocused(nil, context: context, into: &backdropContext)
        var baseBuffer = TUIView.renderToBuffer(
            content, context: backdropContext.isolatedForBackground())
        ContextMenuPresentation.present(
            menuItems, over: &baseBuffer, stateBox: stateBox, sectionID: sectionID, context: context)
        return baseBuffer
    }

    /// Reports this menu to the list row it is in, if it is in one, for the
    /// list's Shift+F10 to open on that row (`RowEditRestrictions.rowMenus`),
    /// and answers whether it did: then the content is no focus stop of its
    /// own. Replayable, as the focus stop it stands in for is, so a row served
    /// from a memo reports it again.
    private func reportsToListRow(stateBox: StateBox<ContextMenuState>, context: RenderContext) -> Bool {
        guard let restrictions = context.environment.listRowEditRestrictions, restrictions.currentRowIndex != nil
        else { return false }
        guard context.environment.isEnabled else { return true }
        let onOpen = context.environment.menuOpenAction
        RowMenuReporter.report(stateBox: stateBox, onOpen: onOpen, context: context)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        if let journal = context.recordingEffectJournal {
            journal.append(
                EffectJournal.Entry(kind: RowMenuReporter.kind, channelToken: context.environment.keyChannelToken) { replay in
                    RowMenuReporter.report(stateBox: stateBox, onOpen: onOpen, context: replay)
                })
        }
        return true
    }

    /// Makes the content a focus stop and opens the menu on **Shift+F10** while
    /// it holds focus — the keyboard route to a menu that otherwise only a
    /// right-click can reach.
    ///
    /// Shift+F10 because it is the one binding every platform with a keyboard
    /// context-menu route agrees on (Windows, GTK, every browser); macOS has no
    /// native equivalent, and a Mac keyboard has no Menu key to offer instead.
    /// It arrives as `ESC[21;2~` in iTerm2, Ghostty, Warp and xterm. Apple
    /// Terminal has no modifier encoding for function keys and sends `ESC[32~`
    /// (its alias for F18) instead; `Terminal.finalize` normalises that back to
    /// Shift+F10 — see `Documentation/Terminals/Terminal compatibility survey.md`. A PC
    /// keyboard's Menu key does the same where the terminal reports it
    /// (``Key/menu``: under the kitty keyboard protocol only).
    ///
    /// The focus stop is the price of the feature: you cannot key a menu open on
    /// a view you cannot reach. It consumes no keys of its own
    /// (`triggerKeys: []`), so content that is already interactive keeps every
    /// binding it had.
    ///
    /// - Returns: The focus stop's id, or `nil` where none was registered (no
    ///   focus manager, or the content is disabled).
    @discardableResult
    private func attachKeyboardTrigger(stateBox: StateBox<ContextMenuState>, context: RenderContext) -> String? {
        guard context.environment.focusManager != nil, context.environment.isEnabled else {
            return nil
        }
        let onOpen = context.environment.menuOpenAction
        let focusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: nil,
            defaultPrefix: "contextmenu-target", propertyIndex: StateIndex.focusID)
        FocusRegistration.register(
            context: context,
            handler: ActionHandler(focusID: focusID, action: {}, triggerKeys: []),
            focusID: focusID)

        registerOpenKey(stateBox: stateBox, focusIDs: [focusID], onOpen: onOpen, context: context)
        return focusID
    }

    /// Opens the menu on **Shift+F10** while one of the focus stops the
    /// content just registered holds the focus — ``KeyboardRoute/contentStops``.
    /// They are the ids its hit-test regions carry, which is how an enclosing
    /// `ScrollView` finds them too. Content with none has no keyboard route to
    /// the menu, as it has none to anything else.
    private func attachContentStopsTrigger(
        stateBox: StateBox<ContextMenuState>, regions: [HitTestRegion], context: RenderContext
    ) {
        guard context.environment.focusManager != nil, context.environment.isEnabled else { return }
        var focusIDs: [String] = []
        for case let focusID? in regions.map(\.focusID) where !focusIDs.contains(focusID) {
            focusIDs.append(focusID)
        }
        guard !focusIDs.isEmpty else { return }
        registerOpenKey(
            stateBox: stateBox, focusIDs: focusIDs, onOpen: context.environment.menuOpenAction, context: context)
    }

    /// Registers the Shift+F10 handler for `focusIDs`. Replayable, as
    /// `onKeyEvent`'s is: a memo serving the content makes the registration
    /// again from its journal, in the section it was made in.
    private func registerOpenKey(
        stateBox: StateBox<ContextMenuState>, focusIDs: [String], onOpen: MenuOpenAction?, context: RenderContext
    ) {
        let sectionID = context.environment.activeFocusSectionID
        let answersControlReturn = answersControlReturn
        ContextMenuKeyRegistrar.register(
            stateBox: stateBox, focusIDs: focusIDs, onOpen: onOpen, answersControlReturn: answersControlReturn,
            sectionID: sectionID, context: context)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        if let journal = context.recordingEffectJournal {
            journal.append(
                EffectJournal.Entry(
                    kind: ContextMenuKeyRegistrar.kind, channelToken: context.environment.keyChannelToken
                ) { replay in
                    ContextMenuKeyRegistrar.register(
                        stateBox: stateBox, focusIDs: focusIDs, onOpen: onOpen,
                        answersControlReturn: answersControlReturn, sectionID: sectionID, context: replay)
                })
        }
    }
}

/// A list row's context menu reported to its list, shared by the live render
/// and by a memo replaying it.
@MainActor
private enum RowMenuReporter {
    /// The journal kind of the report.
    static let kind = EffectJournal.Kind("contextMenu.listRow")

    /// Reports the menu in `stateBox` to the list row `context` is drawing.
    static func report(stateBox: StateBox<ContextMenuState>, onOpen: MenuOpenAction?, context: RenderContext) {
        guard let restrictions = context.environment.listRowEditRestrictions,
            let row = restrictions.currentRowIndex
        else { return }
        restrictions.reportRowMenu(row: row) {
            ContextMenuPresentation.openFromKeyboard(stateBox, onOpen: onOpen)
        }
    }
}

/// The Shift+F10 handler a closed context menu registers, shared by the live
/// render and by a value memo replaying it — see `EffectJournal`.
@MainActor
private enum ContextMenuKeyRegistrar {
    /// The journal kind of the registration.
    static let kind = EffectJournal.Kind("contextMenu.openKey")

    /// Adds the handler that opens the menu on Shift+F10 — and on Ctrl-Return
    /// as itself, where `answersControlReturn` — while one of `focusIDs` holds
    /// the focus, to `context`'s key dispatcher in `sectionID`. It looks the dispatcher and the focus manager up in
    /// `context`, so a replay registers into, and asks, the services of the
    /// frame that serves it.
    static func register(
        stateBox: StateBox<ContextMenuState>, focusIDs: [String], onOpen: MenuOpenAction?,
        answersControlReturn: Bool, sectionID: String?, context: RenderContext
    ) {
        // The focus manager, weakly, and not the context: the key dispatcher
        // holds this handler, and the context holds the key dispatcher — kept
        // here, it kept the app's state, cache, managers and dispatchers alive
        // after its loop (scroll lane review 3).
        let focusManager = context.environment.focusManager
        context.environment.keyEventDispatcher!.addHandler(sectionID: sectionID) { [weak focusManager] event in
            guard event.opensContextMenu || (answersControlReturn && event.isControlReturn), let focusManager,
                focusIDs.contains(where: { focusManager.isFocused(id: $0) })
            else { return false }
            // Opened from the keyboard, which has no other way to point at a
            // row: on the first item, written back through the box (see
            // `ContextMenuPresentation.attachTrigger`). The write is not
            // load-bearing today: the row that holds the focus is never stored,
            // its focus registration declaring itself a side effect — it keeps
            // the menu opening if that ever changes.
            ContextMenuPresentation.openFromKeyboard(stateBox, onOpen: onOpen)
            return true
        }
    }
}

// MARK: - Layoutable

@MainActor extension ContextMenuModifier: Layoutable {
    /// The menu is presented *over* the content, so the layout footprint is just
    /// the content — and forwarding keeps the focus-section / trigger side effects
    /// on the render pass, never a measure.
    package func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // One environment application deeper, as `publishIsFocused` makes the
        // render walk's — by hand, because a measure must not note.
        var contentContext = context.withChildIdentity(type: Content.self, index: 0)
        contentContext.environmentApplicationDepth += 1
        return measureChild(content, proposal: proposal, context: contentContext)
    }
}
