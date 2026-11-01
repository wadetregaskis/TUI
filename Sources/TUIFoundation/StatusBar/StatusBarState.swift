//  🖥️ TUI — A Terminal UI framework for Swift
//  StatusBarState.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Quit Behavior

/// Controls when the quit shortcut (Control-Q by default) is active.
public enum QuitBehavior: Sendable {
    /// Quit works from any screen.
    ///
    /// Pressing `q` will always exit the application, regardless of
    /// the current navigation state.
    case always

    /// Quit only works from the root/main screen.
    ///
    /// Pressing `q` will only exit when no context is pushed onto the
    /// status bar stack. On subpages, `q` does nothing, allowing the
    /// app to handle navigation (e.g., ESC to go back).
    case rootOnly
}

// MARK: - Status Bar State

/// Manages the status bar state for the running application.
///
/// This class is created by the `AppRunner` and injected into the
/// environment for views to access.
///
/// # Usage
///
/// ```swift
/// // In renderToBuffer(context:):
/// let statusBar = context.environment.statusBar
/// statusBar.setItems([
///     StatusBarItem(shortcut: "⎋", label: "cancel")
/// ])
/// ```
public final class StatusBarState: @unchecked Sendable {
    // MARK: - Render Invalidation

    /// The app state used to trigger re-renders when status bar items change.
    private let appState: AppState

    // MARK: - User Items

    /// Stack of user contexts with their items (legacy push/pop API).
    private var userContextStack: [(context: String, items: [any StatusBarItemProtocol])] = []

    /// Global user items that are always shown (lowest priority).
    private var userGlobalItems: [any StatusBarItemProtocol] = []

    /// Global items a `.statusBarItems` modifier declared during THIS render
    /// pass, cleared at the start of every one.
    ///
    /// Kept apart from ``userGlobalItems``, which an app sets imperatively and
    /// expects to persist. A declaration in the view tree is only true while
    /// the view is in the tree, and the tree is rebuilt every frame — so items
    /// declared by a page that has gone away have to go with it. They did not:
    /// pressing Escape back to the Example's menu left every shortcut of the
    /// page just left sitting on the bar, because the modifier wrote straight
    /// into `userGlobalItems` and nothing ever cleared it.
    ///
    /// (Section items were already right — ``registerSectionItems`` is cleared
    /// per pass, and has been since the modifier's own comment was written. It
    /// is the branch for a page NOT inside a `.focusSection()` that leaked, and
    /// that is the common one.)
    private var declaredGlobalItems: [any StatusBarItemProtocol] = []

    /// The global items in force: this pass's declaration when there is one,
    /// and the app's own standing set otherwise.
    ///
    /// Precedence rather than a merge, because that is what the modifier did
    /// when it wrote into the same property — it replaced.
    private var globalItems: [any StatusBarItemProtocol] {
        declaredGlobalItems.isEmpty ? userGlobalItems : declaredGlobalItems
    }

    // MARK: - Section Items (Declarative API)

    /// Items registered per focus section during rendering.
    ///
    /// Each entry maps a section ID to its declared items and composition strategy.
    /// Rebuilt every render pass by ``StatusBarItemsModifier``.
    private var sectionItems:
        [(sectionID: String, items: [any StatusBarItemProtocol], composition: StatusBarItemComposition, serial: Int)] =
            []

    /// How many section registrations have been made, ever: each one's
    /// `serial`, which ``replaceSectionItems(registeredAs:with:)`` finds it by.
    private var sectionRegistrations = 0

    /// The focus manager used to determine the active section.
    ///
    /// Set by `RenderLoop` at the start of each render pass.
    package var focusManager: FocusManager? { get { _focusManager } set { _focusManager = newValue } }

    /// ``focusManager``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private weak var _focusManager: FocusManager?

    /// The ID of the currently active focus section, read from the FocusManager.
    private var activeFocusSectionID: String? {
        focusManager?.activeSectionIdentifier
    }

    // MARK: - System Items Configuration

    /// Whether system items are shown at all.
    ///
    /// Set to `false` to hide all system items (quit, help, theme).
    /// Default is `true`.
    public var showSystemItems: Bool = true

    /// Whether the appearance item (`a`) is shown, and the key live.
    ///
    /// When `true`, pressing `a` cycles through available appearances (border
    /// styles). Default is `false`, and then `a` is an ordinary key: an app
    /// opts into the built-in appearance cycling, as into theme cycling.
    public var showAppearanceItem: Bool = false

    /// Whether the theme item (`t`) is shown, and the key live.
    ///
    /// When `true`, pressing `t` cycles through available themes.
    /// Default is `false`, and then `t` is an ordinary key.
    public var showThemeItem: Bool = false

    /// Whether the bar shows "undo" while the app's undo manager has a step to
    /// undo, and "redo" while it has one to redo; a click performs it.
    ///
    /// On by default. Undo's key, Ctrl-minus, reaches the app on every
    /// terminal, but redo's reach only some (see
    /// ``EnvironmentValues/undoManager``), and on the rest these items are the
    /// way to it. ``TextField`` and ``TextEditor`` register their edits with
    /// the app's undo manager, so an app with either shows "undo" once the
    /// user has typed in it. An app that shows its own undo affordance can
    /// turn them off.
    public var showUndoItems: Bool = true

    /// The app's undo manager, whose undo and redo the bar offers; set by the
    /// run loop.
    package var undoManager: UndoManager? { get { _undoManager } set { _undoManager = newValue } }

    /// ``undoManager``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _undoManager: UndoManager?

    /// The app's undo and redo keys, which decide the key the bar names
    /// beside each: the first the terminal can deliver (``UndoShortcuts``'s
    /// hint). Set by the run loop with ``undoManager``.
    package var undoKeys: AppUndoKeys { get { _undoKeys } set { _undoKeys = newValue } }

    /// ``undoKeys``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _undoKeys = AppUndoKeys()

    /// Whether the bar carries an Escape entry when something claims the key.
    ///
    /// Return and Escape are the two keys common enough — and special
    /// enough — to be worth a permanent place, so both are on by default. An
    /// app that wants the space back turns them off with
    /// ``View/statusBarSystemItems(theme:appearance:returnKey:escapeKey:)``.
    ///
    /// Presence only. Turning this off changes nothing about what the key
    /// DOES: the claim that labels the entry is also what routes Escape to the
    /// surface that claimed it, and that is independent of whether the bar
    /// shows anything.
    public var showEscapeItem: Bool = true

    /// Whether the bar carries a Return entry when something claims the key.
    /// See ``showEscapeItem``.
    public var showReturnItem: Bool = true

    /// Controls when the quit shortcut is active.
    ///
    /// - `.always`: Quit works from any screen (default).
    /// - `.rootOnly`: Quit only works when no context is pushed (main screen).
    ///
    /// When set to `.rootOnly`, pressing the quit key on a subpage does nothing,
    /// allowing the app to handle navigation (e.g., go back) instead.
    public var quitBehavior: QuitBehavior = .always

    /// Whether a presentation on screen this frame asked that the app not be
    /// quit — `presentationPreventsAppTermination(true)` on a sheet's content,
    /// `dialogPreventsAppTermination(true)` on an alert. Set by the presenter
    /// as it draws, and cleared before every walk, so dismissing it lifts it.
    private(set) var quitIsPrevented = false

    /// Records that a presentation drawn this frame prevents quitting.
    package func preventQuit() {
        quitIsPrevented = true
    }

    /// What asks before the quit key quits — a top-level
    /// `dismissalConfirmationDialog` whose `shouldPresent` held this frame.
    /// Cleared before every walk, like ``quitIsPrevented``.
    private var quitQuestion: ((@escaping () -> Void) -> Void)?

    /// Whether something on screen has asked to be asked before a quit.
    package var asksBeforeQuit: Bool { quitQuestion != nil }

    /// Whether what is on screen holds the quit key, a dialog's question among
    /// them.
    package var holdsQuit: Bool { quitIsPrevented }

    /// Has the quit key ask `question` first, this frame.
    package func askBeforeQuitting(_ question: @escaping (@escaping () -> Void) -> Void) {
        quitQuestion = question
    }

    /// Quits — or asks first, if something on screen asked to be asked.
    package func requestQuit(_ quit: @escaping () -> Void) {
        if let quitQuestion {
            quitQuestion(quit)
        } else {
            quit()
        }
    }

    /// The keyboard shortcut used to quit the application.
    ///
    /// Defaults to `.ctrlQ` (pressing Control-Q quits). Change this to use a different key:
    ///
    /// ```swift
    /// statusBar.quitShortcut = .escape   // ⎋ quit
    /// statusBar.quitShortcut = .q        // q quit, where nothing is typed
    /// ```
    ///
    /// The status bar display updates automatically.
    public var quitShortcut: QuitShortcut = .ctrlQ

    // MARK: - Appearance

    /// The horizontal alignment of items.
    public var alignment: StatusBarAlignment = .justified

    /// The color for shortcut keys, or `nil` (the default) for the palette's
    /// accent.
    ///
    /// Resolved against the palette each time the bar is drawn, so a palette role
    /// follows a change of theme. Any colour set here is drawn as set.
    public var highlightColor: Color?

    /// The color for labels, or `nil` (the default) for the palette's foreground.
    ///
    /// Resolved against the palette each time the bar is drawn, like
    /// ``highlightColor``.
    public var labelColor: Color?

    // MARK: - Transient Modal Overrides

    /// While non-nil, any rendered status-bar item bound to the escape key
    /// (an item whose shortcut is ``Shortcut/escape``) displays this label
    /// in place of its declared one.
    ///
    /// Useful for transient modes — an open drop-down menu, an inline
    /// editor — where ESC should still fire the same handler the page set
    /// up (`back`, `cancel`, …) but the user should be told that *right
    /// now* the key closes the transient surface.
    ///
    /// Setting it is a CLAIM on Escape for the frame, by whatever renders it
    /// — the latest claim stands, and each is a new one, however it is
    /// labelled (`claimEscape(_:)`). Clearing it (set to nil) withdraws the
    /// claim and restores the underlying item label.
    ///
    /// Where a live sheet is docked under the page, each pane — the page, the
    /// sheet — has a claim of its own: one is made in the pane rendering it,
    /// and what this reads is the claim of the pane the focus is in
    /// (`activeEscapeClaim`). A `NavigationStack` in the sheet does not take
    /// Escape from the page while the focus is on the page.
    public var escapeLabelOverride: String? {
        get { activeEscapeClaim?.label }
        set {
            if let newValue { claimEscape(newValue) } else { withdrawEscapeClaim() }
        }
    }

    /// Whether the surface that claimed ESC (``escapeLabelOverride``) is an
    /// input-grabbing transient surface — an open drop-down menu, a
    /// suggestions pop-up — whose presence should also suppress the global
    /// app-chrome shortcuts (theme/appearance cycling), exactly like a modal.
    ///
    /// `true` (the default, and every new claim's) preserves that modal
    /// behaviour. A lightweight claim — a multi-selection list offering ESC
    /// to clear its selection — sets this `false`: only the ESC key itself is
    /// re-routed, everything else behaves normally.
    ///
    /// Set after the label, it changes the claim the label made. Set before
    /// it — while no claim stands where it is set — it is kept for the claim
    /// made there next this frame, and for that claim only: the claim after
    /// it grabs the input again unless it says otherwise, and a claim
    /// withdrawn meanwhile takes the kept flag with it.
    public var escapeClaimGrabsInput: Bool {
        get { activeEscapeClaim?.grabsInput ?? true }
        set {
            if hasEscapeClaimHere {
                updateEscapeClaimHere { $0.grabsInput = newValue }
            } else {
                pendingEscapeClaimFlag = PendingEscapeClaimFlag(
                    pane: focusManager?.currentPaneID, grabsInput: newValue)
            }
        }
    }

    /// ``escapeClaimGrabsInput`` as it was set while no claim stood where it
    /// was set, for the next claim made there this frame
    /// (`claimEscape(_:)`).
    var pendingEscapeClaimFlag: PendingEscapeClaimFlag?

    /// What the bar calls Escape where nothing has claimed it this walk: named
    /// by a surface that takes the key at the lowest priority before its
    /// content draws — a window opened over another, which Escape closes —
    /// for a bar drawn before the surface can know whether anything in it
    /// claims the key. A claim made later names the key instead
    /// (``escapeLabelOverride``). Emptied before each walk.
    package var escapeFallbackLabel: String?

    /// The page's claim on Escape this frame — made outside every pane — if
    /// anything has made one: see ``EscapeClaim``.
    var escapeClaim: EscapeClaim?

    /// Each pane's claim on Escape this frame, by the pane.
    var paneEscapeClaims: [String: EscapeClaim] = [:]

    /// The token the next claim on Escape is made with. Never reused, so a
    /// token kept from an earlier claim — or an earlier frame — names that
    /// claim and no other.
    var nextEscapeClaimToken = 0

    /// Whether item ACTIONS are suppressed for this frame — set, alongside
    /// ``escapeLabelOverride``, by an open transient surface that does NOT
    /// switch the active focus section (the Picker drop-down): the items on
    /// the bar still describe the page BEHIND the surface, and firing them
    /// under it is how typing a lettered shortcut over an open drop-down
    /// navigated the page out from under it. Surfaces that switch sections
    /// (modals, popovers) never need this — the section switch already swaps
    /// the bar's items for their own. Reset every frame with the override.
    public var itemActionsSuppressed = false

    /// What Return would do to whatever holds the focus right now, or `nil`
    /// when nothing has said.
    ///
    /// The Return counterpart of ``escapeLabelOverride``, and it exists for the
    /// same reason: a page declares one item for the key and the key means
    /// something different depending on what is focused. "show" is right over
    /// the row that opens a dialog and wrong over the toggle beside it, and the
    /// page cannot know which is which.
    ///
    /// Published by the focused control each render (see
    /// `FocusRegistration.publishActivationLabel(_:context:isFocused:)`) and
    /// cleared at the top of every frame, so a control that lost the focus
    /// never leaves its verb behind. A control that does nothing with Return —
    /// a slider, a stepper — publishes nothing, and the page's own label
    /// stands.
    public var activationLabelOverride: String?

    /// The `id` of the status-bar item the mouse cursor is
    /// currently hovering over, or `nil` if the cursor isn't on
    /// any item.
    ///
    /// Flipped by `_StatusBarCore`'s per-item mouse handler in
    /// response to the dispatcher's synthetic `.entered` /
    /// `.exited` events. The renderer reads it to apply a
    /// hover-bumped tint on the matching item.
    public var hoveredItemID: String?

    /// Creates a new status bar state.
    ///
    /// - Parameter appState: The app state instance for triggering re-renders.
    public init(appState: AppState) {
        self.appState = appState
    }

    /// Creates a status bar state with a default `AppState` instance.
    ///
    /// Used for environment key defaults and testing only.
    internal convenience init() {
        self.init(appState: AppState())
    }

    /// Whether we are at the root level (no context pushed).
    public var isAtRoot: Bool {
        userContextStack.isEmpty
    }

    /// Whether quit is currently allowed based on `quitBehavior`.
    public var isQuitAllowed: Bool {
        if quitIsPrevented { return false }
        switch quitBehavior {
        case .always: return true
        case .rootOnly: return isAtRoot
        }
    }

    /// The current system items based on configuration flags — but the bare
    /// keys a focused type select takes (`typeSelectHoldsTypedKeys`).
    public var currentSystemItems: [StatusBarItem] {
        let items = allSystemItems
        guard items.contains(where: Self.namesTypedKey) else { return items }
        return typeSelectHoldsTypedKeys ? items.filter { !Self.namesTypedKey($0) } : items
    }

    /// The system items the configuration flags call for.
    private var allSystemItems: [StatusBarItem] {
        guard showSystemItems else { return [] }

        var items: [StatusBarItem] = []
        if isQuitAllowed {
            // Localize the displayed quit label only when it's the framework
            // default; a custom `QuitShortcut` (e.g. label "exit") keeps its
            // own label verbatim. Resolving here (not at construction) means a
            // runtime language switch re-localizes it live.
            let quitLabel = quitShortcut.label == QuitShortcut.ctrlQ.label
                ? LocalizationService.shared.string(for: LocalizationKey.StatusBar.quit)
                : quitShortcut.label
            items.append(
                StatusBarItem(
                    shortcut: quitShortcut.shortcutSymbol,
                    label: quitLabel,
                    order: .quit
                )
            )
        }
        if showAppearanceItem { items.append(SystemStatusBarItem.appearance) }
        if showThemeItem { items.append(SystemStatusBarItem.theme) }
        // The two common keys appear only while something has said what they
        // do this frame — a focused control's verb, a presented surface's
        // claim. Nothing said, nothing shown: an entry for a key that will not
        // be handled is worse than no entry, and the bar cannot tell what an
        // undeclared `onKeyEvent` closure would do with the key.
        //
        // A page that publishes its OWN escape or return item wins the shortcut
        // dedup below and keeps its action; these are the fallback for a page
        // that has not.
        if showEscapeItem, let label = escapeLabelOverride ?? escapeFallbackLabel {
            items.append(SystemStatusBarItem.escape(label: label))
        }
        if showReturnItem, let label = activationLabelOverride {
            items.append(SystemStatusBarItem.returnKey(label: label))
        }
        if showUndoItems, let undoManager { items += undoItems(undoManager) }
        return items
    }

    /// "undo" and "redo", each while the undo manager has a step for it, each
    /// performing it when clicked, and each naming the first of its keys the
    /// terminal can deliver (none where it can deliver none). They name the
    /// key and do not bind it (`StatusBarItem(id:naming:…)`): the keys stay
    /// the input chain's default bindings (``UndoShortcuts``), behind the
    /// focused control and an app's own shortcuts, and never match here. Read
    /// as a shortcut, the name bound a bare key at layer 1 — an Option-← undo
    /// key made a plain ← undo, and a bare `u` undid ahead of every view
    /// while there was a step and reached them while there was not — until
    /// the 2026-10-05 review.
    ///
    /// Each has an identity of its own, not its key's name: two commands
    /// with no deliverable key both name none, and shared the hover.
    ///
    /// The bar is not isolated to the main actor, though it only ever runs
    /// there; `UndoManager` is.
    private func undoItems(_ undoManager: UndoManager) -> [StatusBarItem] {
        let reference = MainActorUndoManager(undoManager)
        let (canUndo, canRedo) = MainActor.assumeIsolated { (reference.manager.canUndo, reference.manager.canRedo) }
        guard canUndo || canRedo else { return [] }
        let localization = LocalizationService.shared
        // The hint follows the focus: a text field's own ⌃Y yanks, so redo
        // is named by another of its keys while one has it (FB9-REDO).
        let focus = focusManager?.currentFocused as? any TextInputFocusHandler
        var items: [StatusBarItem] = []
        if canUndo {
            items.append(
                StatusBarItem(
                    id: Self.undoItemID, naming: undoKeys.hint(for: .undo, sparing: focus) ?? "",
                    label: localization.string(for: LocalizationKey.StatusBar.undo), order: .undo
                ) { _ = UndoCommand.undo.perform(on: undoManager) })
        }
        if canRedo {
            items.append(
                StatusBarItem(
                    id: Self.redoItemID, naming: undoKeys.hint(for: .redo, sparing: focus) ?? "",
                    label: localization.string(for: LocalizationKey.StatusBar.redo), order: .redo
                ) { _ = UndoCommand.redo.perform(on: undoManager) })
        }
        return items
    }

    /// The identities of the "undo" and "redo" items: no key's name, so they
    /// collide with no item that takes its identity from one.
    static let undoItemID = "statusbar.undo"

    /// See ``undoItemID``.
    static let redoItemID = "statusbar.redo"

    /// The current user items resolved from focus sections, context stack, or
    /// global items — but those whose bare key a focused type select takes
    /// (`typeSelectHoldsTypedKeys`).
    public var currentUserItems: [any StatusBarItemProtocol] {
        let items = resolvedUserItems
        guard items.contains(where: Self.bindsTypedKey) else { return items }
        return typeSelectHoldsTypedKeys ? items.filter { !Self.bindsTypedKey($0) } : items
    }

    /// The user items of the focus section, the context stack or the global
    /// set, whatever the focus is on.
    private var resolvedUserItems: [any StatusBarItemProtocol] {
        // Behind a modal only its own items show and fire, not the page's merged
        // under them: the dimming says the page is inert, and on a Mac a sheet's
        // window takes no key of the page's (decisions A-MODALS-1, 2026-10-27;
        // this undoes the merge of 2026-08-22). The system items still show.
        if let modal = focusManager?.activeModalSectionID {
            return sectionItems.first { $0.sectionID == modal }?.items ?? []
        }
        if !sectionItems.isEmpty, let activeSectionID = activeFocusSectionID {
            return resolvedSectionItems(for: activeSectionID)
        }
        if let topContext = userContextStack.last { return topContext.items }
        return globalItems
    }

    /// Whether the focused control takes every character type select takes —
    /// a list, a table, an open `Picker` drop-down — so that no bare-key
    /// binding hears one (the owner's ruling B77-KEYTIME, 2026-10-23).
    ///
    /// While it does, the bar leaves out what it would advertise for those
    /// keys and cannot fire: the user items with an action on one, which
    /// match at layer 1, ahead of the focused control, and so are left out
    /// of the items keys are matched against too; and TUI's own quit,
    /// appearance and theme items, whose keys are layer 4's, behind it. An
    /// item with no action stays: it may name a key an `onKeyEvent` handler
    /// takes, which comes before the focused control and still hears it.
    package var typeSelectHoldsTypedKeys: Bool {
        (focusManager?.currentFocused as? any TypeSelectingFocusHandler)?.takesTypedCharacters == true
    }

    /// Whether type select takes `key`, a bare character.
    package static func typeSelectTakes(_ key: Key?) -> Bool {
        guard case .character(let character)? = key else { return false }
        return TypeSelectBuffer.takes(KeyEvent(key: .character(character)))
    }

    /// Whether `item` is a user item that binds a key type select takes: one
    /// with an action, as only such an item fires at layer 1.
    private static func bindsTypedKey(_ item: any StatusBarItemProtocol) -> Bool {
        guard let item = item as? StatusBarItem, item.hasAction, item.matchesKeys else { return false }
        return typeSelectTakes(item.triggerKey)
    }

    /// Whether a system item names a key type select takes: `q`, `a`, `t`.
    private static func namesTypedKey(_ item: StatusBarItem) -> Bool {
        typeSelectTakes(item.triggerKey)
    }

    /// All currently active items for rendering and event handling.
    public var currentItems: [any StatusBarItemProtocol] {
        let userShortcuts = Set(currentUserItems.map { $0.shortcut })
        let filteredSystemItems = currentSystemItems.filter { !userShortcuts.contains($0.shortcut) }
        let sortedUserItems = currentUserItems.sorted { $0.order < $1.order }
        return sortedUserItems + filteredSystemItems
    }

    /// Whether the status bar has any items to display — counting those it
    /// leaves out while type select holds the focus
    /// (`typeSelectHoldsTypedKeys`), so the bar keeps its row as the focus
    /// moves into a list and out again, rather than the page jumping by a row
    /// each time.
    public var hasItems: Bool { !resolvedUserItems.isEmpty || !allSystemItems.isEmpty }

    /// Whether there are any user items (ignoring system items).
    public var hasUserItems: Bool { !currentUserItems.isEmpty }

    /// This frame's tooltip, wrapped to the bottom bar's content width — empty
    /// when no tooltip is showing or the showing one is a popover.
    ///
    /// Drawn by the window's chrome host at the top of the bottom bar, or as a
    /// bar of its own while there is none. Resolved by the run loop BEFORE the
    /// bar's rows are reserved, which is what makes the row cost one pass
    /// rather than two. That works because the tooltip's triggers all land
    /// between frames: a mouse event, a key press, and a scheduled wake for the
    /// hover delay. What the render publishes is the `.onHover` REGISTRATION;
    /// the invocation has already happened. (The one case that does lag a frame
    /// is a help string that changes while the pointer is stationary, which is
    /// not worth a second pass.)
    public package(set) var tooltipLines: [String] = []

    /// Whether this frame's ``tooltipLines`` are the line about a copy, shown
    /// in place of the items of the app's line of key hints
    /// (``StatusBar/init()``) for its few seconds rather than above them.
    ///
    /// A row added to the bottom bar is a row taken from the page, and a page
    /// laid out one row shorter moves — a `WindowGroup` centres its content —
    /// which would carry what was just copied out from under its highlight. In
    /// place of the items the bar keeps its height. The items' keys still work
    /// while it shows; only their labels are hidden. Set by the run loop with
    /// the lines, and only while the line drew a row of items the frame before
    /// (``lineShowsItems``): with none to stand in for, the note takes a row of
    /// its own, as a tooltip does.
    package var showsNoteInPlaceOfItems: Bool { get { _showsNoteInPlaceOfItems } set { _showsNoteInPlaceOfItems = newValue } }

    /// ``showsNoteInPlaceOfItems``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _showsNoteInPlaceOfItems = false

    /// The rows this frame adds to the bottom bar above its items: the
    /// ``tooltipLines``, or none while they are the line about a copy shown
    /// in place of the items (``showsNoteInPlaceOfItems``). Each is a row
    /// taken from the page.
    package var linesAboveItems: [String] { showsNoteInPlaceOfItems ? [] : tooltipLines }

    /// Whether the app's line of key hints (``StatusBar/init()``) drew a row of
    /// items this frame — the row a line about a copy can stand in for in the
    /// next. Recorded by the line as it draws; taken, and cleared, by the run
    /// loop as it resolves the next frame's rows.
    package var lineShowsItems: Bool { get { _lineShowsItems } set { _lineShowsItems = newValue } }

    /// ``lineShowsItems``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _lineShowsItems = false
}

// MARK: - Public API

extension StatusBarState {
    /// Sets the global user items. Triggers a re-render.
    public func setItems(_ items: [any StatusBarItemProtocol]) {
        userGlobalItems = items
        appState.setNeedsRender()
    }

    /// Sets the global user items using a builder. Triggers a re-render.
    public func setItems(@StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]) {
        userGlobalItems = builder()
        appState.setNeedsRender()
    }

    /// Pushes a new user context with its items onto the stack. Triggers a re-render.
    public func push(context: String, items: [any StatusBarItemProtocol]) {
        userContextStack.removeAll { $0.context == context }
        userContextStack.append((context, items))
        appState.setNeedsRender()
    }

    /// Pushes a new user context using a builder. Triggers a re-render.
    public func push(context: String, @StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]) {
        push(context: context, items: builder())
    }

    /// Pops a user context from the stack. Triggers a re-render.
    public func pop(context: String) {
        userContextStack.removeAll { $0.context == context }
        appState.setNeedsRender()
    }

    /// Clears all user contexts (keeps global user items and system items). Triggers a re-render.
    public func clearContexts() {
        userContextStack.removeAll()
        appState.setNeedsRender()
    }

    /// Clears all user items (global and contexts). System items remain.
    public func clearUserItems() {
        userContextStack.removeAll()
        userGlobalItems.removeAll()
        declaredGlobalItems.removeAll()
    }

    /// Clears everything including user items and hides system items.
    public func clear() {
        userContextStack.removeAll()
        userGlobalItems.removeAll()
        declaredGlobalItems.removeAll()
        showSystemItems = false
    }

    /// Handles a key event, checking if any current item matches.
    @discardableResult
    public func handleKeyEvent(_ event: KeyEvent) -> Bool {
        guard let item = item(taking: event) else { return false }
        // A held key's repeat, for an item that does not repeat, runs nothing
        // and is still taken: it reaches nothing below either
        // (`KeyboardShortcutRegistry.trigger(for:)`).
        if event.phase == .repeat, !item.repeats { return true }
        item.execute()
        return true
    }

    /// Whether an item would run for one of `events` — ``handleKeyEvent(_:)``'s
    /// rule, without running anything, the items gathered once for all of
    /// them. For the user's quit key, asked after every frame
    /// (`InputHandler.quitKeyBindings(byte:hostAliases:)`).
    ///
    /// Asked only about the quit key's Control chords, it does not gather
    /// the items at all: only a ``StatusBarItem`` runs (``item(taking:among:)``),
    /// and none takes a Control or Option chord
    /// (``StatusBarItem/mayMatch(_:)``). Gathering them — sets, sorts and
    /// filters of every item — after every frame cost each app something for
    /// an answer that could only be no.
    package func takesAny(of events: [KeyEvent]) -> Bool {
        guard !itemActionsSuppressed, events.contains(where: StatusBarItem.mayMatch) else { return false }
        let items = currentItems
        return events.contains { item(taking: $0, among: items) != nil }
    }

    /// The item ``handleKeyEvent(_:)`` runs for `event`: Layer 1's rule.
    private func item(taking event: KeyEvent, among items: [any StatusBarItemProtocol]? = nil) -> StatusBarItem? {
        // An open sectionless surface holds the keyboard: nothing on the bar
        // is its own, so nothing on the bar may fire. See
        // ``itemActionsSuppressed``; ESC still works via the pre-route.
        guard !itemActionsSuppressed else { return nil }
        // While a modal surface (open Picker drop-down, etc.) has claimed
        // ESC via ``escapeLabelOverride``, leave that key to the focus
        // dispatch chain so the surface's own handler actually fires —
        // otherwise a page-level "ESC: back" would close the page out
        // from under it. The label printed in the status bar already tells
        // the user what ESC does *right now*; here we make the behaviour
        // match.
        let escapeIsClaimedByModal = escapeLabelOverride != nil && event.key == .escape

        for item in items ?? currentItems where item.matches(event) {
            // Any item matching an Escape event IS an Escape binding —
            // whatever its display string. This used to compare the display
            // glyph (`item.shortcut == "⎋"`), so an item spelled differently
            // (`shortcut: "esc"` with an explicit `key: .escape`) fired out
            // from under the modal's claim.
            if escapeIsClaimedByModal {
                continue
            }
            if let statusBarItem = item as? StatusBarItem, statusBarItem.hasAction {
                return statusBarItem
            }
        }
        return nil
    }
}

// MARK: - Internal API

extension StatusBarState {
    /// Sets the global user items without triggering a re-render.
    package func setItemsSilently(_ items: [any StatusBarItemProtocol]) {
        declaredGlobalItems = items
    }

    /// Registers status bar items for a focus section, in place of any
    /// registered for it earlier this pass.
    ///
    /// - Returns: The registration's serial, for
    ///   ``keepPresentationItem(_:inSection:registeredAs:)``.
    @discardableResult
    package func registerSectionItems(
        sectionID: String,
        items: [any StatusBarItemProtocol],
        composition: StatusBarItemComposition
    ) -> Int {
        sectionRegistrations += 1
        sectionItems.removeAll { $0.sectionID == sectionID }
        sectionItems.append((sectionID, items, composition, sectionRegistrations))
        return sectionRegistrations
    }

    /// Keeps `item`, a presentation's own item — its Escape — among the
    /// items of its section `sectionID`, once the presentation's content has
    /// drawn and named it for what the key does now.
    ///
    /// - As the items of the registration `serial` names, where that is still
    ///   the section's: the presenter's own, made before its content drew.
    /// - Added to the section's registration otherwise — the content's, whose
    ///   `.statusBarItems` registered into the section the presentation
    ///   activated it in — unless an item of the content's binds the same
    ///   key, which then stands, as a child's item stands over its parent's.
    /// - Registered alone, merged with the items outside, where nothing is
    ///   registered in the section.
    ///
    /// The content's items are ADDED to the presentation's, never put in its
    /// place. Put in its place, the presentation's Escape item was gone
    /// whenever its content declared a status bar item of its own; the
    /// section's items merge with the items declared outside the
    /// presentation, which are live, and a page's "⎋ back" declared around
    /// the view presenting a sheet then answered Escape at the bar's layer —
    /// ahead of the presenter's own key handler — and took the page away from
    /// under the sheet.
    package func keepPresentationItem(
        _ item: any StatusBarItemProtocol, inSection sectionID: String, registeredAs serial: Int? = nil
    ) {
        if let serial, let index = sectionItems.firstIndex(where: { $0.serial == serial }) {
            sectionItems[index].items = [item]
            return
        }
        guard let index = sectionItems.firstIndex(where: { $0.sectionID == sectionID }) else {
            registerSectionItems(sectionID: sectionID, items: [item], composition: .merge)
            return
        }
        guard !sectionItems[index].items.contains(where: { $0.shortcut == item.shortcut }) else { return }
        sectionItems[index].items.append(item)
    }

    /// Holds Escape in `sectionID` without offering it
    /// (``SystemStatusBarItem/heldEscape``), kept among the section's items
    /// as ``keepPresentationItem(_:inSection:registeredAs:)`` keeps a
    /// presentation's: added to what the section's own content registered
    /// there — which an Escape item of its own keeps — or registered alone,
    /// merged with the items outside, whose Escape it displaces.
    package func holdEscape(inSection sectionID: String) {
        keepPresentationItem(SystemStatusBarItem.heldEscape, inSection: sectionID)
    }

    /// Drops everything the view tree declared last pass, at the start of the
    /// next one.
    ///
    /// Both kinds: a section's items and a page's global ones. Anything still
    /// in the tree re-declares itself as it renders; anything that left takes
    /// its shortcuts with it, which is the whole point.
    func beginRenderPass() {
        sectionItems.removeAll()
        declaredGlobalItems.removeAll()
        quitIsPrevented = false
        quitQuestion = nil
    }

    /// Everything a walk of the scene republishes, emptied before the walk:
    /// the items (``beginRenderPass()``) and the per-frame claims below.
    ///
    /// One method so the render loop and a headless renderer reset the same
    /// things.
    package func beginSceneRender() {
        beginRenderPass()
        // The transient escape-label override is published by whichever
        // open modal surface (Picker drop-down, etc.) renders in this
        // frame; clearing it here makes the default the absence of any
        // override, so a surface that disappeared on the previous frame
        // never leaves its stale label behind on the next page. The
        // grabs-input flag travels with it (modal by default; a list's
        // lightweight selection claim lowers it each frame it applies).
        escapeClaim = nil
        if !paneEscapeClaims.isEmpty { paneEscapeClaims.removeAll() }
        pendingEscapeClaimFlag = nil
        escapeFallbackLabel = nil
        itemActionsSuppressed = false
        // Same contract for the Return verb: published by whichever control
        // holds the focus this frame, so its absence has to be the default or a
        // control that lost the focus would leave its verb on the bar.
        activationLabelOverride = nil
    }

    /// Pushes a new user context without triggering a re-render.
    package func pushSilently(context: String, items: [any StatusBarItemProtocol]) {
        userContextStack.removeAll { $0.context == context }
        userContextStack.append((context, items))
    }
}

// MARK: - Private Helpers

extension StatusBarState {
    /// Resolves items for a given section using its composition strategy.
    fileprivate func resolvedSectionItems(for sectionID: String) -> [any StatusBarItemProtocol] {
        guard let entry = sectionItems.first(where: { $0.sectionID == sectionID }) else {
            return globalItems
        }

        switch entry.composition {
        case .replace:
            return entry.items
        case .merge:
            let sectionShortcuts = Set(entry.items.map { $0.shortcut })
            let filteredGlobal = globalItems.filter { !sectionShortcuts.contains($0.shortcut) }
            return entry.items + filteredGlobal
        }
    }
}

// MARK: - StatusBar Environment Key

/// Environment key for accessing the status bar state.
///
/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct StatusBarKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    @usableFromInline static let defaultValue: StatusBarState? = nil
}

/// Environment key for the app's own status bar state, which isolation never
/// replaces.
private struct AppStatusBarKey: EnvironmentKey {
    static let defaultValue: StatusBarState? = nil
}

extension EnvironmentValues {
    /// The status bar state for the current application.
    ///
    /// Use this to set status bar items from within your views:
    ///
    /// ```swift
    /// context.environment.statusBar?.setItems([
    ///     StatusBarItem(shortcut: "q", label: "quit")
    /// ])
    /// ```
    ///
    /// `nil` outside a running application. These are the app's own objects,
    /// created by `AppRunner` and published by `RenderLoop.buildEnvironment()`
    /// — so a bare `EnvironmentValues()` (a headless render, a test) has none,
    /// which is the truth. It used to hand out a SHARED instance instead, and
    /// every such render mutated the same object: two tests rendering sheets in
    /// parallel both registered their ESC item into it and read each other's
    /// back. The convention here is the one `focusManager` and
    /// `keyEventDispatcher` already follow — a runtime service is Optional, and
    /// absent means absent.
    @inlinable
    public var statusBar: StatusBarState? {
        get { self[StatusBarKey.self] }
        set { self[StatusBarKey.self] = newValue }
    }

    /// The app's own status bar state — the one the input handler dispatches
    /// keys from — which ``StatusBar``'s `init()` draws, wherever it is drawn.
    ///
    /// Not ``statusBar``, which is the channel a subtree DECLARES its items
    /// into: rendering the page beneath a modal as a backdrop, or a `.dimmed()`
    /// subtree, swaps that one for a throwaway (`isolatedForBackground()`), so
    /// what the page declares there neither shows nor fires. The line of key
    /// hints is not something the page declares but a view of what the app
    /// does with a key, and a `StatusBar()` placed by a `.toolbar` that a
    /// `.sheet` wraps is drawn in that backdrop's environment: reading the
    /// throwaway, it showed the page's `n new` over the sheet, not the sheet's
    /// `⎋ dismiss`, and a click on `n new` ran the page's action behind it.
    ///
    /// Set at the root by the render loop, with ``statusBar``, and replaced by
    /// nothing. `nil` outside a running app, where `StatusBar()` falls back to
    /// ``statusBar``.
    package var appStatusBar: StatusBarState? {
        get { self[AppStatusBarKey.self] }
        set { self[AppStatusBarKey.self] = newValue }
    }
}
