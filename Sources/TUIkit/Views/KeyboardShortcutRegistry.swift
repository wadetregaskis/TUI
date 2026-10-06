//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// button. Where no pane is drawn, nothing here changes.
///
/// `@unchecked Sendable` like its sibling per-frame services
/// (`MouseEventDispatcher`, `KeyEventDispatcher`): touched only from the
/// main run loop (render pass registration + input dispatch).
final class KeyboardShortcutRegistry: @unchecked Sendable {
    /// An app shortcut's action, whether a held key's repeats run it again,
    /// and when in the frame it was registered (``registrationCount``).
    struct Entry {
        let repeats: Bool
        let action: () -> Void
        let serial: Int
    }

    /// The app's shortcuts registered outside every pane.
    private var actions: [KeyboardShortcut.Trigger: Entry] = [:]

    /// The app's shortcuts registered inside each pane, by the pane.
    private var paneActions: [String: [KeyboardShortcut.Trigger: Entry]] = [:]

    /// The pane whose content is rendering now, if any: set around it by
    /// `renderingPane(_:context:_:)`, so what registers meanwhile is the
    /// pane's.
    var currentPane: String?

    /// How many app shortcuts this frame has registered so far: a mark a
    /// presenter takes before its content renders, and hands back to
    /// ``entry(for:registeredAfter:)`` once it has.
    private(set) var registrationCount = 0

    /// A framework default, and whether the view that registered it held the
    /// focus.
    private struct Default {
        let holdsFocus: Bool
        let action: () -> Void
    }

    /// The framework defaults, consulted only when no app shortcut has the
    /// trigger.
    private var defaults: [KeyboardShortcut.Trigger: Default] = [:]

    /// Clears the frame's registrations (called from the render loop).
    func beginRenderPass() {
        actions.removeAll(keepingCapacity: true)
        if !paneActions.isEmpty { paneActions.removeAll() }
        currentPane = nil
        defaults.removeAll(keepingCapacity: true)
        registrationCount = 0
    }

    /// Registers `action` for `shortcut`; the last registration in a frame wins.
    ///
    /// - Parameter repeats: Whether a held key's repeats run the action again.
    ///   A repeat is told from a press only where the terminal speaks the kitty
    ///   keyboard protocol; in a legacy encoding every repeat is a press and
    ///   runs it. A repeat that does not run it is still taken, so it reaches
    ///   nothing else: holding a button's shortcut never falls through to
    ///   whatever the key means further down.
    func register(_ shortcut: KeyboardShortcut, repeats: Bool = true, action: @escaping () -> Void) {
        registrationCount += 1
        let entry = Entry(repeats: repeats, action: action, serial: registrationCount)
        if let currentPane {
            paneActions[currentPane, default: [:]][shortcut.trigger] = entry
        } else {
            actions[shortcut.trigger] = entry
        }
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
    private func appEntry(for trigger: KeyboardShortcut.Trigger, activePane: String?) -> Entry? {
        guard let activePane else { return actions[trigger] }
        if let entry = paneActions[activePane]?[trigger] { return entry }
        switch trigger {
        case .defaultAction, .cancelAction: return nil
        case .key: return actions[trigger]
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
    func registerDefault(
        _ shortcut: KeyboardShortcut, holdsFocus: Bool = false, action: @escaping () -> Void
    ) {
        if let existing = defaults[shortcut.trigger], existing.holdsFocus || !holdsFocus { return }
        defaults[shortcut.trigger] = Default(holdsFocus: holdsFocus, action: action)
    }

    /// Runs the action matching a fallen-through key event, if any.
    ///
    /// Unmodified Return/Escape drive the two semantic roles; a character key
    /// drives a key equivalent whose modifiers match exactly what the terminal
    /// reported. Exactly, not "at least": a shortcut on plain "q" must not fire
    /// on Ctrl-Q. The event → trigger rule itself is
    /// ``KeyboardShortcut/trigger(for:)``, shared with the row-shortcut table.
    ///
    /// - Parameter activePane: The pane the focus is in
    ///   (`FocusManager.activePaneID`), or `nil` on the page.
    func trigger(for event: KeyEvent, activePane: String? = nil) -> Bool {
        guard let trigger = KeyboardShortcut.trigger(for: event) else { return false }
        let entry = appEntry(for: trigger, activePane: activePane)
        if event.phase == .repeat, let entry, !entry.repeats { return true }
        guard let action = entry?.action ?? defaults[trigger]?.action else { return false }
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
    func hasAppShortcut(for event: KeyEvent, activePane: String? = nil) -> Bool {
        guard let trigger = KeyboardShortcut.trigger(for: event) else { return false }
        return appEntry(for: trigger, activePane: activePane) != nil
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

    init(_ shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
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

private struct KeyboardShortcutRegistryKey: EnvironmentKey {
    static let defaultValue: KeyboardShortcutRegistry? = nil
}

private struct AssignedKeyboardShortcutKey: EnvironmentKey {
    static let defaultValue: KeyboardShortcutAssignment? = nil
}

extension EnvironmentValues {
    /// The app's semantic-shortcut registry (nil outside a running app).
    var keyboardShortcutRegistry: KeyboardShortcutRegistry? {
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
