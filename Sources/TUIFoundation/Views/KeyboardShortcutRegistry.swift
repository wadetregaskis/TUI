//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcutRegistry.swift
//
//  The per-frame registry keyboard shortcuts register their actions in, the
//  claimable carrier `.keyboardShortcut` plants for a control, and the
//  environment entries that reach both. Split out of `KeyboardShortcut.swift`,
//  which had grown past the file-length guideline.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Registry

/// The per-frame registry of semantic shortcut actions.
///
/// Buttons carrying a ``KeyboardShortcut`` register their action here during
/// the render pass; ``InputHandler`` triggers the matching action when a
/// Return/Escape falls through the focused control. Cleared at the start of
/// every render pass, so only what's actually on screen can be triggered —
/// and when overlapping surfaces each register (a dialog over a page), the
/// LAST registration wins, which render order makes the topmost surface.
///
/// Below the app's shortcuts sits a tier of framework DEFAULTS
/// (``registerDefault(_:holdsFocus:action:)``), for shortcuts the framework
/// binds for itself, such as a split view's sidebar chord. Any app shortcut on
/// the same trigger beats a default whatever the registration order: under the
/// default `.commandKey(.control)`, SwiftUI's ⌃⌘S and an app's plain ⌘S are the
/// same ⌃S, and the app means its own. This is `RowShortcuts`' rule, "defaults
/// first, then the overrides on top".
///
/// A shortcut registered inside a PANE — a live sheet docked under the page,
/// whose content renders through `renderingPane(_:context:_:)` — is that
/// pane's: it fires while the focus is in the pane, and only then. The page's
/// own (registered outside every pane) fire while the focus is on the page;
/// while it is in a pane, a key equivalent the pane does not bind still
/// reaches the page's, as a key goes up a responder chain, but Return and
/// Escape — the default and cancel actions — are the pane's alone: a field in
/// the sheet that lets Return through must not press the page's default
/// button. A framework default is its pane's by the same rule. Where no pane
/// is drawn, nothing here changes.
///
/// `@unchecked Sendable` like its sibling per-frame services
/// (`MouseEventDispatcher`, `KeyEventDispatcher`): touched only from the
/// main run loop (render pass registration + input dispatch).
package final class KeyboardShortcutRegistry: @unchecked Sendable {
    /// An app shortcut's action, whether a held key's repeats run it again,
    /// and when in the frame it was registered (``registrationCount``).
    struct Entry {
        let repeats: Bool
        let action: () -> Void
        let serial: Int
        /// Where it was declared, which decides whether it fires while a modal
        /// holds the keyboard (``Scope``).
        var scope = Scope()
    }

    /// Where a shortcut was declared: the focus section. While a modal section
    /// holds the keyboard only the shortcuts declared in it fire, as nothing
    /// behind an app-modal alert does on macOS, and as neither a window's key
    /// equivalents nor its menu commands do behind its sheet (measured
    /// 2026-10-27, decisions A-MODALS-1). A shortcut declared outside the
    /// presenting view used to fire behind a sheet, though the dimming says the
    /// page is inert. (The menu bar's commands were already inert there: the
    /// menu bar is drawn as a backdrop under a modal, and registers nothing.)
    struct Scope {
        var section: String?

        /// Whether a shortcut of this scope fires while `modalSection` holds the
        /// keyboard (`nil`: no modal does).
        func fires(under modalSection: String?) -> Bool {
            guard let modalSection else { return true }
            return section == modalSection
        }
    }

    /// The app's shortcuts registered outside every pane.
    private var actions: [KeyboardShortcut.Trigger: Entry] = [:]

    /// The app's shortcuts registered inside each pane, by the pane.
    private var paneActions: [String: [KeyboardShortcut.Trigger: Entry]] = [:]

    /// The pane whose content is rendering now, if any: set around it by
    /// `renderingPane(_:context:_:)`, so what registers meanwhile is the
    /// pane's.
    package var currentPane: String? { get { _currentPane } set { _currentPane = newValue } }

    /// ``currentPane``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _currentPane: String?

    /// How many app shortcuts this frame has registered so far: a mark a
    /// presenter takes before its content renders, and hands back to
    /// ``entry(for:registeredAfter:)`` once it has.
    private(set) var registrationCount = 0

    /// A framework default, and whether the view that registered it held the
    /// focus.
    private struct Default {
        let holdsFocus: Bool
        let action: () -> Void
        var scope = Scope()
    }

    /// The framework defaults registered outside every pane, consulted only
    /// when no app shortcut has the trigger.
    private var defaults: [KeyboardShortcut.Trigger: Default] = [:]

    /// The framework defaults registered inside each pane, by the pane.
    private var paneDefaults: [String: [KeyboardShortcut.Trigger: Default]] = [:]

    /// Clears the frame's registrations (called from the render loop).
    package func beginRenderPass() {
        actions.removeAll(keepingCapacity: true)
        if !paneActions.isEmpty { paneActions.removeAll() }
        currentPane = nil
        defaults.removeAll(keepingCapacity: true)
        if !paneDefaults.isEmpty { paneDefaults.removeAll() }
        registrationCount = 0
    }

    /// Registers `action` for `shortcut`; the last registration in a frame wins
    /// — except over the window's own while the menu bar's commands register
    /// (``registeringCommands(_:)``).
    ///
    /// - Parameter repeats: Whether a held key's repeats run the action again.
    ///   A repeat is told from a press only where the terminal speaks the kitty
    ///   keyboard protocol; in a legacy encoding every repeat is a press and
    ///   runs it. A repeat that does not run it is still taken, so it reaches
    ///   nothing else: holding a button's shortcut never falls through to
    ///   whatever the key means further down.
    /// - Parameter commandChord: The shortcut as written, with its ⌘, where it
    ///   also fires on a real ⌘ (``KeyboardShortcut/commandChord(matching:)``):
    ///   the same action is registered on that trigger too. `nil` — the
    ///   default, and every shortcut's unless the app asked — registers
    ///   nothing more.
    func register(
        _ shortcut: KeyboardShortcut, commandChord: KeyboardShortcut? = nil, repeats: Bool = true,
        section: String? = nil, action: @escaping () -> Void
    ) {
        registrationCount += 1
        let entry = Entry(
            repeats: repeats, action: action, serial: registrationCount,
            scope: Scope(section: section))
        insert(entry, on: shortcut.trigger)
        if let commandChord { insert(entry, on: commandChord.trigger) }
    }

    /// Puts `entry` on `trigger`, in the pane rendering now or on the page —
    /// unless the menu bar's commands are registering and something already
    /// holds the trigger (``registeringCommands(_:)``).
    private func insert(_ entry: Entry, on trigger: KeyboardShortcut.Trigger) {
        if let currentPane {
            if registersCommands, paneActions[currentPane]?[trigger] != nil { return }
            paneActions[currentPane, default: [:]][trigger] = entry
        } else {
            if registersCommands, actions[trigger] != nil { return }
            actions[trigger] = entry
        }
    }

    /// Registers `action` for `shortcut`, which `KeyboardShortcut.resolved(commandKey:)`
    /// has resolved: for a framework command outside a view — a scene's
    /// `.keyboardShortcut` (TUIApp) — inside ``registeringCommands(_:)``,
    /// so the window's own shortcut on the key keeps it. A held key does not
    /// repeat it. `commandChord` is ``register(_:commandChord:repeats:action:)``'s.
    package func registerCommand(
        _ shortcut: KeyboardShortcut, commandChord: KeyboardShortcut? = nil, action: @escaping () -> Void
    ) {
        register(shortcut, commandChord: commandChord, repeats: false, action: action)
    }

    /// Whether what registers now is the menu bar's commands — see
    /// ``registeringCommands(_:)``.
    private var registersCommands = false

    /// Runs `body`, in which what registers is the menu bar's commands: a
    /// command's shortcut is registered unless the window's content already
    /// registered one on its trigger this frame, which keeps it.
    ///
    /// The menu bar's commands render after the content, so that a command
    /// reading the focused view's `@FocusedValue` reads this frame's, and
    /// "the last registration wins" would have handed every shared chord to
    /// the menu bar. AppKit documents the other order: a key equivalent goes
    /// to the key window's views first, and to the main menu only if none
    /// takes it (Cocoa Event Handling Guide, "The Path of Key Events").
    /// UNMEASURED in SwiftUI itself: the lane's probe
    /// (`Tools/SwiftUIProbes/The menu bar (O13)/menus.swift`) could not make its window key on this machine,
    /// and with no key window the menu took the key.
    package func registeringCommands<Result>(_ body: () -> Result) -> Result {
        let outer = registersCommands
        registersCommands = true
        defer { registersCommands = outer }
        return body()
    }

    /// What `shortcut` runs, and whether a held key repeats it, if its
    /// registration — the last this frame on its trigger — came after `mark`,
    /// a ``registrationCount`` taken earlier in the frame: a shortcut
    /// registered by whatever rendered in between, and not since overridden.
    ///
    /// How a presenter finds its content's cancel button
    /// (``DismissalGate/cancelButton``).
    ///
    /// Among the shortcuts of the pane rendering now (``currentPane``), or of
    /// the page outside every pane: a live sheet's content registers in its
    /// pane, and its presenter asks while the pane is still rendering.
    func entry(for shortcut: KeyboardShortcut, registeredAfter mark: Int) -> Entry? {
        let table = currentPane.map { paneActions[$0] ?? [:] } ?? actions
        guard let entry = table[shortcut.trigger], entry.serial > mark else { return nil }
        return entry
    }

    /// The app's shortcut on `trigger` that fires while the focus is in
    /// `activePane` (`nil`: on the page): the pane's own; else, for anything
    /// but Return and Escape, the page's — see the type's discussion.
    ///
    /// Not the page's while `reachesPage` is false: a modal presented from
    /// inside the pane — an alert over a live sheet — holds the keyboard, and
    /// the page behind it, live as it is, must not fire from under it.
    private func appEntry(
        for trigger: KeyboardShortcut.Trigger, activePane: String?, reachesPage: Bool = true,
        modalSection: String? = nil
    ) -> Entry? {
        Self.paneScoped(trigger, page: actions, panes: paneActions, activePane: activePane, reachesPage: reachesPage)
            .flatMap { $0.scope.fires(under: modalSection) ? $0 : nil }
    }

    /// The framework default on `trigger` that fires while the focus is in
    /// `activePane`, by the rule an app shortcut fires by (``appEntry``).
    ///
    /// The page's, from inside a pane, only where the page's app shortcuts
    /// reach: a split view on the page registers its sidebar chord as a
    /// default, and an alert opened in a live sheet must hold it as it holds
    /// the page's own ⌃N.
    private func defaultEntry(
        for trigger: KeyboardShortcut.Trigger, activePane: String?, reachesPage: Bool, modalSection: String?
    ) -> Default? {
        Self.paneScoped(trigger, page: defaults, panes: paneDefaults, activePane: activePane, reachesPage: reachesPage)
            .flatMap { $0.scope.fires(under: modalSection) ? $0 : nil }
    }

    /// What fires on `trigger` with the focus in `activePane` (`nil`: on the
    /// page), of what was registered on the `page` and in the `panes`: the
    /// pane's own; else, for anything but Return and Escape, the page's,
    /// where `reachesPage`.
    private static func paneScoped<Value>(
        _ trigger: KeyboardShortcut.Trigger, page: [KeyboardShortcut.Trigger: Value],
        panes: [String: [KeyboardShortcut.Trigger: Value]], activePane: String?, reachesPage: Bool
    ) -> Value? {
        guard let activePane else { return page[trigger] }
        if let value = panes[activePane]?[trigger] { return value }
        switch trigger {
        case .defaultAction, .cancelAction: return nil
        case .key: return reachesPage ? page[trigger] : nil
        }
    }

    /// Registers a framework default for `shortcut`, which fires only when no
    /// app shortcut has the same trigger, however the two were ordered.
    ///
    /// Among defaults on one trigger, one registered by a view that holds the
    /// focus (`holdsFocus`) beats one that does not, and otherwise the FIRST
    /// registration wins. First, not last as for app shortcuts, because a
    /// framework control registering after its content has rendered finishes
    /// after anything nested inside it: the innermost of several nested
    /// focus-holding views registers first.
    ///
    /// Like an app shortcut, a default registered inside a pane is the pane's
    /// (``currentPane``).
    package func registerDefault(
        _ shortcut: KeyboardShortcut, holdsFocus: Bool = false, section: String? = nil,
        action: @escaping () -> Void
    ) {
        let trigger = shortcut.trigger
        let existing = currentPane.map { paneDefaults[$0]?[trigger] } ?? defaults[trigger]
        if let existing, existing.holdsFocus || !holdsFocus { return }
        let entry = Default(
            holdsFocus: holdsFocus, action: action, scope: Scope(section: section))
        if let currentPane {
            paneDefaults[currentPane, default: [:]][trigger] = entry
        } else {
            defaults[trigger] = entry
        }
    }

    /// Runs the action matching a fallen-through key event, if any.
    ///
    /// Unmodified Return/Escape drive the two semantic roles; a character key
    /// drives a key equivalent whose modifiers match exactly what the terminal
    /// reported. Exactly, not "at least": a shortcut on plain "q" must not fire
    /// on Ctrl-Q. The event → trigger rule itself is
    /// ``KeyboardShortcut/trigger(for:)``, shared with the row-shortcut table.
    ///
    /// - Parameters:
    ///   - activePane: The pane the focus is in (`FocusManager.activePaneID`),
    ///     or `nil` on the page.
    ///   - reachesPage: Whether a key equivalent the pane does not bind may
    ///     reach the page's: not while a modal section holds the focus.
    ///   - modalSection: The modal section holding the keyboard
    ///     (`FocusManager.activeModalSectionID`), whose own shortcuts are then the
    ///     only ones that fire (``Scope``).
    package func trigger(
        for event: KeyEvent, activePane: String? = nil, reachesPage: Bool = true, modalSection: String? = nil
    ) -> Bool {
        if triggerOne(event, activePane: activePane, reachesPage: reachesPage, modalSection: modalSection) {
            return true
        }
        // A character Option composed (`ƒ` for ⌥F, where the terminal does not
        // send Option as Alt) is the Option chord on its key where nothing
        // binds the character: a menu's letter, ⌥? for every tooltip (the
        // owner's afternoon list #36 and #39, 2026-10-28).
        guard let chord = event.optionChord else { return false }
        return triggerOne(chord, activePane: activePane, reachesPage: reachesPage, modalSection: modalSection)
    }

    /// ``trigger(for:activePane:reachesPage:modalSection:)`` for `event` as it
    /// is.
    private func triggerOne(
        _ event: KeyEvent, activePane: String?, reachesPage: Bool, modalSection: String?
    ) -> Bool {
        guard let trigger = KeyboardShortcut.trigger(for: event) else { return false }
        let entry = appEntry(for: trigger, activePane: activePane, reachesPage: reachesPage, modalSection: modalSection)
        if event.phase == .repeat, let entry, !entry.repeats { return true }
        guard
            let action = entry?.action
                ?? defaultEntry(
                    for: trigger, activePane: activePane, reachesPage: reachesPage, modalSection: modalSection)?.action
        else { return false }
        action()
        return true
    }

    /// Whether an app shortcut is registered for `event`: what ``trigger(for:)``
    /// would match, without running anything.
    ///
    /// App shortcuts only. A framework default never takes a key from the
    /// control holding the focus, so it has no say here.
    ///
    /// For `InputHandler`, which asks it before offering a focused text control
    /// one of its editing chords. An app shortcut on the chord takes the key
    /// instead; see
    /// ``TextEditingCommand/givesWayToKeyboardShortcuts(homeAndEndReachLineEnds:)``.
    package func hasAppShortcut(
        for event: KeyEvent, activePane: String? = nil, reachesPage: Bool = true, modalSection: String? = nil
    ) -> Bool {
        guard let trigger = KeyboardShortcut.trigger(for: event) else { return false }
        return appEntry(for: trigger, activePane: activePane, reachesPage: reachesPage, modalSection: modalSection) != nil
    }

    /// Whether any shortcut is registered for `event`, the app's or a
    /// framework default: what ``trigger(for:)`` would match, without
    /// running anything. For the user's quit key, which the driver keeps
    /// unless a binding the framework can see is on a chord its byte could be
    /// for (`InputHandler.quitKeyBindings(byte:hostAliases:)`).
    ///
    /// On the page or in any pane, wherever the focus is: the driver's quit
    /// is set once a frame, for the whole screen, so a pane's binding masks it
    /// as the page's does. Which of them the key then reaches is the pane
    /// rule's (``trigger(for:activePane:reachesPage:)``).
    package func hasShortcut(for event: KeyEvent) -> Bool {
        guard let trigger = KeyboardShortcut.trigger(for: event) else { return false }
        return actions[trigger] != nil || defaults[trigger] != nil
            || paneActions.values.contains { $0[trigger] != nil }
            || paneDefaults.values.contains { $0[trigger] != nil }
    }
}

// MARK: - Assignment

/// The per-frame, claimable carrier ``View/keyboardShortcut(_:)-(KeyboardShortcut)``
/// plants in the environment.
///
/// A plain environment *value* would cascade to every button in the subtree —
/// `.keyboardShortcut(.defaultAction)` on a container would mark all of them.
/// A claimable box keeps SwiftUI's attach-to-one-control semantics: the first
/// button rendered under the modifier claims it (which is the wrapped button
/// itself when the modifier is attached directly, the only supported usage).
/// Main-loop-confined like the registry it feeds.
final class KeyboardShortcutAssignment: @unchecked Sendable {
    let shortcut: KeyboardShortcut

    /// Whether the control claiming it registers its action on the shortcut —
    /// `false` for a hint (``View/keyboardShortcutHint(_:)``), which a menu row
    /// prints and something else binds.
    let registers: Bool

    /// Who holds the claim, tracked SEPARATELY for measuring and for drawing.
    ///
    /// Keyed by identity rather than a bare "claimed" flag because a control
    /// asks more than once per frame: the measure pass needs the shortcut to
    /// size the space its hint occupies, and the render pass then needs it
    /// again to register the action. A one-shot claim would hand it to the
    /// measure and leave the render — the pass that actually registers — with
    /// nothing.
    ///
    /// Two latches rather than one because **a measure and a render need not lay
    /// the control out in the same place**, and one latch made the render's
    /// different identity look like a second control muscling in. A scrolling
    /// menu is exactly that: it measures its column bordered and hugging to
    /// decide whether it overflows, then draws the overflowing one inside a
    /// `ScrollView`, so every row's identity gains a component between the two
    /// passes. The measure claimed, the render was refused, and each row lost the
    /// key equivalent it had just been measured wide enough to print — silently,
    /// and only once the menu grew past its cap.
    private var measureClaimant: ViewIdentity?
    private var renderClaimant: ViewIdentity?

    /// How many value memos were recording where this carrier was last planted
    /// — `RenderContext.effectRecordingDepth` at that point in the walk.
    ///
    /// What it answers is whether the modifier sits INSIDE the memo that would
    /// store the control claiming it, which is what decides whether that
    /// control's registration can be replayed on a served frame. Stamped by
    /// `KeyboardShortcutModifier` on each plant rather than taken at init,
    /// because the carrier is built with the view value and the memo nesting is
    /// a property of where it is rendered.
    private var plantedAtEffectRecordingDepth = 0

    init(_ shortcut: KeyboardShortcut, registers: Bool = true) {
        self.shortcut = shortcut
        self.registers = registers
    }

    /// Records that this carrier was planted where `depth` value memos were
    /// recording.
    func planted(atEffectRecordingDepth depth: Int) {
        plantedAtEffectRecordingDepth = depth
    }

    /// Whether the memo now recording — the innermost of `recordingDepth` of
    /// them — is one this carrier was planted inside.
    ///
    /// Equal depths mean the modifier rendered below that memo's root, since a
    /// carrier is always an ancestor of the control claiming it and the depth
    /// only grows down the tree.
    func isPlanted(insideMemoAtDepth recordingDepth: Int) -> Bool {
        plantedAtEffectRecordingDepth == recordingDepth
    }

    /// Claims the assignment for the control at `identity`; returns nil if some
    /// other control already holds it for this kind of pass.
    ///
    /// - Parameters:
    ///   - identity: The claiming control's identity.
    ///   - isMeasuring: Whether this is a measuring pass (`RenderContext/isMeasuring`).
    ///     Measuring and drawing hold their claims independently — see the
    ///     latches above.
    func claim(by identity: ViewIdentity, isMeasuring: Bool) -> KeyboardShortcut? {
        if isMeasuring {
            if let measureClaimant, measureClaimant != identity { return nil }
            measureClaimant = identity
        } else {
            if let renderClaimant, renderClaimant != identity { return nil }
            renderClaimant = identity
        }
        return shortcut
    }
}

// MARK: - Environment

private struct KeyboardShortcutRegistryKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    static let defaultValue: KeyboardShortcutRegistry? = nil
}

private struct AssignedKeyboardShortcutKey: EnvironmentKey {
    static let defaultValue: KeyboardShortcutAssignment? = nil
}

extension EnvironmentValues {
    /// The app's semantic-shortcut registry (nil outside a running app).
    package var keyboardShortcutRegistry: KeyboardShortcutRegistry? {
        get { self[KeyboardShortcutRegistryKey.self] }
        set { self[KeyboardShortcutRegistryKey.self] = newValue }
    }

    /// The shortcut assignment awaiting a control, planted by
    /// ``View/keyboardShortcut(_:)-(KeyboardShortcut)``.
    var assignedKeyboardShortcut: KeyboardShortcutAssignment? {
        get { self[AssignedKeyboardShortcutKey.self] }
        set { self[AssignedKeyboardShortcutKey.self] = newValue }
    }

    /// The keyboard shortcut buttons in this environment are triggered with,
    /// or `nil` where none was assigned to the view or an ancestor — SwiftUI's
    /// `\.keyboardShortcut`.
    ///
    /// For a button style whose look depends on its shortcut, as SwiftUI's
    /// documentation shows — here a view the style's body draws:
    ///
    /// ```swift
    /// struct DefaultMark: View {
    ///     @Environment(\.keyboardShortcut) private var shortcut
    ///
    ///     var body: some View {
    ///         Text(shortcut == .defaultAction ? "▸" : " ")
    ///     }
    /// }
    /// ```
    ///
    /// Read-only, as SwiftUI's is: ``View/keyboardShortcut(_:)-(KeyboardShortcut)`` is how one is
    /// assigned.
    public var keyboardShortcut: KeyboardShortcut? {
        assignedKeyboardShortcut?.shortcut
    }
}
