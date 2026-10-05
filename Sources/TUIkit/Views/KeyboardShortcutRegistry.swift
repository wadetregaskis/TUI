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
/// `@unchecked Sendable` like its sibling per-frame services
/// (`MouseEventDispatcher`, `KeyEventDispatcher`): touched only from the
/// main run loop (render pass registration + input dispatch).
final class KeyboardShortcutRegistry: @unchecked Sendable {
    /// An app shortcut's action, and whether a held key's repeats run it again.
    private struct Entry {
        let repeats: Bool
        let action: () -> Void
    }

    private var actions: [KeyboardShortcut.Trigger: Entry] = [:]

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
        defaults.removeAll(keepingCapacity: true)
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
        actions[shortcut.trigger] = Entry(repeats: repeats, action: action)
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
    func trigger(for event: KeyEvent) -> Bool {
        guard let trigger = KeyboardShortcut.trigger(for: event) else { return false }
        if event.phase == .repeat, let entry = actions[trigger], !entry.repeats { return true }
        return run(trigger)
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
    func hasAppShortcut(for event: KeyEvent) -> Bool {
        guard let trigger = KeyboardShortcut.trigger(for: event) else { return false }
        return actions[trigger] != nil
    }

    /// Runs the registered action for `trigger`, reporting whether there was one:
    /// the app's, else the framework default's.
    private func run(_ trigger: KeyboardShortcut.Trigger) -> Bool {
        guard let action = actions[trigger]?.action ?? defaults[trigger]?.action else { return false }
        action()
        return true
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
